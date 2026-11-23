//
//  TabManager.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
import Network
import UIKit

enum TabMode: String, Codable {
    case regular
    case `private`
}

enum TabRemovalBehavior {
    case recent     // activate the most recently used tab
    case adjacent   // activate the tab adjacent to the one being removed
    case none
}

enum TabInsertionTarget: Equatable {
    case end
    case afterSelected
    case index(Int)
}

enum TabManagerUpdateReason {
    case title
    case location
    case favicon
    case navigationState
    case loading
    case loadError
    case thumbnail
    case pageBackgroundColor
    case readerMode
    case audio
}

protocol TabListSource: AnyObject {
    var regularTabs: [Tab] { get }
    var privateTabs: [Tab] { get }
    var activeTabs: [Tab] { get }
    var selectedTabMode: TabMode { get }
    var selectedTabIndex: Int { get }
    var selectedTab: Tab? { get }
}

protocol TabManagerDelegate: AnyObject {
    func tabManagerDidChangeTabs(_ tabManager: TabManager)
    func tabManagerDidTerminateSelectedTab(_ tabManager: TabManager)
    func tabManager(_ tabManager: TabManager, didSelect tab: Tab, previous previousTab: Tab?)
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession)
    func tabManager(_ tabManager: TabManager, didUpdate tab: Tab, reason: TabManagerUpdateReason)
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession)
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailFor tab: Tab, url: String)
    func tabManager(_ tabManager: TabManager, animateReturnTo tab: Tab, completion: @escaping () -> Void)
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionTo tab: Tab, completion: @escaping () -> Void)
}

extension TabManagerDelegate {
    func tabManagerDidTerminateSelectedTab(_ tabManager: TabManager) {}
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession) {}
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailFor tab: Tab, url: String) {}
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession) {}
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionTo tab: Tab, completion: @escaping () -> Void) {
        completion()
    }
}

final class TabManager: NSObject {
    private final class TabList {
        private(set) var tabs: [Tab] = []
        var selectedIndex = -1
        
        var selectedTab: Tab? {
            return tabs[safe: selectedIndex]
        }
        
        func restore(_ tabs: [Tab], selectedTabID: UUID?) {
            self.tabs = tabs
            selectedIndex = tabs.firstIndex { $0.id == selectedTabID } ?? (tabs.isEmpty ? -1 : 0)
        }
        
        func insert(_ tab: Tab, at index: Int) {
            tabs.insert(tab, at: index)
            
            if selectedIndex >= index {
                selectedIndex += 1
            }
        }
        
        func remove(at index: Int) -> Tab {
            let tab = tabs.remove(at: index)
            
            if tabs.isEmpty {
                selectedIndex = -1
            } else if index < selectedIndex {
                selectedIndex -= 1
            }
            
            return tab
        }
        
        func move(from sourceIndex: Int, to destinationIndex: Int) {
            let selectedTab = self.selectedTab
            tabs.insert(tabs.remove(at: sourceIndex), at: destinationIndex)
            
            if let selectedTab,
               let index = tabs.firstIndex(where: { $0 === selectedTab }) {
                selectedIndex = index
            }
        }
        
        func removeAll() {
            tabs.removeAll(keepingCapacity: true)
            selectedIndex = -1
        }
    }
    
    private let regularTabList = TabList()
    private let privateTabList = TabList()
    private(set) var selectedTabMode: TabMode = .regular
    
    var regularTabs: [Tab] {
        return regularTabList.tabs
    }
    
    var privateTabs: [Tab] {
        return privateTabList.tabs
    }
    
    var selectedTabIndex: Int {
        return tabList(for: selectedTabMode).selectedIndex
    }
    
    var selectedTab: Tab? {
        return tabList(for: selectedTabMode).selectedTab
    }
    
    var activeTabs: [Tab] {
        return tabs(for: selectedTabMode)
    }
    
    var openerTab: Tab? {
        guard let tab = selectedTab,
              !tab.isPrivate,
              let openerTabID = tab.state.openerTabID else {
            return nil
        }
        
        return regularTabs.first { $0.id == openerTabID }
    }
    
    var canGoBack: Bool {
        return selectedTab?.state.navigationState.canGoBack == true || openerTab != nil
    }
    
    private weak var delegate: TabManagerDelegate?
    private weak var sessionHandlerDelegate: TabSessionHandlerDelegate?
    let sessionManager: SessionManager
    private let promptCoordinator: PromptCoordinator
    private let permissionCoordinator: PermissionCoordinator
    private let pagePrintCoordinator: PagePrintCoordinator
    private let selectionActionCoordinator: SelectionActionCoordinator
    private let store: TabManagementStore
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    
    private(set) lazy var readerMode = ReaderModeController(delegate: self)
    private lazy var systemMediaSession = SystemMediaSession(playbackObserver: self)
    private let networkMonitor = NWPathMonitor()
    private var selectionCounter = 0
    
    private lazy var lenientURLExpression: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    init(
        delegate: TabManagerDelegate?,
        sessionHandlerDelegate: TabSessionHandlerDelegate?,
        sessionManager: SessionManager,
        promptCoordinator: PromptCoordinator,
        permissionCoordinator: PermissionCoordinator,
        pagePrintCoordinator: PagePrintCoordinator,
        selectionActionCoordinator: SelectionActionCoordinator,
        store: TabManagementStore = .shared,
        faviconStore: FaviconStore = .shared,
        historyStore: HistoryStore = .shared
    ) {
        self.delegate = delegate
        self.sessionHandlerDelegate = sessionHandlerDelegate
        self.sessionManager = sessionManager
        self.promptCoordinator = promptCoordinator
        self.permissionCoordinator = permissionCoordinator
        self.pagePrintCoordinator = pagePrintCoordinator
        self.selectionActionCoordinator = selectionActionCoordinator
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
    
    // MARK: - Lookup
    
    func tabs(for mode: TabMode) -> [Tab] {
        return tabList(for: mode).tabs
    }
    
    private func tabList(for mode: TabMode) -> TabList {
        switch mode {
        case .regular:
            return regularTabList
        case .private:
            return privateTabList
        }
    }
    
    func tab(for session: GeckoSession) -> Tab? {
        return regularTabs.first { $0.session === session } ?? privateTabs.first { $0.session === session }
    }
    
    private func tab(withID tabID: UUID) -> Tab? {
        return regularTabs.first { $0.id == tabID } ?? privateTabs.first { $0.id == tabID }
    }
    
    private func index(of tab: Tab) -> Int? {
        return tabs(for: tab.mode).firstIndex { $0 === tab }
    }
    
    func index(for target: TabInsertionTarget, mode: TabMode) -> Int? {
        let tabCount = tabs(for: mode).count
        
        switch target {
        case .end:
            return tabCount
        case .afterSelected:
            guard selectedTabMode == mode,
                  selectedTabIndex >= 0 else {
                return tabCount
            }
            
            return selectedTabIndex + 1
        case let .index(index):
            return index
        }
    }
    
    // MARK: - State Updates
    
    func persistState() {
        store.persistTabs(
            regularTabs: regularTabs,
            privateTabs: privateTabs,
            selectedRegularTabID: regularTabList.selectedTab?.id,
            selectedPrivateTabID: privateTabList.selectedTab?.id,
            selectedTabMode: selectedTabMode
        )
    }
    
    func notifyUpdate(for tab: Tab, reason: TabManagerUpdateReason) {
        guard index(of: tab) != nil else {
            return
        }
        
        if tab.mode == selectedTabMode {
            delegate?.tabManager(self, didUpdate: tab, reason: reason)
        } else {
            delegate?.tabManagerDidChangeTabs(self)
        }
    }
    
    func notifyFinishedLoading(_ session: GeckoSession) {
        delegate?.tabManager(self, didFinishLoading: session)
    }
    
    func requestHistoryThumbnail(for tab: Tab, url: String) {
        delegate?.tabManager(self, captureHistoryThumbnailFor: tab, url: url)
    }
    
    // MARK: - Startup
    
    func createInitialTab() {
        let didRestoreTabs = restoreTabsIfNeeded()
        
        switch Prefs.HomepageSettings.openingScreen {
        case .lastTab:
            if !didRestoreTabs {
                createTab(selecting: true, mode: .regular)
            }
            
        case .homepage:
            if didRestoreTabs,
               let lastTab = regularTabs.last,
               lastTab.displayedURL == nil {
                lastTab.state.showsStartupHomepage = true
                
                if selectedTab?.id != lastTab.id {
                    selectTab(lastTab)
                }
                return
            }
            
            if didRestoreTabs,
               let selectedTab,
               selectedTab.displayedURL == nil {
                selectedTab.state.showsStartupHomepage = true
                return
            }
            
            let tab = createTab(selecting: true, mode: .regular)
            tab.state.showsStartupHomepage = true
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
        
        regularTabList.restore(
            snapshot.regularTabs.map { makeRestoredTab(from: $0, isPrivate: false) },
            selectedTabID: snapshot.selectedRegularTabID
        )
        privateTabList.restore(
            snapshot.privateTabs.map { makeRestoredTab(from: $0, isPrivate: true) },
            selectedTabID: snapshot.selectedPrivateTabID
        )
        
        selectedTabMode = snapshot.selectedTabMode
        
        if tabs(for: selectedTabMode).isEmpty {
            selectedTabMode = regularTabs.isEmpty ? .private : .regular
        }
        
        let selectedTabList = tabList(for: selectedTabMode)
        let selectedTab = selectedTabList.tabs[max(selectedTabList.selectedIndex, 0)]
        
        if Prefs.HomepageSettings.openingScreen == .lastTab,
           sessionManager.isForeground {
            restoreTabIfNeeded(selectedTab)
            sessionManager.open(selectedTab.session)
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        selectTab(selectedTab)
        return true
    }
    
    private func makeRestoredTab(from snapshot: TabManagementStore.TabSnapshot, isPrivate: Bool) -> Tab {
        let sessionHandler = makeSessionHandler()
        let tab = Tab(
            id: snapshot.id,
            session: createSession(
                tabID: snapshot.id,
                url: snapshot.url,
                windowId: nil,
                isPrivate: isPrivate,
                opening: .manual,
                handler: sessionHandler
            ),
            sessionHandler: sessionHandler,
            title: snapshot.title,
            url: snapshot.url,
            createdAt: snapshot.createdAt,
            favicon: faviconStore.cachedFavicon(for: snapshot.url),
            thumbnail: snapshot.thumbnail,
            isMuted: snapshot.isMuted,
            isPrivate: isPrivate
        )
        
        if !isPrivate {
            tab.state.openerTabID = snapshot.openerTabID
        }
        
        prepareRestoration(
            serializedSessionState: snapshot.tabSessionState,
            fallbackURL: snapshot.url,
            for: tab
        )
        return tab
    }
    
    // MARK: - Tab Creation
    
    @discardableResult
    func createTab(
        selecting: Bool,
        windowId: String? = nil,
        target: TabInsertionTarget = .end,
        mode: TabMode? = nil,
        url: String? = nil,
        loadImmediately: Bool = false
    ) -> Tab {
        let mode = mode ?? selectedTabMode
        let tabID = UUID()
        let sessionHandler = makeSessionHandler()
        
        let tab = Tab(
            id: tabID,
            session: createSession(
                tabID: tabID,
                url: nil,
                windowId: windowId,
                isPrivate: mode == .private,
                handler: sessionHandler
            ),
            sessionHandler: sessionHandler,
            isPrivate: mode == .private
        )
        insert(tab, at: index(for: target, mode: mode))
        
        if selecting {
            selectTab(tab)
        } else {
            persistState()
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            loadImmediately ? browse(to: url, in: tab) : (tab.state.displayState = .pending(url))
        }
        
        return tab
    }
    
    @discardableResult
    func addTransferredSession(
        _ session: GeckoSession,
        url: String,
        title: String?,
        selecting: Bool,
        at insertionIndex: Int?,
        isPrivate: Bool = false
    ) -> Tab {
        let sessionHandler = makeSessionHandler()
        let tab = Tab(session: session, sessionHandler: sessionHandler, isPrivate: isPrivate)
        
        let isOpenedFromRegularTab = !isPrivate && selectedTab?.isPrivate == false
        tab.state.openerTabID = isOpenedFromRegularTab ? selectedTab?.id : nil
        tab.state.tabSessionState = restorableSessionState(session.currentSessionState, matching: url)
        
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates(for: sessionHandler))
        readerMode.registerMessageHandlers(for: session)
        
        let hasTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let pageTitle = hasTitle ? title : nil
        tab.url = url
        if let pageTitle {
            tab.title = pageTitle
        }
        tab.state.displayState = .committed
        tab.state.suppressInitialNavigation = true
        tab.favicon = faviconStore.cachedFavicon(for: url)
        
        insert(tab, at: insertionIndex)
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(for: tab, reason: .location)
        notifyUpdate(for: tab, reason: .title)
        tab.sessionHandler.scheduleFaviconUpdate()
        
        if !isPrivate,
           let pageURL = URLUtils.webURL(from: tab.url) {
            historyStore.recordVisit(url: pageURL, title: tab.title)
            
            if let pageTitle {
                historyStore.updatePageTitle(for: pageURL, title: pageTitle)
            }
        }
        
        if selecting {
            selectWithAnimation(tab)
        } else {
            persistState()
        }
        
        return tab
    }
    
    func addNewWindowTab(
        openedBy sourceTab: Tab?,
        from session: GeckoSession,
        uri: String,
        target: LoadRequestTarget
    ) -> GeckoSession {
        let mode = sourceTab?.mode ?? selectedTabMode
        let sourceIsPrivate = mode == .private
        let tabID = UUID()
        let sessionHandler = makeSessionHandler()
        
        let newSession = sessionManager.createSession(
            url: uri,
            tabID: tabID,
            isPrivate: sourceIsPrivate,
            opening: .external,
            delegates: sessionDelegates(for: sessionHandler)
        )
        sessionManager.universalLinkManager.didCreateNewSession(from: session, for: uri)
        
        let newTab = Tab(id: tabID, session: newSession, sessionHandler: sessionHandler, isPrivate: sourceIsPrivate)
        newTab.state.openerTabID = sourceIsPrivate ? nil : sourceTab?.id
        permissionCoordinator.restorePermissions(for: newSession, at: uri)
        newTab.url = uri
        newTab.favicon = faviconStore.cachedFavicon(for: uri)
        
        let insertionIndex = sourceTab.flatMap { index(of: $0) }.map { $0 + 1 }
        insert(newTab, at: insertionIndex)
        
        delegate?.tabManagerDidChangeTabs(self)
        notifyUpdate(for: newTab, reason: .location)
        newTab.sessionHandler.scheduleFaviconUpdate()
        persistState()
        
        if target != .background {
            selectWithAnimation(newTab)
        }
        
        return newSession
    }
    
    @discardableResult
    func restoreRecentlyClosedTab(id: UUID) -> Bool {
        guard let snapshot = store.takeRecentlyClosedTab(id: id) else {
            return false
        }
        
        let sessionHandler = makeSessionHandler()
        let tab = Tab(
            id: snapshot.id,
            session: createSession(
                tabID: snapshot.id,
                url: snapshot.url,
                windowId: nil,
                isPrivate: false,
                handler: sessionHandler
            ),
            sessionHandler: sessionHandler,
            title: snapshot.title,
            url: snapshot.url,
            favicon: faviconStore.cachedFavicon(for: snapshot.url),
            isPrivate: false
        )
        prepareRestoration(
            serializedSessionState: snapshot.tabSessionState,
            fallbackURL: snapshot.url,
            for: tab
        )
        
        insert(tab, at: nil)
        delegate?.tabManagerDidChangeTabs(self)
        selectWithAnimation(tab)
        
        return true
    }
    
    private func insert(_ tab: Tab, at insertionIndex: Int?) {
        let tabList = self.tabList(for: tab.mode)
        let count = tabList.tabs.count
        tabList.insert(tab, at: min(max(insertionIndex ?? count, 0), count))
    }
    
    private func makeSessionHandler() -> TabSessionHandler {
        return TabSessionHandler(
            delegate: sessionHandlerDelegate,
            tabManager: self,
            sessionManager: sessionManager,
            faviconStore: faviconStore,
            historyStore: historyStore,
            readerMode: readerMode,
            permissionCoordinator: permissionCoordinator,
            systemMediaSession: systemMediaSession,
            networkMonitor: networkMonitor
        )
    }
    
    private func createSession(
        tabID: UUID,
        url: String?,
        windowId: String?,
        isPrivate: Bool,
        opening: SessionOpening? = nil,
        handler: TabSessionHandler
    ) -> GeckoSession {
        let session = sessionManager.createSession(
            url: url,
            tabID: tabID,
            isPrivate: isPrivate,
            opening: opening ?? .immediate(windowID: windowId),
            delegates: sessionDelegates(for: handler)
        )
        readerMode.registerMessageHandlers(for: session)
        
        return session
    }
    
    private func sessionDelegates(for handler: TabSessionHandler) -> SessionDelegates {
        return SessionDelegates(
            content: handler,
            navigation: handler,
            history: handler,
            permission: permissionCoordinator,
            progress: handler,
            scroll: handler,
            prompt: promptCoordinator,
            print: pagePrintCoordinator,
            selectionAction: selectionActionCoordinator,
            mediaSession: systemMediaSession
        )
    }
    
    // MARK: - Selection
    
    func selectTab(_ tab: Tab) {
        guard let index = index(of: tab) else {
            return
        }
        
        let previousTab = selectedTab
        let previousTabInMode = selectedTabMode == tab.mode ? previousTab : nil
        
        selectedTabMode = tab.mode
        selectionCounter += 1
        tabList(for: tab.mode).selectedIndex = index
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
    
    private func selectWithAnimation(_ tab: Tab) {
        if let previousSession = selectedTab?.session,
           previousSession !== tab.session {
            sessionManager.deactivate(previousSession)
        }
        
        selectedTabMode = tab.mode
        delegate?.tabManager(self, animateNewTabSelectionTo: tab) { [weak self] in
            self?.selectTab(tab)
        }
    }
    
    // MARK: - Reordering And Removal
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard tabs(for: mode).indices.contains(sourceIndex),
              tabs(for: mode).indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }
        
        tabList(for: mode).move(from: sourceIndex, to: destinationIndex)
        persistState()
    }
    
    func removeTab(_ tab: Tab, behavior: TabRemovalBehavior) {
        guard let index = index(of: tab) else {
            return
        }
        
        let mode = tab.mode
        let isRemovingSelectedTab = mode == selectedTabMode && index == selectedTabIndex
        let removedTab = tabList(for: mode).remove(at: index)
        
        defer {
            delegate?.tabManagerDidChangeTabs(self)
            sessionManager.discard(removedTab.session, forTab: removedTab.id, keepingHistory: mode == .regular)
        }
        
        saveClosedTabIfNeeded(removedTab)
        
        if isRemovingSelectedTab {
            sessionManager.deactivate(removedTab.session)
        }
        removedTab.sessionHandler.cancelFaviconUpdate()
        
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
            replacementLocation = (.regular, max(regularTabList.selectedIndex, 0))
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
            tabList(for: replacementLocation.mode).selectedIndex = replacementLocation.index
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
        tabList(for: mode).removeAll()
        removedTabs.forEach { saveClosedTabIfNeeded($0) }
        removedTabs.forEach { $0.sessionHandler.cancelFaviconUpdate() }
        
        let fallbackTabList = tabList(for: mode == .regular ? .private : .regular)
        if mode == selectedTabMode,
           !fallbackTabList.tabs.isEmpty {
            selectTab(fallbackTabList.tabs[max(fallbackTabList.selectedIndex, 0)])
        } else {
            persistState()
        }
        delegate?.tabManagerDidChangeTabs(self)
        
        removedTabs.forEach { sessionManager.discard($0.session, forTab: $0.id, keepingHistory: mode == .regular) }
    }
    
    private func saveClosedTabIfNeeded(_ tab: Tab) {
        guard !tab.isPrivate,
              let url = tab.displayedURL else {
            return
        }
        
        store.saveRecentlyClosedTab(
            id: tab.id,
            title: tab.title,
            url: url,
            tabSessionState: tab.state.tabSessionState?.serializedString()
        )
    }
    
    // MARK: - Restoration
    
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
        guard URLUtils.restorableURL(from: currentURL) != nil,
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
        
        tab.state.restoreState = URLUtils.restorableURL(from: fallbackURL).map(TabRestoreState.pendingURL) ?? .none
    }
    
    private func prepareRestoration(for tab: Tab) {
        if let sessionState = restorableSessionState(tab.state.tabSessionState) {
            tab.state.tabSessionState = sessionState
            tab.state.restoreState = .pendingSession
        } else {
            tab.state.tabSessionState = nil
            tab.state.restoreState = URLUtils.restorableURL(from: tab.url).map(TabRestoreState.pendingURL) ?? .none
        }
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
            tab.sessionHandler.load(url)
        case .none:
            break
        }
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
            opening: .manual,
            handler: tab.sessionHandler
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
    
    func handleSessionTermination(_ session: GeckoSession, recoverAutomatically: Bool) {
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
        tab.state.loadError = WebRequestError(kind: .contentCrashed, uri: tab.displayedURL)
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
            tab.sessionHandler.load(URLUtils.fixTLDTypo(in: navigationInput))
            return
        }
        
        let searchDestination = SearchEngine.destination(for: navigationInput)
        tab.sessionHandler.load(searchDestination)
    }
    
    @discardableResult
    func openExternalURL(_ url: URL) -> Tab? {
        let selectedURL = selectedTab?.url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isSelectedTabBlank = selectedURL.isEmpty || selectedURL.hasPrefix("about:blank")
        
        let tab: Tab
        if let selectedTab,
           isSelectedTabBlank {
            tab = selectedTab
        } else {
            tab = createTab(selecting: true)
        }
        
        browse(to: url.absoluteString, in: tab)
        return tab
    }
    
    func reloadOrStopSelectedTab() {
        guard let selectedTab else {
            return
        }
        
        selectedTab.state.loadingState.isLoading ? selectedTab.session.stop() : selectedTab.session.reload()
    }
    
    func hardReloadSelectedTab() {
        guard let selectedTab else {
            return
        }
        
        selectedTab.session.reload(flags: GeckoSessionLoadFlags.bypassCache)
    }
    
    @discardableResult
    func changeWebsiteModeForSelectedTab() -> Bool {
        guard let tab = selectedTab,
              let url = tab.url,
              let navigationAction = sessionManager.toggleWebsiteMode(
                for: url,
                tabID: tab.id
              ) else {
            return false
        }
        
        switch navigationAction {
        case .reload:
            sessionManager.updateSettings(of: tab.session, for: url, tabID: tab.id)
            tab.session.reload()
        case let .load(overrideURL):
            tab.state.displayState = .pending(overrideURL)
            tab.state.suppressInitialNavigation = false
            sessionManager.updateSettings(of: tab.session, for: overrideURL, tabID: tab.id)
            tab.session.load(overrideURL, flags: GeckoSessionLoadFlags.replaceHistory)
        }
        
        return true
    }
    
    // MARK: - History Navigation
    
    func goBack() {
        guard let tab = selectedTab else {
            return
        }
        
        if !tab.state.navigationState.canGoBack,
           let openerTab {
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
    
    func goForward() {
        selectedTab?.session.goForward()
    }
    
    func goToHistory(offset: Int) {
        guard let tab = selectedTab,
              let currentHistoryIndex = tab.displayedSessionState?.currentHistoryIndex else {
            return
        }
        
        tab.session.goToHistoryIndex(currentHistoryIndex + offset)
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
                   let pageURL = URLUtils.webURL(from: url) {
                    historyStore.recordVisit(url: pageURL, title: title ?? "")
                }
            } catch {
                tab.sessionHandler.load(url)
            }
            
            sessionManager.close(previewSession)
        }
    }
    
    // MARK: - Tab Updates
    
    func updateThumbnail(_ image: UIImage?, for tab: Tab) {
        guard index(of: tab) != nil else {
            return
        }
        
        tab.thumbnail = image
        store.persistThumbnail(image, for: tab.id)
        notifyUpdate(for: tab, reason: .thumbnail)
    }
    
    func updateHistoryThumbnail(_ image: UIImage, for tab: Tab, url: String, isPreparedForNavigation: Bool) {
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
            tabID: tab.id
        ) { [weak self] in
            self?.notifyUpdate(for: tab, reason: .navigationState)
        }
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
        for tab in tabs(for: selectedTabMode) where tab.id != tabID {
            guard tab.state.isPlayingAudio,
                  !tab.isMuted else {
                continue
            }
            
            setMuted(true, for: tab.id)
        }
    }
}

extension TabManager: SystemMediaSessionPlaybackObserver {
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

extension TabManager: ReaderModeControllerDelegate {
    func readerModeController(_ controller: ReaderModeController, tabFor session: GeckoSession) -> Tab? {
        return tab(for: session)
    }
    
    func readerModeController(_ controller: ReaderModeController, didChangeStateFor tab: Tab) {
        notifyUpdate(for: tab, reason: .readerMode)
    }
}
