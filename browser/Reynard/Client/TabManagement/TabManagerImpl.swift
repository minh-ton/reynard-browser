//
//  TabManagerImpl.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
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
    private lazy var selectionActionCoordinator = SelectionActionCoordinator(
        presenter: SelectionActionPresenter(onMenuDismissed: requestContentKeyboardFocus)
    )
    private lazy var permissionCoordinator = PermissionCoordinator(
        promptPresenter: PermissionPromptPresenter(),
        onPromptFinished: requestContentKeyboardFocus
    )
    private lazy var systemMediaSession = SystemMediaSession(playbackObserver: self)
    private lazy var pictureInPictureCoordinator: PictureInPictureCoordinating? = {
        guard Prefs.ExperimentalSettings.isVideoPictureInPictureEnabled,
              #available(iOS 15.0, *) else {
            return nil
        }
        return PictureInPictureCoordinator(
            delegate: self,
            mediaSession: systemMediaSession,
            sessionManager: sessionManager
        )
    }()
    
    private weak var delegate: TabManagerDelegate?
    private let store: TabManagementStore
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    let sessionManager: SessionManager
    private var faviconTasks: [UUID: Task<Void, Never>] = [:]
    private var selectionCounter = 0
    
    // A background termination may be reported after the app becomes active.
    // Keep the session eligible for silent recovery until a foreground composite confirms it survived.
    private weak var sessionEligibleForSilentRecovery: GeckoSession?
    
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
    }
    
    // MARK: - Application Lifecycle
    
    func applicationWillResignActive() {
        sessionEligibleForSilentRecovery = selectedTab?.session
    }
    
    func applicationDidBecomeActive() {
        guard selectedTab?.session.isOpen() == false else {
            return
        }
        
        selectTab(at: selectedTabIndex, mode: selectedTabMode)
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
    
    private func tabs(for mode: TabMode) -> [Tab] {
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
    
    private func tabLocation(for session: GeckoSession) -> (mode: TabMode, index: Int)? {
        if let index = regularTabs.firstIndex(where: { $0.session === session }) {
            return (.regular, index)
        }
        
        if let index = privateTabs.firstIndex(where: { $0.session === session }) {
            return (.private, index)
        }
        
        return nil
    }
    
    private func tabLocation(for tabID: UUID) -> (mode: TabMode, index: Int)? {
        if let index = regularTabs.firstIndex(where: { $0.id == tabID }) {
            return (.regular, index)
        }
        
        if let index = privateTabs.firstIndex(where: { $0.id == tabID }) {
            return (.private, index)
        }
        
        return nil
    }
    
    private func notifyUpdate(at index: Int, mode: TabMode, reason: TabManagerUpdateReason) {
        if mode == selectedTabMode {
            delegate?.tabManager(self, didUpdateTabAt: index, reason: reason)
        } else {
            delegate?.tabManagerDidChangeTabs(self)
        }
    }
    
    // MARK: - Navigation State
    
    private func loadURL(_ url: String, in tab: Tab) {
        tab.state.restoreState = .none
        tab.state.showsStartupHomepage = false
        tab.state.loadingState = .loading(progress: 0)
        if let location = tabLocation(for: tab.id) {
            notifyUpdate(at: location.index, mode: location.mode, reason: .loading)
        }
        sessionManager.updateSettings(of: tab.session, for: url, tabID: tab.id)
        tab.session.load(url)
    }
    
    private func applyNavigationState(to tab: Tab) {
        tab.state.navigationState = sessionManager.navigationAvailability(
            for: tab.id,
            sessionState: tab.state.sessionNavigationAvailability
        )
    }
    
    private func applySessionNavigationHistory(
        with sessionState: GeckoSessionState,
        to tab: Tab
    ) -> Bool {
        let entries = sessionState.history
        guard let currentIndex = sessionManager.synchronizeNavigationHistory(
            with: sessionState,
            for: tab.id
        ) else {
            return false
        }
        tab.state.sessionNavigationAvailability = .available(
            back: currentIndex > 0,
            forward: currentIndex + 1 < entries.count
        )
        applyNavigationState(to: tab)
        return true
    }
    
    private func recordNavigation(_ url: String, title: String? = nil, for tab: Tab) {
        tab.state.navigationState = sessionManager.recordNavigation(
            to: url,
            title: title ?? tab.title,
            for: tab.id,
            sessionState: tab.state.sessionNavigationAvailability
        )
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
            prompt: promptCoordinator,
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
    
    private func scheduleFaviconUpdate(forTabAt index: Int, mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let tab = tabs(for: mode)[index]
        cancelFaviconTask(for: tab.id)
        
        let cachedImage = cachedFavicon(for: tab.url)
        tab.favicon = cachedImage
        notifyUpdate(at: index, mode: mode, reason: .favicon)
        
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
        
        guard let location = tabLocation(for: tabID),
              tabs(for: location.mode)[location.index].url == expectedURL else {
            return
        }
        
        tabs(for: location.mode)[location.index].favicon = image
        notifyUpdate(at: location.index, mode: location.mode, reason: .favicon)
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
            tab.state.restoreState = .pendingSession
            return
        }
        tab.state.restoreState = restoredURL(from: fallbackURL).map(TabRestoreState.pendingURL) ?? .none
    }
    
    private func prepareRestoration(for tab: Tab) {
        if !sessionManager.usesStoredNavigationHistory(for: tab.id),
           restorableSessionState(tab.state.tabSessionState) != nil {
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
                isPrivate: false
            )
            prepareRestoration(
                serializedSessionState: snapshot.tabSessionState,
                fallbackURL: snapshot.url,
                for: tab
            )
            tab.state.navigationState = sessionManager.restoreNavigation(for: tab.id)
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
                isPrivate: true
            )
            prepareRestoration(
                serializedSessionState: snapshot.tabSessionState,
                fallbackURL: snapshot.url,
                for: tab
            )
            tab.state.navigationState = sessionManager.restoreNavigation(for: tab.id)
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
        
        delegate?.tabManagerDidChangeTabs(self)
        
        selectTab(at: max(selectedIndex(for: selectedTabMode), 0), mode: selectedTabMode)
        return true
    }
    
    private func restorePendingSessionStateIfNeeded(for tab: Tab) {
        guard tab.state.restoreState == .pendingSession,
              let sessionState = tab.state.tabSessionState else {
            return
        }
        tab.state.restoreState = .none
        if !applySessionNavigationHistory(with: sessionState, to: tab) {
            tab.state.sessionNavigationAvailability = .unavailable
            tab.state.navigationState = sessionManager.useStoredNavigationHistory(for: tab.id)
        }
        tab.session.restoreState(sessionState)
    }
    
    private func loadRestoredURLIfNeeded(for index: Int, mode: TabMode) {
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let tab = tabs(for: mode)[index]
        guard tab.session.isOpen(),
              case let .pendingURL(url) = tab.state.restoreState else {
            return
        }
        
        tab.state.suppressInitialNavigation = false
        loadURL(url, in: tab)
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
        tab.state.navigationState = sessionManager.restoreNavigation(for: tab.id)
        
        let index = regularTabs.count
        regularTabs.append(tab)
        delegate?.tabManagerDidChangeTabs(self)
        selectedTabMode = .regular
        delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
            self?.selectTab(at: index, mode: .regular)
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
            isPrivate: tab.isPrivate
        )
        tab.session = replacementSession
        tab.state.sessionNavigationAvailability = .unavailable
        restorePendingSessionStateIfNeeded(for: tab)
        delegate?.tabManager(
            self,
            didReplaceSelectedSession: previousSession,
            with: replacementSession
        )
    }
    
    private func handleSessionTermination(_ session: GeckoSession) {
        DownloadStore.shared.failCapturedDownloads(for: session)
        sessionManager.clearExternalResponseRetention(for: session)
        
        guard let location = tabLocation(for: session) else {
            return
        }
        
        let wasAwaitingForegroundComposite =
        sessionEligibleForSilentRecovery === session
        if wasAwaitingForegroundComposite {
            sessionEligibleForSilentRecovery = nil
        }
        
        let didTerminateSelectedTab = selectedTab?.session === session
        let tab = tabs(for: location.mode)[location.index]
        if !sessionManager.usesStoredNavigationHistory(for: tab.id),
           let sessionState = session.currentSessionState {
            tab.state.tabSessionState = sessionState
        }
        sessionManager.close(session)
        prepareRestoration(for: tab)
        tab.state.loadingState = .idle
        notifyUpdate(at: location.index, mode: location.mode, reason: .loading)
        persistState()
        
        guard didTerminateSelectedTab,
              sessionManager.isApplicationActive else {
            return
        }
        
        if wasAwaitingForegroundComposite {
            selectTab(at: location.index, mode: location.mode)
        } else {
            delegate?.tabManagerDidTerminateSelectedTab(self)
        }
    }
    
    // MARK: - Tab Lifecycle
    
    private func saveClosedTabIfNeeded(_ tab: Tab, mode: TabMode) {
        guard mode == .regular,
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
    
    func createInitialTab(openingScreen: HomepageOpeningScreen) {
        switch openingScreen {
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
           let lastTabIndex = regularTabs.indices.last,
           displayedURL(for: regularTabs[lastTabIndex]) == nil {
            let lastTab = regularTabs[lastTabIndex]
            lastTab.state.showsStartupHomepage = true
            if selectedTab?.id != lastTab.id {
                selectTab(at: lastTabIndex, mode: .regular)
            }
            return
        }
        
        if didRestoreTabs,
           let selectedTab,
           displayedURL(for: selectedTab) == nil {
            selectedTab.state.showsStartupHomepage = true
            return
        }
        
        let index = addTab(selecting: true, windowId: nil, at: nil, isPrivate: false)
        regularTabs[index].state.showsStartupHomepage = true
    }
    
    @discardableResult
    func addTab(selecting: Bool, windowId: String? = nil, at insertionIndex: Int? = nil, isPrivate: Bool = false) -> Int {
        let tab = makeTab(windowId: windowId, isPrivate: isPrivate)
        let mode: TabMode = isPrivate ? .private : .regular
        let count = tabs(for: mode).count
        let index = min(max(insertionIndex ?? count, 0), count)
        
        if mode == .regular {
            if index == regularTabs.count {
                regularTabs.append(tab)
            } else {
                regularTabs.insert(tab, at: index)
                if selectedRegularTabIndex >= index {
                    selectedRegularTabIndex += 1
                }
            }
        } else {
            if index == privateTabs.count {
                privateTabs.append(tab)
            } else {
                privateTabs.insert(tab, at: index)
                if selectedPrivateTabIndex >= index {
                    selectedPrivateTabIndex += 1
                }
            }
        }
        
        if selecting {
            selectTab(at: index, mode: mode)
        } else {
            persistState()
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        return index
    }
    
    @discardableResult
    func addTransferredSession(_ session: GeckoSession, url: String, title: String?, selecting: Bool, at insertionIndex: Int?, isPrivate: Bool = false) -> Int {
        let tab = Tab(session: session, isPrivate: isPrivate)
        let sessionState = restorableSessionState(session.currentSessionState, matching: url)
        tab.state.tabSessionState = sessionState
        let mode: TabMode = isPrivate ? .private : .regular
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates)
        applyTransferredState(to: tab, url: url, title: title)
        if let sessionState {
            _ = applySessionNavigationHistory(with: sessionState, to: tab)
        }
        
        let count = tabs(for: mode).count
        let index = min(max(insertionIndex ?? count, 0), count)
        if mode == .regular {
            if index == regularTabs.count {
                regularTabs.append(tab)
            } else {
                regularTabs.insert(tab, at: index)
                if selectedRegularTabIndex >= index {
                    selectedRegularTabIndex += 1
                }
            }
        } else {
            if index == privateTabs.count {
                privateTabs.append(tab)
            } else {
                privateTabs.insert(tab, at: index)
                if selectedPrivateTabIndex >= index {
                    selectedPrivateTabIndex += 1
                }
            }
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(at: index, mode: mode, reason: .location)
        notifyUpdate(at: index, mode: mode, reason: .title)
        scheduleFaviconUpdate(forTabAt: index, mode: mode)
        recordTransferredHistory(for: tab, title: title)
        if selecting {
            if let previousSession = selectedTab?.session,
               previousSession !== session {
                sessionManager.deactivate(previousSession)
            }
            selectedTabMode = mode
            delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
                self?.selectTab(at: index, mode: mode)
            }
        } else {
            persistState()
        }
        
        return index
    }
    
    func selectTab(at index: Int, mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let previousTab = selectedTab
        let previousMode = selectedTabMode
        let previousIndex = previousMode == mode && tabs(for: previousMode).indices.contains(selectedTabIndex) ? selectedTabIndex : nil
        
        selectedTabMode = mode
        selectionCounter += 1
        setSelectedIndex(index, for: mode)
        tabs(for: mode)[index].state.selectionOrder = selectionCounter
        let selectedTab = tabs(for: mode)[index]
        if previousTab?.session !== selectedTab.session,
           let previousSession = previousTab?.session {
            sessionManager.deactivate(previousSession)
        }
        recoverSelectedSessionIfNeeded()
        restorePendingSessionStateIfNeeded(for: selectedTab)
        sessionManager.activate(selectedTab.session)
        systemMediaSession.select(session: selectedTab.session)
        pictureInPictureCoordinator?.selectedSessionDidChange()
        applyNavigationState(to: selectedTab)
        
        delegate?.tabManager(self, didSelectTabAt: index, previousIndex: previousIndex)
        loadRestoredURLIfNeeded(for: index, mode: mode)
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
    
    func removeTab(at index: Int, mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let wasSelected = mode == selectedTabMode && index == selectedTabIndex
        let removedTab: Tab
        if mode == .regular {
            removedTab = regularTabs.remove(at: index)
        } else {
            removedTab = privateTabs.remove(at: index)
        }
        saveClosedTabIfNeeded(removedTab, mode: mode)
        if wasSelected {
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
            delegate?.tabManagerDidChangeTabs(self)
            sessionManager.discard(removedTab.session, forTab: removedTab.id, keepingHistory: mode == .regular)
            return
        }
        
        if wasSelected {
            let remainingTabs = tabs(for: mode)
            if !remainingTabs.isEmpty {
                let previousIndex = remainingTabs.indices
                    .filter { remainingTabs[$0].state.selectionOrder > 0 }
                    .max { remainingTabs[$0].state.selectionOrder < remainingTabs[$1].state.selectionOrder }
                selectTab(at: previousIndex ?? min(index, remainingTabs.count - 1), mode: mode)
            } else if mode == .private && !regularTabs.isEmpty {
                selectTab(at: max(selectedIndex(for: .regular), 0), mode: .regular)
            } else {
                persistState()
            }
        } else {
            persistState()
        }
        delegate?.tabManagerDidChangeTabs(self)
        
        sessionManager.discard(removedTab.session, forTab: removedTab.id, keepingHistory: mode == .regular)
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
        removedTabs.forEach { saveClosedTabIfNeeded($0, mode: mode) }
        removedTabs.forEach { cancelFaviconTask(for: $0.id) }
        let fallbackMode: TabMode = mode == .regular ? .private : .regular
        if mode == selectedTabMode,
           !tabs(for: fallbackMode).isEmpty {
            selectTab(at: max(selectedIndex(for: fallbackMode), 0), mode: fallbackMode)
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
        if let location = tabLocation(for: tab.id) {
            notifyUpdate(at: location.index, mode: location.mode, reason: .location)
        }
        
        let navigationInputRange = NSRange(location: 0, length: (navigationInput as NSString).length)
        let shouldNavigateDirectly = lenientURLExpression.firstMatch(in: navigationInput, range: navigationInputRange) != nil
        
        if shouldNavigateDirectly {
            loadURL(navigationInput, in: tab)
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
        
        enqueueHistoryNavigation(.back, in: tab)
    }
    
    func goBack(to index: Int) {
        guard let tab = selectedTab else {
            return
        }
        
        if !sessionManager.usesStoredNavigationHistory(for: tab.id) {
            guard let sessionState = tab.state.tabSessionState,
                  let currentIndex = sessionState.currentHistoryIndex else {
                return
            }
            let targetIndex = currentIndex - index - 1
            guard sessionState.history.indices.contains(targetIndex) else {
                return
            }
            tab.session.goToHistoryIndex(targetIndex)
            tab.session.flushSessionState()
            return
        }
        
        guard let transition = sessionManager.goBack(
            to: index,
            for: tab.id,
            sessionState: tab.state.sessionNavigationAvailability
        ) else {
            return
        }
        
        tab.state.navigationState = transition.availability
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
        switch transition.action {
        case .session:
            tab.session.goBack()
        case let .load(url):
            loadURL(url, in: tab)
        }
    }
    
    func goForward() {
        guard let tab = selectedTab else {
            return
        }
        
        enqueueHistoryNavigation(.forward, in: tab)
    }
    
    func goForward(to index: Int) {
        guard let tab = selectedTab else {
            return
        }
        
        if !sessionManager.usesStoredNavigationHistory(for: tab.id) {
            guard let sessionState = tab.state.tabSessionState,
                  let currentIndex = sessionState.currentHistoryIndex else {
                return
            }
            let targetIndex = currentIndex + index + 1
            guard sessionState.history.indices.contains(targetIndex) else {
                return
            }
            tab.session.goToHistoryIndex(targetIndex)
            tab.session.flushSessionState()
            return
        }
        
        guard let transition = sessionManager.goForward(
            to: index,
            for: tab.id,
            sessionState: tab.state.sessionNavigationAvailability
        ) else {
            return
        }
        
        tab.state.navigationState = transition.availability
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
        switch transition.action {
        case .session:
            tab.session.goForward()
        case let .load(url):
            loadURL(url, in: tab)
        }
    }
    
    private func enqueueHistoryNavigation(_ direction: HistoryNavigationDirection, in tab: Tab) {
        tab.state.pendingHistoryNavigations.append(direction)
        startNextHistoryNavigation(in: tab)
    }
    
    private func startNextHistoryNavigation(in tab: Tab) {
        guard tab.state.activeHistoryNavigationID == nil,
              !tab.state.pendingHistoryNavigations.isEmpty else {
            return
        }
        
        let direction = tab.state.pendingHistoryNavigations.removeFirst()
        let transition: NavigationTransition?
        switch direction {
        case .back:
            transition = sessionManager.goBack(
                for: tab.id,
                sessionState: tab.state.sessionNavigationAvailability
            )
        case .forward:
            transition = sessionManager.goForward(
                for: tab.id,
                sessionState: tab.state.sessionNavigationAvailability
            )
        }
        
        guard let transition else {
            startNextHistoryNavigation(in: tab)
            return
        }
        
        tab.state.lastHistoryNavigationID += 1
        tab.state.activeHistoryNavigationID = tab.state.lastHistoryNavigationID
        tab.state.navigationState = transition.availability
        if let location = tabLocation(for: tab.id) {
            notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
        }
        
        switch transition.action {
        case .session:
            switch direction {
            case .back:
                tab.session.goBack()
            case .forward:
                tab.session.goForward()
            }
        case let .load(url):
            loadURL(url, in: tab)
        }
    }
    
    private func scheduleHistoryNavigationCompletion(in tab: Tab) {
        guard let navigationID = tab.state.activeHistoryNavigationID else {
            return
        }
        
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab,
                  tab.state.activeHistoryNavigationID == navigationID else {
                return
            }
            
            tab.state.activeHistoryNavigationID = nil
            self.startNextHistoryNavigation(in: tab)
        }
    }
    
    // MARK: - Session Replacement
    
    func replaceSelectedSession(with session: GeckoSession, url: String, title: String?) {
        guard let tab = selectedTab else {
            return
        }
        
        let oldSession = tab.session
        let usesStoredNavigationHistory = sessionManager.usesStoredNavigationHistory(for: tab.id)
        
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates)
        tab.session = session
        let sessionState = restorableSessionState(session.currentSessionState, matching: url)
        tab.state.tabSessionState = sessionState
        tab.state.restoreState = .none
        applyTransferredState(to: tab, url: url, title: title)
        if usesStoredNavigationHistory {
            tab.state.tabSessionState = nil
            tab.state.sessionNavigationAvailability = .unavailable
            recordNavigation(url, for: tab)
            tab.state.navigationState = sessionManager.useStoredNavigationHistory(for: tab.id)
        } else {
            tab.state.sessionNavigationAvailability = .unavailable
            applyNavigationState(to: tab)
            if let sessionState {
                _ = applySessionNavigationHistory(with: sessionState, to: tab)
            }
        }
        sessionManager.activate(session)
        systemMediaSession.select(session: session)
        pictureInPictureCoordinator?.selectedSessionDidChange()
        
        delegate?.tabManagerDidChangeTabs(self)
        delegate?.tabManager(self, didReplaceSelectedSession: oldSession, with: session)
        sessionManager.close(oldSession)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .location)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .title)
        scheduleFaviconUpdate(forTabAt: selectedTabIndex)
        persistState()
        recordTransferredHistory(for: tab, title: title)
    }
    
    // MARK: - Tab Queries And Updates
    
    func tabIndex(for session: GeckoSession) -> Int? {
        return tabs(for: selectedTabMode).firstIndex(where: { $0.session === session })
    }
    
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
    
    func updateThumbnail(_ image: UIImage?, forTabAt index: Int, mode: TabMode) {
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let tab = tabs(for: mode)[index]
        tab.thumbnail = image
        store.persistThumbnail(image, for: tab.id)
        notifyUpdate(at: index, mode: mode, reason: .thumbnail)
    }
    
    func updateHistoryThumbnail(
        _ image: UIImage?,
        for tab: Tab,
        url: String,
        isPreparedForNavigation: Bool
    ) {
        let tabID = tab.id
        if isPreparedForNavigation {
            tab.state.preparedNavigationThumbnailURL = url
        }
        sessionManager.updateCurrentHistoryThumbnail(image, for: tabID, matching: url) { [weak self] in
            guard let self,
                  let location = tabLocation(for: tabID) else {
                return
            }
            notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
        }
    }
    
    func navigationHistory(for tab: Tab) -> NavigationHistoryStore.Snapshot {
        return sessionManager.navigationHistory(for: tab.id)
    }
    
    func navigationPreviewImages(for tab: Tab) -> NavigationPreviewImages {
        return sessionManager.navigationPreviewImages(for: tab.id)
    }
    
    func invalidateNavigationThumbnails() {
        sessionManager.invalidateNavigationThumbnails()
    }
    
    // MARK: - Session Factory
    
    private func createSession(
        tabID: UUID,
        url: String?,
        windowId: String?,
        isPrivate: Bool,
        opening: SessionOpening? = nil
    ) -> GeckoSession {
        return sessionManager.createSession(
            url: url,
            tabID: tabID,
            isPrivate: isPrivate,
            opening: opening ?? .immediate(windowID: windowId),
            delegates: sessionDelegates
        )
    }
}

extension TabManagerImplementation: SystemMediaSessionPlaybackObserver {
    func systemMediaSessionPlaybackStateDidChange(
        _ playbackState: SystemMediaSession.PlaybackState,
        for session: GeckoSession
    ) {
        delegate?.tabManager(self, didChangeMediaPlayback: playbackState == .playing, for: session)
    }
}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let location = tabLocation(for: session) else {
            return
        }
        
        let tab = tabs(for: location.mode)[location.index]
        
        guard !title.isEmpty || (
            tab.state.restoreState == .none &&
            !tab.state.isSuppressingInitialBlankPageLoad
        ) else {
            return
        }
        
        tab.title = title
        if let url = tab.url {
            sessionManager.updateCurrentHistoryTitle(title, for: tab.id, matching: url)
        }
        if !tab.isPrivate,
           let url = remoteURL(from: tab.url) {
            historyStore.updatePageTitle(for: url, title: title)
        }
        notifyUpdate(at: location.index, mode: location.mode, reason: .title)
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
        guard let location = tabLocation(for: session) else {
            return
        }
        removeTab(at: location.index, mode: location.mode)
    }
    
    func onFullScreen(session: GeckoSession, fullScreen: Bool) {
        guard selectedTab?.session === session else {
            return
        }
        
        let mediaIsPlaying = systemMediaSession.selectedSnapshot.map {
            $0.session === session && $0.playbackState == .playing
        } ?? false
        
        delegate?.tabManager(
            self,
            didChangeFullscreen: fullScreen,
            mediaIsPlaying: mediaIsPlaying,
            for: session
        )
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
        handleSessionTermination(session)
    }
    
    func onKill(session: GeckoSession) {
        handleSessionTermination(session)
    }
    
    func onFirstComposite(session: GeckoSession) {
        guard sessionManager.isApplicationActive,
              sessionEligibleForSilentRecovery === session else {
            return
        }
        
        sessionEligibleForSilentRecovery = nil
    }
    
    func onFirstContentfulPaint(session: GeckoSession) {}
    
    func onPaintStatusReset(session: GeckoSession) {}
    
    func onPageBackgroundColorChange(session: GeckoSession, color: UIColor) {
        sessionManager.setPageBackgroundColor(color, for: session)
        guard let location = tabLocation(for: session) else {
            return
        }
        
        guard location.mode == selectedTabMode else {
            return
        }
        delegate?.tabManager(self, didUpdateTabAt: location.index, reason: .pageBackgroundColor)
    }
    
    func onWebAppManifest(session: GeckoSession, manifest: Any) {
        guard let location = tabLocation(for: session),
              let url = remoteURL(from: tabs(for: location.mode)[location.index].url) else {
            return
        }
        
        let tab = tabs(for: location.mode)[location.index]
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
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
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
                    captureHistoryThumbnailForTabAt: location.index,
                    mode: location.mode,
                    url: currentURL
                )
            }
            tab.state.preparedNavigationThumbnailURL = nil
            
            tab.url = url
            recordNavigation(url, title: currentURL == url ? tab.title : "", for: tab)
        } else {
            tab.state.preparedNavigationThumbnailURL = nil
            tab.url = url
        }
        tab.state.displayState = .committed
        tab.favicon = nil
        notifyUpdate(at: location.index, mode: location.mode, reason: .location)
        scheduleFaviconUpdate(forTabAt: location.index, mode: location.mode)
        persistState()
        if !sessionManager.usesStoredNavigationHistory(for: tab.id) {
            session.flushSessionState()
        }
        scheduleHistoryNavigationCompletion(in: tab)
        
    }
    
    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        tab.state.sessionNavigationAvailability = .available(
            back: canGoBack,
            forward: tab.state.sessionNavigationAvailability.canGoForward
        )
        applyNavigationState(to: tab)
        notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
    }
    
    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        tab.state.sessionNavigationAvailability = .available(
            back: tab.state.sessionNavigationAvailability.canGoBack,
            forward: canGoForward
        )
        applyNavigationState(to: tab)
        notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
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
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String, target: LoadRequestTarget) async -> GeckoSession? {
        let sourceLocation = tabLocation(for: session)
        let mode = sourceLocation?.mode ?? selectedTabMode
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
        permissionCoordinator.restorePermissions(for: newSession, at: uri)
        newTab.url = uri
        newTab.favicon = cachedFavicon(for: uri)
        recordNavigation(uri, for: newTab)
        
        let insertionIndex = sourceLocation.map { $0.index + 1 }
        let count = tabs(for: mode).count
        let index = min(max(insertionIndex ?? count, 0), count)
        if mode == .regular {
            if index == regularTabs.count {
                regularTabs.append(newTab)
            } else {
                regularTabs.insert(newTab, at: index)
                if selectedRegularTabIndex >= index {
                    selectedRegularTabIndex += 1
                }
            }
        } else {
            if index == privateTabs.count {
                privateTabs.append(newTab)
            } else {
                privateTabs.insert(newTab, at: index)
                if selectedPrivateTabIndex >= index {
                    selectedPrivateTabIndex += 1
                }
            }
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(at: index, mode: mode, reason: .location)
        scheduleFaviconUpdate(forTabAt: index, mode: mode)
        persistState()
        
        guard target != .background else { return newSession }
        
        if let previousSession = selectedTab?.session,
           previousSession !== newSession {
            sessionManager.deactivate(previousSession)
        }
        selectedTabMode = mode
        delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
            self?.selectTab(at: index, mode: mode)
        }
        return newSession
    }
}

@available(iOS 15.0, *)
extension TabManagerImplementation: PictureInPictureCoordinatorDelegate {
    func pictureInPictureCoordinator(
        _ coordinator: PictureInPictureCoordinator,
        restore session: GeckoSession
    ) -> Bool {
        guard let location = tabLocation(for: session) else {
            return false
        }
        selectTab(at: location.index, mode: location.mode)
        return true
    }
}

extension TabManagerImplementation: HistoryDelegate {
    func onHistoryStateChange(session: GeckoSession, sessionState: GeckoSessionState) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        guard !sessionManager.usesStoredNavigationHistory(for: tab.id) else {
            return
        }
        guard applySessionNavigationHistory(with: sessionState, to: tab) else {
            return
        }
        notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
    }
    
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
        
        let title = tabLocation(for: session).map { tabs(for: $0.mode)[$0.index].title } ?? ""
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
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        if !sessionManager.usesStoredNavigationHistory(for: tab.id) {
            tab.state.tabSessionState = sessionState
        }
        persistState()
    }
    
    func onPageStart(session: GeckoSession, url: String) {
        systemMediaSession.navigationStarted(in: session)
        pictureInPictureCoordinator?.navigationStarted(in: session)
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        if url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank"),
           hasDisplayURL(for: tab) {
            tab.state.isSuppressingInitialBlankPageLoad = true
            return
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
        notifyUpdate(at: location.index, mode: location.mode, reason: .loading)
    }
    
    func onPageStop(session: GeckoSession, success: Bool) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        if tab.state.isSuppressingInitialBlankPageLoad {
            tab.state.isSuppressingInitialBlankPageLoad = false
            return
        }
        
        tab.state.loadingState = .idle
        notifyUpdate(at: location.index, mode: location.mode, reason: .loading)
        notifyUpdate(at: location.index, mode: location.mode, reason: .thumbnail)
        delegate?.tabManager(self, didFinishLoading: session)
    }
    
    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        tab.state.loadingState = .loading(progress: Float(progress) / 100)
        notifyUpdate(at: location.index, mode: location.mode, reason: .loading)
    }
}
