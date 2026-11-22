//
//  TabManagerImpl.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
import Network
import UIKit

final class TabManagerImplementation: NSObject, TabManager {
    private(set) var regularTabs: [Tab] = []
    private(set) var privateTabs: [Tab] = []
    private(set) var selectedTabMode: TabMode = .regular
    private var selectedRegularTabIndex = -1
    private var selectedPrivateTabIndex = -1
    
    var selectedTabIndex: Int {
        return selectedIndex(for: selectedTabMode)
    }
    
    var selectedTab: Tab? {
        return tabs(for: selectedTabMode)[safe: selectedTabIndex]
    }
    
    private lazy var requestContentKeyboardFocus: (GeckoSession) -> Void = { [weak self] session in
        guard let self else { return }
        self.delegate?.tabManager(self, didRequestContentKeyboardFocusFor: session)
    }
    private lazy var promptCoordinator = PromptCoordinator(
        presenter: PromptPresenter(),
        onPromptFinished: requestContentKeyboardFocus
    )
    private lazy var pagePrintCoordinator = PagePrintCoordinator { [weak self] session in
        return self?.tab(for: session)?.title
    }
    private lazy var selectionActionCoordinator = SelectionActionCoordinator(
        presenter: SelectionActionPresenter(
            onMenuDismissed: requestContentKeyboardFocus,
            onFindInPage: { [weak self] session, query in
                guard let self else { return }
                self.delegate?.tabManager(self, didRequestFindInPage: query, in: session)
            }
        )
    )
    private lazy var permissionCoordinator = PermissionCoordinator(
        promptPresenter: PermissionPromptPresenter(),
        onPromptFinished: requestContentKeyboardFocus
    )
    private(set) lazy var readerMode = ReaderModeController(delegate: self)
    private lazy var systemMediaSession = SystemMediaSession(playbackObserver: self)
    
    private weak var delegate: TabManagerDelegate?
    private let store: TabManagementStore
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    let sessionManager: SessionManager
    private let networkMonitor = NWPathMonitor()
    private var faviconTasks: [UUID: Task<Void, Never>] = [:]
    private var selectionCounter = 0
    
    private lazy var lenientURLExpression: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    init(
        delegate: TabManagerDelegate?,
        sessionManager: SessionManager,
        store: TabManagementStore = .shared,
        faviconStore: FaviconStore = .shared,
        historyStore: HistoryStore = .shared
    ) {
        self.delegate = delegate
        self.sessionManager = sessionManager
        self.store = store
        self.faviconStore = faviconStore
        self.historyStore = historyStore
        super.init()
        
        networkMonitor.start(queue: .global(qos: .utility))
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Application Lifecycle
    
    func applicationDidBecomeActive() {
        guard selectedTab?.session.isOpen() == false else {
            return
        }
        
        if let selectedTab {
            selectTab(selectedTab)
        }
    }
    
    // MARK: - Persistence And Lookup
    
    private func cancelFaviconTask(for tabID: UUID) {
        faviconTasks.removeValue(forKey: tabID)?.cancel()
    }
    
    private func persistState() {
        store.persistTabs(
            regularTabs: regularTabs,
            privateTabs: privateTabs,
            selectedRegularTabID: regularTabs[safe: selectedRegularTabIndex]?.id,
            selectedPrivateTabID: privateTabs[safe: selectedPrivateTabIndex]?.id,
            selectedTabMode: selectedTabMode
        )
    }
    
    func tabs(for mode: TabMode) -> [Tab] {
        switch mode {
        case .regular:
            return regularTabs
        case .private:
            return privateTabs
        }
    }
    
    private func selectedIndex(for mode: TabMode) -> Int {
        switch mode {
        case .regular:
            return selectedRegularTabIndex
        case .private:
            return selectedPrivateTabIndex
        }
    }
    
    private func setSelectedIndex(_ index: Int, for mode: TabMode) {
        switch mode {
        case .regular:
            selectedRegularTabIndex = index
        case .private:
            selectedPrivateTabIndex = index
        }
    }
    
    private func tab(for session: GeckoSession) -> Tab? {
        return regularTabs.first { $0.session === session } ?? privateTabs.first { $0.session === session }
    }
    
    private func tab(withID tabID: UUID) -> Tab? {
        return regularTabs.first { $0.id == tabID } ?? privateTabs.first { $0.id == tabID }
    }
    
    private func index(of tab: Tab) -> Int? {
        return tabs(for: tab.mode).firstIndex { $0 === tab }
    }
    
    private func notifyUpdate(for tab: Tab, reason: TabManagerUpdateReason) {
        guard index(of: tab) != nil else {
            return
        }
        
        if tab.mode == selectedTabMode {
            delegate?.tabManager(self, didUpdate: tab, reason: reason)
        } else {
            delegate?.tabManagerDidChangeTabs(self)
        }
    }
    
    // MARK: - Navigation State
    
    private func loadURL(_ url: String, in tab: Tab) {
        tab.state.loadError = nil
        tab.state.restoreState = .none
        tab.state.showsStartupHomepage = false
        tab.state.loadingState = .loading(progress: 0)
        notifyUpdate(for: tab, reason: .loading)
        sessionManager.updateSettings(of: tab.session, for: url, tabID: tab.id)
        tab.session.load(url)
    }
    
    private func matchingHistoryEntry(for tab: Tab) -> GeckoSessionHistoryIdentifier? {
        guard let sessionState = tab.state.tabSessionState,
              let currentHistoryIndex = sessionState.currentHistoryIndex,
              let entry = sessionState.history[safe: currentHistoryIndex],
              entry.url == tab.state.committedEngineURL else {
            return nil
        }
        return entry.identifier
    }
    
    // MARK: - Session Creation
    
    private func makeTab(windowId: String?, isPrivate: Bool) -> Tab {
        let tabID = UUID()
        return Tab(
            id: tabID,
            session: createSession(tabID: tabID, url: nil, windowId: windowId, isPrivate: isPrivate),
            isPrivate: isPrivate
        )
    }
    
    private var sessionDelegates: SessionDelegates {
        return SessionDelegates(
            content: self,
            navigation: self,
            history: self,
            permission: permissionCoordinator,
            progress: self,
            scroll: self,
            prompt: promptCoordinator,
            print: pagePrintCoordinator,
            selectionAction: selectionActionCoordinator,
            mediaSession: systemMediaSession
        )
    }
    
    // MARK: - Transferred Tabs
    
    private func applyTransferredState(to tab: Tab, url: String, title: String?) {
        tab.url = url
        if let title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab.title = title
        }
        tab.state.displayState = .committed
        tab.state.suppressInitialNavigation = true
        tab.favicon = cachedFavicon(for: url)
    }
    
    private func recordTransferredHistory(for tab: Tab, title: String?) {
        guard !tab.isPrivate,
              let url = remoteURL(from: tab.url) else {
            return
        }
        
        historyStore.recordVisit(url: url, title: tab.title)
        if let title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            historyStore.updatePageTitle(for: url, title: title)
        }
    }
    
    // MARK: - URL Resolution
    
    private func restoredURL(from value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty,
              trimmedValue.lowercased() != "about:blank" else {
            return nil
        }
        
        return trimmedValue
    }
    
    private func displayedURL(for tab: Tab) -> String? {
        switch tab.state.displayState {
        case let .pending(url):
            return restoredURL(from: url)
        case .committed:
            return restoredURL(from: tab.url)
        }
    }
    
    private func hasDisplayURL(for tab: Tab) -> Bool {
        return displayedURL(for: tab) != nil
    }
    
    private func remoteURL(from value: String?) -> URL? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        
        return url
    }
    
    // MARK: - Favicons
    
    private func cachedFavicon(for value: String?) -> UIImage? {
        guard let url = remoteURL(from: value) else {
            return nil
        }
        
        return faviconStore.cachedFavicon(for: url)
    }
    
    private func scheduleFaviconUpdate(for tab: Tab) {
        cancelFaviconTask(for: tab.id)
        
        let cachedImage = cachedFavicon(for: tab.url)
        tab.favicon = cachedImage
        notifyUpdate(for: tab, reason: .favicon)
        
        guard cachedImage == nil,
              let url = remoteURL(from: tab.url) else {
            return
        }
        
        let tabID = tab.id
        let expectedURL = url.absoluteString
        faviconTasks[tabID] = Task { [weak self] in
            guard let self else {
                return
            }
            
            let image = await self.faviconStore.favicon(for: url)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                self.applyResolvedFavicon(image, toTabWithID: tabID, expectedURL: expectedURL)
            }
        }
    }
    
    @MainActor
    private func applyResolvedFavicon(_ image: UIImage?, toTabWithID tabID: UUID, expectedURL: String) {
        defer {
            faviconTasks.removeValue(forKey: tabID)
        }
        
        guard let tab = tab(withID: tabID),
              tab.url == expectedURL else {
            return
        }
        
        tab.favicon = image
        notifyUpdate(for: tab, reason: .favicon)
    }
    
    // MARK: - Tab Restoration
    
    private func restorableSessionState(
        _ sessionState: GeckoSessionState?,
        matching url: String? = nil
    ) -> GeckoSessionState? {
        guard let sessionState,
              let currentHistoryIndex = sessionState.currentHistoryIndex else {
            return nil
        }
        let history = sessionState.history
        guard history.indices.contains(currentHistoryIndex) else {
            return nil
        }
        let currentURL = history[currentHistoryIndex].url
        guard restoredURL(from: currentURL) != nil,
              url == nil || currentURL == url else {
            return nil
        }
        return sessionState
    }
    
    private func prepareRestoration(
        serializedSessionState: String?,
        fallbackURL: String?,
        for tab: Tab
    ) {
        if !tab.isPrivate,
           let serializedSessionState,
           let decodedSessionState = GeckoSessionState(serializedString: serializedSessionState),
           let sessionState = restorableSessionState(decodedSessionState) {
            tab.state.tabSessionState = sessionState
            tab.state.navigationState = NavigationAvailability(
                canGoBack: !sessionState.backHistory.isEmpty,
                canGoForward: !sessionState.forwardHistory.isEmpty
            )
            tab.state.restoreState = .pendingSession
            return
        }
        tab.state.restoreState = restoredURL(from: fallbackURL).map(TabRestoreState.pendingURL) ?? .none
    }
    
    private func prepareRestoration(for tab: Tab) {
        if let sessionState = restorableSessionState(tab.state.tabSessionState) {
            tab.state.tabSessionState = sessionState
            tab.state.restoreState = .pendingSession
        } else {
            tab.state.tabSessionState = nil
            tab.state.restoreState = restoredURL(from: tab.url).map(TabRestoreState.pendingURL) ?? .none
        }
    }
    
    private func restoreTabsIfNeeded() -> Bool {
        guard regularTabs.isEmpty && privateTabs.isEmpty else {
            return true
        }
        
        let snapshot = store.currentSnapshot()
        guard !snapshot.regularTabs.isEmpty || !snapshot.privateTabs.isEmpty else {
            return false
        }
        
        regularTabs = snapshot.regularTabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                session: createSession(
                    tabID: snapshot.id,
                    url: snapshot.url,
                    windowId: nil,
                    isPrivate: false,
                    opening: .manual
                ),
                title: snapshot.title,
                url: snapshot.url,
                createdAt: snapshot.createdAt,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isMuted: snapshot.isMuted,
                isPrivate: false
            )
            tab.state.openerTabID = snapshot.openerTabID
            prepareRestoration(
                serializedSessionState: snapshot.tabSessionState,
                fallbackURL: snapshot.url,
                for: tab
            )
            return tab
        }
        
        privateTabs = snapshot.privateTabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                session: createSession(
                    tabID: snapshot.id,
                    url: snapshot.url,
                    windowId: nil,
                    isPrivate: true,
                    opening: .manual
                ),
                title: snapshot.title,
                url: snapshot.url,
                createdAt: snapshot.createdAt,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isMuted: snapshot.isMuted,
                isPrivate: true
            )
            prepareRestoration(
                serializedSessionState: snapshot.tabSessionState,
                fallbackURL: snapshot.url,
                for: tab
            )
            return tab
        }
        
        selectedRegularTabIndex = snapshot.selectedRegularTabID.flatMap { selectedTabID in
            regularTabs.firstIndex(where: { $0.id == selectedTabID })
        } ?? (regularTabs.isEmpty ? -1 : 0)
        
        selectedPrivateTabIndex = snapshot.selectedPrivateTabID.flatMap { selectedTabID in
            privateTabs.firstIndex(where: { $0.id == selectedTabID })
        } ?? (privateTabs.isEmpty ? -1 : 0)
        
        selectedTabMode = snapshot.selectedTabMode
        
        if tabs(for: selectedTabMode).isEmpty {
            selectedTabMode = regularTabs.isEmpty ? .private : .regular
        }
        
        let selectedIndex = max(selectedIndex(for: selectedTabMode), 0)
        let selectedTab = tabs(for: selectedTabMode)[selectedIndex]
        
        if Prefs.HomepageSettings.openingScreen == .lastTab,
           sessionManager.isForeground {
            restoreTabIfNeeded(selectedTab)
            sessionManager.open(selectedTab.session)
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        selectTab(selectedTab)
        return true
    }
    
    private func restoreTabIfNeeded(_ tab: Tab) {
        switch tab.state.restoreState {
        case .pendingSession:
            guard let sessionState = tab.state.tabSessionState else {
                return
            }
            tab.state.restoreState = .none
            tab.state.loadingState = .loading(progress: 0)
            tab.session.restoreState(sessionState)
        case let .pendingURL(url):
            tab.state.suppressInitialNavigation = false
            loadURL(url, in: tab)
        case .none:
            break
        }
    }
    
    @discardableResult
    func restoreRecentlyClosedTab(id: UUID) -> Bool {
        guard let snapshot = store.takeRecentlyClosedTab(id: id) else {
            return false
        }
        
        let tab = Tab(
            id: snapshot.id,
            session: createSession(
                tabID: snapshot.id,
                url: snapshot.url,
                windowId: nil,
                isPrivate: false
            ),
            title: snapshot.title,
            url: snapshot.url,
            favicon: cachedFavicon(for: snapshot.url),
            isPrivate: false
        )
        prepareRestoration(
            serializedSessionState: snapshot.tabSessionState,
            fallbackURL: snapshot.url,
            for: tab
        )
        
        regularTabs.append(tab)
        delegate?.tabManagerDidChangeTabs(self)
        selectedTabMode = .regular
        delegate?.tabManager(self, animateNewTabSelectionTo: tab) { [weak self] in
            self?.selectTab(tab)
        }
        return true
    }
    
    // MARK: - Session Recovery
    
    private func recoverSelectedSessionIfNeeded() {
        guard sessionManager.isForeground,
              let tab = selectedTab,
              !tab.session.isOpen() else {
            return
        }
        
        let previousSession = tab.session
        let replacementSession = createSession(
            tabID: tab.id,
            url: tab.url,
            windowId: nil,
            isPrivate: tab.isPrivate,
            opening: .manual
        )
        tab.session = replacementSession
        
        restoreTabIfNeeded(tab)
        
        sessionManager.open(replacementSession)
        delegate?.tabManager(
            self,
            didReplaceSelectedSession: previousSession,
            with: replacementSession
        )
    }
    
    private func handleSessionTermination(_ session: GeckoSession, recoverAutomatically: Bool) {
        DownloadStore.shared.failCapturedDownloads(for: session)
        sessionManager.clearExternalResponseRetention(for: session)
        
        guard let tab = tab(for: session) else {
            return
        }
        
        let didTerminateSelectedTab = selectedTab?.session === session
        if let sessionState = session.currentSessionState {
            tab.state.tabSessionState = sessionState
        }
        sessionManager.close(session)
        prepareRestoration(for: tab)
        tab.state.loadingState = .idle
        tab.state.loadError = WebRequestError(kind: .contentCrashed, uri: displayedURL(for: tab))
        notifyUpdate(for: tab, reason: .loadError)
        notifyUpdate(for: tab, reason: .loading)
        persistState()
        
        guard didTerminateSelectedTab,
              sessionManager.isApplicationActive else {
            return
        }
        
        if recoverAutomatically {
            selectTab(tab)
        } else {
            delegate?.tabManagerDidTerminateSelectedTab(self)
        }
    }
    
    // MARK: - Tab Lifecycle
    
    private func saveClosedTabIfNeeded(_ tab: Tab) {
        guard !tab.isPrivate,
              let url = displayedURL(for: tab) else {
            return
        }
        
        store.saveRecentlyClosedTab(
            id: tab.id,
            title: tab.title,
            url: url,
            tabSessionState: tab.state.tabSessionState?.serializedString()
        )
    }
    
    private func insert(_ tab: Tab, at insertionIndex: Int?) {
        let mode = tab.mode
        let count = tabs(for: mode).count
        let index = min(max(insertionIndex ?? count, 0), count)
        switch mode {
        case .regular:
            regularTabs.insert(tab, at: index)
        case .private:
            privateTabs.insert(tab, at: index)
        }
        
        if selectedIndex(for: mode) >= index {
            setSelectedIndex(selectedIndex(for: mode) + 1, for: mode)
        }
    }
    
    func createInitialTab() {
        switch Prefs.HomepageSettings.openingScreen {
        case .lastTab:
            if !restoreTabsIfNeeded() {
                addTab(selecting: true, windowId: nil, at: nil, isPrivate: false)
            }
        case .homepage:
            createHomepageInitialTab()
        }
    }
    
    private func createHomepageInitialTab() {
        let didRestoreTabs = restoreTabsIfNeeded()
        
        if didRestoreTabs,
           let lastTab = regularTabs.last,
           displayedURL(for: lastTab) == nil {
            lastTab.state.showsStartupHomepage = true
            if selectedTab?.id != lastTab.id {
                selectTab(lastTab)
            }
            return
        }
        
        if didRestoreTabs,
           let selectedTab,
           displayedURL(for: selectedTab) == nil {
            selectedTab.state.showsStartupHomepage = true
            return
        }
        
        let tab = addTab(selecting: true, windowId: nil, at: nil, isPrivate: false)
        tab.state.showsStartupHomepage = true
    }
    
    @discardableResult
    func addTab(selecting: Bool, windowId: String? = nil, at insertionIndex: Int? = nil, isPrivate: Bool = false) -> Tab {
        let tab = makeTab(windowId: windowId, isPrivate: isPrivate)
        insert(tab, at: insertionIndex)
        
        if selecting {
            selectTab(tab)
        } else {
            persistState()
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        return tab
    }
    
    @discardableResult
    func addTransferredSession(_ session: GeckoSession, url: String, title: String?, selecting: Bool, at insertionIndex: Int?, isPrivate: Bool = false) -> Tab {
        let tab = Tab(session: session, isPrivate: isPrivate)
        tab.state.openerTabID = !isPrivate && selectedTab?.isPrivate == false ? selectedTab?.id : nil
        let sessionState = restorableSessionState(session.currentSessionState, matching: url)
        tab.state.tabSessionState = sessionState
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates)
        readerMode.registerMessageHandlers(for: session)
        applyTransferredState(to: tab, url: url, title: title)
        
        insert(tab, at: insertionIndex)
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(for: tab, reason: .location)
        notifyUpdate(for: tab, reason: .title)
        scheduleFaviconUpdate(for: tab)
        recordTransferredHistory(for: tab, title: title)
        if selecting {
            if let previousSession = selectedTab?.session,
               previousSession !== session {
                sessionManager.deactivate(previousSession)
            }
            selectedTabMode = tab.mode
            delegate?.tabManager(self, animateNewTabSelectionTo: tab) { [weak self] in
                self?.selectTab(tab)
            }
        } else {
            persistState()
        }
        
        return tab
    }
    
    func selectTab(_ tab: Tab) {
        guard let index = index(of: tab) else {
            return
        }
        
        let previousTab = selectedTab
        let previousTabInMode = selectedTabMode == tab.mode ? previousTab : nil
        
        selectedTabMode = tab.mode
        selectionCounter += 1
        setSelectedIndex(index, for: tab.mode)
        tab.state.selectionOrder = selectionCounter
        if previousTab?.session !== tab.session,
           let previousSession = previousTab?.session {
            sessionManager.deactivate(previousSession)
        }
        recoverSelectedSessionIfNeeded()
        restoreTabIfNeeded(tab)
        sessionManager.activate(tab.session)
        tab.session.mediaSession.muteAudio(tab.isMuted)
        systemMediaSession.select(session: tab.session)
        
        delegate?.tabManager(self, didSelect: tab, previous: previousTabInMode)
        persistState()
    }
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard tabs(for: mode).indices.contains(sourceIndex),
              tabs(for: mode).indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }
        
        let selectedTabID = tabs(for: mode)[safe: selectedIndex(for: mode)]?.id
        if mode == .regular {
            let movedTab = regularTabs.remove(at: sourceIndex)
            regularTabs.insert(movedTab, at: destinationIndex)
        } else {
            let movedTab = privateTabs.remove(at: sourceIndex)
            privateTabs.insert(movedTab, at: destinationIndex)
        }
        
        if let selectedTabID,
           let selectedIndex = tabs(for: mode).firstIndex(where: { $0.id == selectedTabID }) {
            setSelectedIndex(selectedIndex, for: mode)
        }
        
        persistState()
    }
    
    func removeTab(_ tab: Tab, behavior: TabRemovalBehavior) {
        guard let index = index(of: tab) else {
            return
        }
        
        let mode = tab.mode
        let isRemovingSelectedTab = mode == selectedTabMode && index == selectedTabIndex
        let removedTab: Tab
        if mode == .regular {
            removedTab = regularTabs.remove(at: index)
        } else {
            removedTab = privateTabs.remove(at: index)
        }
        
        defer {
            delegate?.tabManagerDidChangeTabs(self)
            sessionManager.discard(removedTab.session, forTab: removedTab.id, keepingHistory: mode == .regular)
        }
        
        saveClosedTabIfNeeded(removedTab)
        
        if isRemovingSelectedTab {
            sessionManager.deactivate(removedTab.session)
        }
        cancelFaviconTask(for: removedTab.id)
        
        if tabs(for: mode).isEmpty {
            setSelectedIndex(-1, for: mode)
        } else if index < selectedIndex(for: mode) {
            setSelectedIndex(selectedIndex(for: mode) - 1, for: mode)
        }
        
        if regularTabs.isEmpty && privateTabs.isEmpty {
            persistState()
            return
        }
        
        guard isRemovingSelectedTab else {
            persistState()
            return
        }
        
        let remainingTabs = tabs(for: mode)
        let replacementLocation: (mode: TabMode, index: Int)?
        
        if !remainingTabs.isEmpty {
            switch behavior {
            case .adjacent:
                replacementLocation = (mode, min(index, remainingTabs.count - 1))
            case .recent, .none:
                let mostRecentlySelectedIndex = remainingTabs.indices
                    .filter { remainingTabs[$0].state.selectionOrder > 0 }
                    .max { remainingTabs[$0].state.selectionOrder < remainingTabs[$1].state.selectionOrder }
                replacementLocation = (mode, mostRecentlySelectedIndex ?? min(index, remainingTabs.count - 1))
            }
        } else if mode == .private && !regularTabs.isEmpty {
            replacementLocation = (.regular, max(selectedIndex(for: .regular), 0))
        } else {
            replacementLocation = nil
        }
        
        guard let replacementLocation else {
            persistState()
            return
        }
        
        switch behavior {
        case .recent, .adjacent:
            selectTab(tabs(for: replacementLocation.mode)[replacementLocation.index])
        case .none:
            selectedTabMode = replacementLocation.mode
            setSelectedIndex(replacementLocation.index, for: replacementLocation.mode)
            persistState()
        }
    }
    
    func removeAllTabs(mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard !tabs(for: mode).isEmpty else {
            return
        }
        
        if mode == selectedTabMode,
           let selectedSession = selectedTab?.session {
            sessionManager.deactivate(selectedSession)
        }
        let removedTabs = tabs(for: mode)
        if mode == .regular {
            regularTabs.removeAll(keepingCapacity: true)
            selectedRegularTabIndex = -1
        } else {
            privateTabs.removeAll(keepingCapacity: true)
            selectedPrivateTabIndex = -1
        }
        removedTabs.forEach { saveClosedTabIfNeeded($0) }
        removedTabs.forEach { cancelFaviconTask(for: $0.id) }
        let fallbackMode: TabMode = mode == .regular ? .private : .regular
        if mode == selectedTabMode,
           !tabs(for: fallbackMode).isEmpty {
            selectTab(tabs(for: fallbackMode)[max(selectedIndex(for: fallbackMode), 0)])
        } else {
            persistState()
        }
        delegate?.tabManagerDidChangeTabs(self)
        
        removedTabs.forEach { sessionManager.discard($0.session, forTab: $0.id, keepingHistory: mode == .regular) }
    }
    
    // MARK: - Browsing
    
    func browse(to term: String) {
        guard let tab = selectedTab else {
            return
        }
        browse(to: term, in: tab)
    }
    
    func browse(to term: String, in tab: Tab) {
        let navigationInput = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !navigationInput.isEmpty else {
            return
        }
        
        if selectedTab === tab {
            recoverSelectedSessionIfNeeded()
        }
        guard tab.session.isOpen() else {
            return
        }
        
        tab.state.suppressInitialNavigation = false
        tab.state.displayState = .pending(navigationInput)
        notifyUpdate(for: tab, reason: .location)
        
        let navigationInputRange = NSRange(location: 0, length: (navigationInput as NSString).length)
        let shouldNavigateDirectly = lenientURLExpression.firstMatch(in: navigationInput, range: navigationInputRange) != nil
        
        if shouldNavigateDirectly {
            loadURL(URLUtils.fixTLDTypo(in: navigationInput), in: tab)
            return
        }
        
        let searchDestination = SearchEngine.destination(for: navigationInput)
        loadURL(searchDestination, in: tab)
    }
    
    // MARK: - History Navigation
    
    func goBack() {
        guard let tab = selectedTab else {
            return
        }
        
        if !tab.state.navigationState.canGoBack, let openerTab {
            delegate?.tabManager(self, animateReturnTo: openerTab) { [weak self] in
                guard let self,
                      self.selectedTab === tab,
                      self.index(of: openerTab) != nil else {
                    return
                }
                self.selectTab(openerTab)
                self.removeTab(tab, behavior: .none)
            }
            return
        }
        
        tab.session.goBack()
    }
    
    func goBack(to index: Int) {
        guard let tab = selectedTab,
              let currentHistoryIndex = displayedSessionState(for: tab)?.currentHistoryIndex else {
            return
        }
        
        tab.session.goToHistoryIndex(currentHistoryIndex - index - 1)
    }
    
    func goForward() {
        selectedTab?.session.goForward()
    }
    
    func goForward(to index: Int) {
        guard let tab = selectedTab,
              let currentHistoryIndex = displayedSessionState(for: tab)?.currentHistoryIndex else {
            return
        }
        
        tab.session.goToHistoryIndex(currentHistoryIndex + index + 1)
    }
    
    func displayedSessionState(for tab: Tab) -> GeckoSessionState? {
        guard tab.state.displayedHistoryEntry != nil,
              matchingHistoryEntry(for: tab) == tab.state.displayedHistoryEntry else {
            return nil
        }
        return tab.state.tabSessionState
    }
    
    // MARK: - Preview Adoption
    
    func adoptPreview(_ previewSession: GeckoSession, url: String, title: String?) {
        guard let tab = selectedTab else {
            sessionManager.close(previewSession)
            return
        }
        
        if let currentURL = tab.url {
            delegate?.tabManager(
                self,
                captureHistoryThumbnailFor: tab,
                url: currentURL
            )
            tab.state.preparedNavigationThumbnailURL = currentURL
        }
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            do {
                try await tab.session.adoptPreview(previewSession)
                if !tab.isPrivate,
                   let pageURL = remoteURL(from: url) {
                    historyStore.recordVisit(url: pageURL, title: title ?? "")
                }
            } catch {
                NSLog("Failed to adopt link preview: %@", "\(error)")
                loadURL(url, in: tab)
            }
            sessionManager.close(previewSession)
        }
    }
    
    // MARK: - Tab Queries And Updates
    
    func shareableURL(for tab: Tab) -> URL? {
        guard let value = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "about:blank",
              let url = URL(string: value),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }
    
    func updateThumbnail(_ image: UIImage?, for tab: Tab) {
        guard index(of: tab) != nil else {
            return
        }
        
        tab.thumbnail = image
        store.persistThumbnail(image, for: tab.id)
        notifyUpdate(for: tab, reason: .thumbnail)
    }
    
    func updateHistoryThumbnail(
        _ image: UIImage,
        for tab: Tab,
        url: String,
        isPreparedForNavigation: Bool
    ) {
        let tabID = tab.id
        if isPreparedForNavigation {
            tab.state.preparedNavigationThumbnailURL = url
        }
        guard let entry = tab.state.displayedHistoryEntry else {
            return
        }
        
        NavigationHistoryStore.shared.updateThumbnail(
            image,
            for: entry,
            in: tab.state.tabSessionState?.history.compactMap(\.identifier) ?? [],
            tabID: tabID
        ) { [weak self] in
            self?.notifyUpdate(for: tab, reason: .navigationState)
        }
    }
    
    func navigationPreviewImages(for tab: Tab) -> NavigationPreviewImages {
        guard let sessionState = displayedSessionState(for: tab) else {
            return NavigationPreviewImages(backImage: nil, forwardImage: nil)
        }
        
        let navigationHistoryStore = NavigationHistoryStore.shared
        return NavigationPreviewImages(
            backImage: navigationHistoryStore.thumbnail(for: sessionState.backHistory.first?.identifier, in: tab.id),
            forwardImage: navigationHistoryStore.thumbnail(for: sessionState.forwardHistory.first?.identifier, in: tab.id)
        )
    }
    
    func invalidateNavigationThumbnails() {
        NavigationHistoryStore.shared.invalidateThumbnails()
    }
    
    func setMuted(_ muted: Bool, for tabID: UUID) {
        guard let tab = tab(withID: tabID),
              tab.isMuted != muted else {
            return
        }
        tab.isMuted = muted
        if tab.session.isOpen() {
            tab.session.mediaSession.muteAudio(muted)
        }
        persistState()
        notifyUpdate(for: tab, reason: .audio)
    }
    
    func muteOtherPlayingTabs(excluding tabID: UUID) {
        for tab in tabs(for: selectedTabMode) where tab.id != tabID && tab.state.isPlayingAudio && !tab.isMuted {
            setMuted(true, for: tab.id)
        }
    }
    
    // MARK: - Session Factory
    
    private func createSession(
        tabID: UUID,
        url: String?,
        windowId: String?,
        isPrivate: Bool,
        opening: SessionOpening? = nil
    ) -> GeckoSession {
        let session = sessionManager.createSession(
            url: url,
            tabID: tabID,
            isPrivate: isPrivate,
            opening: opening ?? .immediate(windowID: windowId),
            delegates: sessionDelegates
        )
        readerMode.registerMessageHandlers(for: session)
        return session
    }
}

extension TabManagerImplementation: SystemMediaSessionPlaybackObserver {
    func systemMediaSessionDidActivate(for session: GeckoSession) {
        guard let tab = tab(for: session) else {
            return
        }
        session.mediaSession.muteAudio(tab.isMuted)
    }
    
    func systemMediaSessionPlaybackStateDidChange(
        _ playbackState: SystemMediaSession.PlaybackState,
        for session: GeckoSession
    ) {
        if let tab = tab(for: session) {
            let isPlaying = playbackState == .playing
            if tab.state.isPlayingAudio != isPlaying {
                tab.state.isPlayingAudio = isPlaying
                notifyUpdate(for: tab, reason: .audio)
            }
        }
    }
}

extension TabManagerImplementation: ReaderModeControllerDelegate {
    func readerModeController(_ controller: ReaderModeController, tabFor session: GeckoSession) -> Tab? {
        return tab(for: session)
    }
    
    func readerModeController(_ controller: ReaderModeController, didChangeStateFor tab: Tab) {
        notifyUpdate(for: tab, reason: .readerMode)
    }
}

extension TabManagerImplementation: ScrollDelegate {
    func onScrollChanged(session: GeckoSession, scrollX: Int, scrollY: Int) {
        guard let tab = tab(for: session) else { return }
        guard tab.state.readerMode.isActive else { return }
        tab.state.readerMode.sourceScrollY = scrollY
    }
}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let tab = tab(for: session) else {
            return
        }
        
        guard !title.isEmpty || (
            tab.state.restoreState == .none &&
            !tab.state.isSuppressingInitialBlankPageLoad
        ) else {
            return
        }
        
        tab.title = title
        if !tab.isPrivate,
           let url = remoteURL(from: tab.url) {
            historyStore.updatePageTitle(for: url, title: title)
        }
        notifyUpdate(for: tab, reason: .title)
        persistState()
    }
    
    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}
    
    func onFocusRequest(session: GeckoSession) {
        guard selectedTab?.session === session else {
            return
        }
        
        sessionManager.activate(session)
    }
    
    func onCloseRequest(session: GeckoSession) {
        guard let tab = tab(for: session) else {
            return
        }
        removeTab(tab, behavior: .recent)
    }
    
    func onFullScreen(session: GeckoSession, fullScreen: Bool) {
        guard selectedTab?.session === session else {
            return
        }
        
        delegate?.tabManager(
            self,
            didChangeFullscreen: fullScreen,
            for: session
        )
    }
    
    func onPictureInPictureRestore(session: GeckoSession) {
        guard selectedTab?.session !== session,
              let tab = tab(for: session) else {
            return
        }
        
        selectTab(tab)
    }
    
    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {}
    
    func onProductUrl(session: GeckoSession) {}
    
    func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: ContextElement) {
        guard selectedTab?.session === session else {
            return
        }
        
        let hasImageSource = element.type == .image && element.srcUri?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasLink = element.linkUri?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasImageSource || hasLink else {
            return
        }
        
        delegate?.tabManager(self, didRequestContextMenuAt: CGPoint(x: screenX, y: screenY), for: element, in: session)
    }
    
    func onCrash(session: GeckoSession) {
        handleSessionTermination(session, recoverAutomatically: false)
    }
    
    func onKill(session: GeckoSession) {
        handleSessionTermination(session, recoverAutomatically: true)
    }
    
    func onFirstComposite(session: GeckoSession) {}
    
    func onFirstContentfulPaint(session: GeckoSession) {}
    
    func onPaintStatusReset(session: GeckoSession) {}
    
    func onPageBackgroundColorChange(session: GeckoSession, color: UIColor) {
        sessionManager.setPageBackgroundColor(color, for: session)
        guard let tab = tab(for: session),
              tab.mode == selectedTabMode else {
            return
        }
        delegate?.tabManager(self, didUpdate: tab, reason: .pageBackgroundColor)
    }
    
    func onWebAppManifest(session: GeckoSession, manifest: Any) {
        guard let tab = tab(for: session),
              let url = remoteURL(from: tab.url) else {
            return
        }
        
        let tabID = tab.id
        let expectedURL = url.absoluteString
        cancelFaviconTask(for: tabID)
        faviconTasks[tabID] = Task { [weak self] in
            guard let self else {
                return
            }
            
            let image = await self.faviconStore.favicon(for: url, webAppManifest: manifest)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                self.applyResolvedFavicon(image, toTabWithID: tabID, expectedURL: expectedURL)
            }
        }
    }
    
    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        return .halt
    }
    
    func onShowDynamicToolbar(session: GeckoSession) {}
    
    func onCookieBannerDetected(session: GeckoSession) {}
    
    func onCookieBannerHandled(session: GeckoSession) {}
    
    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) async -> Bool {
        sessionManager.retainExternalResponse(for: session)
        let shouldStart = await delegate?.tabManager(
            self,
            shouldStartExternalResponse: response,
            for: session
        ) ?? false
        
        if !shouldStart {
            sessionManager.releaseExternalResponse(for: session)
        }
        return shouldStart
    }
    
    func onExternalResponseProgress(
        session: GeckoSession,
        localFilePath: String,
        bytesReceived: Int64
    ) -> Bool {
        return delegate?.tabManager(
            self,
            shouldContinueExternalResponseAt: localFilePath,
            bytesReceived: bytesReceived
        ) ?? false
    }
    
    func onExternalResponseComplete(session: GeckoSession, localFilePath: String, succeeded: Bool) {
        delegate?.tabManager(
            self,
            didCompleteExternalResponseAt: localFilePath,
            succeeded: succeeded
        )
        sessionManager.releaseExternalResponse(for: session)
    }
    
    func onSavePdf(session: GeckoSession, request: SavePdfInfo) {
        guard let download = DownloadStore.shared.pendingDownload(from: request) else {
            return
        }
        
        delegate?.tabManager(self, didRequestDownload: download)
    }
}

extension TabManagerImplementation: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let tab = tab(for: session) else {
            return
        }
        
        if let error = session.currentLoadError {
            if error != tab.state.loadError {
                _ = onLoadError(session: session, error: error)
            }
            return
        }
        
        if url == tab.state.loadError?.pageURI {
            return
        }
        
        if let error = tab.state.loadError, url != error.uri {
            tab.state.loadError = nil
            notifyUpdate(for: tab, reason: .loadError)
        }
        
        let engineURL = url
        let url = url.map { readerMode.displayedURL(for: $0, in: tab) }
        
        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let shouldPreserveDisplayedURL = hasDisplayURL(for: tab)
        
        if let normalizedURL,
           normalizedURL.hasPrefix("about:blank"),
           (tab.state.suppressInitialNavigation || shouldPreserveDisplayedURL) {
            return
        }
        
        sessionManager.universalLinkManager.didCommitNavigation(in: session)
        
        if let normalizedURL, !normalizedURL.isEmpty {
            tab.state.suppressInitialNavigation = false
        }
        
        if let url {
            sessionManager.updateSettings(of: session, for: url, tabID: tab.id)
            permissionCoordinator.restorePermissions(for: session, at: url)
        }
        
        if let url {
            let currentURL = tab.url
            if let currentURL,
               currentURL != url,
               tab.state.preparedNavigationThumbnailURL != currentURL {
                delegate?.tabManager(
                    self,
                    captureHistoryThumbnailFor: tab,
                    url: currentURL
                )
            }
            tab.state.preparedNavigationThumbnailURL = nil
            
            tab.url = url
        } else {
            tab.state.preparedNavigationThumbnailURL = nil
            tab.url = url
        }
        tab.state.committedEngineURL = engineURL
        tab.state.displayedHistoryEntry = matchingHistoryEntry(for: tab)
        tab.state.displayState = .committed
        tab.favicon = nil
        notifyUpdate(for: tab, reason: .location)
        scheduleFaviconUpdate(for: tab)
        persistState()
        session.flushSessionState()
    }
    
    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let tab = tab(for: session) else {
            return
        }
        
        tab.state.navigationState = NavigationAvailability(
            canGoBack: canGoBack,
            canGoForward: tab.state.navigationState.canGoForward
        )
        notifyUpdate(for: tab, reason: .navigationState)
    }
    
    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let tab = tab(for: session) else {
            return
        }
        
        tab.state.navigationState = NavigationAvailability(
            canGoBack: tab.state.navigationState.canGoBack,
            canGoForward: canGoForward
        )
        notifyUpdate(for: tab, reason: .navigationState)
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return await sessionManager.universalLinkManager.decideHandoff(for: request, in: session)
    }
    
    func onPreNavigation(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return await sessionManager.universalLinkManager.decideHandoff(for: request, in: session)
    }
    
    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return .allow
    }
    
    func onLoadError(session: GeckoSession, error: WebRequestError) -> String? {
        guard let tab = tab(for: session) else {
            return nil
        }
        var error = error
        if error.kind == .unknownHost, networkMonitor.currentPath.status != .satisfied {
            error.kind = .noInternet
        }
        
        tab.state.loadError = error
        tab.state.loadingState = .idle
        tab.state.showsStartupHomepage = false
        
        if let uri = error.uri, !uri.isEmpty {
            tab.url = uri
            tab.state.displayState = .committed
            tab.state.committedEngineURL = uri
            tab.state.displayedHistoryEntry = matchingHistoryEntry(for: tab)
        }
        
        notifyUpdate(for: tab, reason: .loadError)
        notifyUpdate(for: tab, reason: .loading)
        return error.pageURI
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String, target: LoadRequestTarget) async -> GeckoSession? {
        let sourceTab = tab(for: session)
        let mode = sourceTab?.mode ?? selectedTabMode
        let sourceIsPrivate = mode == .private
        let tabID = UUID()
        let newSession = sessionManager.createSession(
            url: uri,
            tabID: tabID,
            isPrivate: sourceIsPrivate,
            opening: .external,
            delegates: sessionDelegates
        )
        sessionManager.universalLinkManager.didCreateNewSession(from: session, for: uri)
        let newTab = Tab(id: tabID, session: newSession, isPrivate: sourceIsPrivate)
        newTab.state.openerTabID = sourceIsPrivate ? nil : sourceTab?.id
        permissionCoordinator.restorePermissions(for: newSession, at: uri)
        newTab.url = uri
        newTab.favicon = cachedFavicon(for: uri)
        
        let insertionIndex = sourceTab.flatMap { index(of: $0) }.map { $0 + 1 }
        insert(newTab, at: insertionIndex)
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(for: newTab, reason: .location)
        scheduleFaviconUpdate(for: newTab)
        persistState()
        
        guard target != .background else { return newSession }
        
        if let previousSession = selectedTab?.session,
           previousSession !== newSession {
            sessionManager.deactivate(previousSession)
        }
        selectedTabMode = mode
        delegate?.tabManager(self, animateNewTabSelectionTo: newTab) { [weak self] in
            self?.selectTab(newTab)
        }
        return newSession
    }
}

extension TabManagerImplementation: HistoryDelegate {
    func onVisited(
        session: GeckoSession,
        url: String,
        lastVisitedURL: String?,
        flags: HistoryVisitFlags
    ) async -> Bool {
        guard !session.isPrivateMode,
              flags.contains(.topLevel),
              !flags.contains(.unrecoverableError),
              let pageURL = remoteURL(from: url) else {
            return false
        }
        
        let title = tab(for: session)?.title ?? ""
        return await historyStore.recordVisitImmediately(
            url: pageURL,
            title: title,
            isRedirectSource: flags.contains(.redirectSource) || flags.contains(.redirectSourcePermanent)
        )
    }
    
    func getVisited(session: GeckoSession, urls: [String]) async -> [Bool]? {
        guard !session.isPrivateMode else {
            return Array(repeating: false, count: urls.count)
        }
        
        return await historyStore.visitedStatuses(for: urls)
    }
}

extension TabManagerImplementation: ProgressDelegate {
    func onSessionStateChange(session: GeckoSession, sessionState: GeckoSessionState) {
        guard let tab = tab(for: session) else {
            return
        }
        tab.state.tabSessionState = sessionState
        if let entry = matchingHistoryEntry(for: tab) {
            tab.state.displayedHistoryEntry = entry
        }
        notifyUpdate(for: tab, reason: .navigationState)
        persistState()
    }
    
    func onPageStart(session: GeckoSession, url: String) {
        guard let tab = tab(for: session) else {
            return
        }
        
        if url == tab.state.loadError?.pageURI {
            return
        }
        
        systemMediaSession.navigationStarted(
            in: session,
            preservingPlayback: tab.isMuted && tab.state.isPlayingAudio && tab.url == url
        )
        
        if url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank"),
           hasDisplayURL(for: tab) {
            tab.state.isSuppressingInitialBlankPageLoad = true
            return
        }
        
        if tab.state.loadError != nil {
            tab.state.loadError = nil
            notifyUpdate(for: tab, reason: .loadError)
        }
        
        sessionManager.trackingProtection.clearBlockedTrackers(for: session)
        if sessionManager.needsSettingsUpdate(
            to: session,
            currentURL: tab.url,
            requestedURL: url,
            tabID: tab.id
        ) {
            loadURL(url, in: tab)
        }
        
        tab.state.loadingState = .loading(progress: 0)
        notifyUpdate(for: tab, reason: .loading)
    }
    
    func onPageStop(session: GeckoSession, success: Bool) {
        guard let tab = tab(for: session) else {
            return
        }
        
        if let error = session.currentLoadError, error != tab.state.loadError {
            _ = onLoadError(session: session, error: error)
        }
        
        if tab.state.isSuppressingInitialBlankPageLoad {
            tab.state.isSuppressingInitialBlankPageLoad = false
            return
        }
        
        tab.state.loadingState = .idle
        notifyUpdate(for: tab, reason: .loading)
        notifyUpdate(for: tab, reason: .thumbnail)
        delegate?.tabManager(self, didFinishLoading: session)
    }
    
    func onReloadCancelled(session: GeckoSession) {
        delegate?.tabManager(self, didFinishLoading: session)
    }
    
    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let tab = tab(for: session) else {
            return
        }
        
        tab.state.loadingState = .loading(progress: Float(progress) / 100)
        notifyUpdate(for: tab, reason: .loading)
    }
}
