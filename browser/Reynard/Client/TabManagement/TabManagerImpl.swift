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
    
    private let promptCoordinator = PromptCoordinator(
        presenter: PromptPresenter()
    )
    private let selectionActionCoordinator = SelectionActionCoordinator(
        presenter: SelectionActionPresenter()
    )
    private let permissionCoordinator = PermissionCoordinator(
        promptPresenter: PermissionPromptPresenter()
    )
    private let systemMediaSession = SystemMediaSession()
    
    private weak var delegate: TabManagerDelegate?
    private let store: TabManagementStore
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    let sessionManager: SessionManager
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
    
    private func recordNavigation(_ url: String, for tab: Tab) {
        tab.state.navigationState = sessionManager.recordNavigation(
            to: url,
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
                    isPrivate: false
                ),
                title: snapshot.title,
                url: snapshot.url,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isPrivate: false
            )
            tab.state.restoreState = restoredURL(from: snapshot.url).map(TabRestoreState.pending) ?? .none
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
                    isPrivate: true
                ),
                title: snapshot.title,
                url: snapshot.url,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isPrivate: true
            )
            tab.state.restoreState = restoredURL(from: snapshot.url).map(TabRestoreState.pending) ?? .none
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
    
    private func loadRestoredURLIfNeeded(for index: Int, mode: TabMode) {
        guard tabs(for: mode).indices.contains(index) else {
            return
        }
        
        let tab = tabs(for: mode)[index]
        guard case let .pending(url) = tab.state.restoreState else {
            return
        }
        
        tab.state.restoreState = .none
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
        tab.state.restoreState = restoredURL(from: snapshot.url).map(TabRestoreState.pending) ?? .none
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
    
    // MARK: - Tab Lifecycle
    
    private func saveClosedTabIfNeeded(_ tab: Tab, mode: TabMode) {
        guard mode == .regular,
              let url = displayedURL(for: tab) else {
            return
        }
        
        store.saveRecentlyClosedTab(id: tab.id, title: tab.title, url: url)
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
        
        delegate?.tabManagerDidChangeTabs(self)
        
        if selecting {
            selectTab(at: index, mode: mode)
        } else {
            persistState()
        }
        
        return index
    }
    
    @discardableResult
    func addTransferredSession(_ session: GeckoSession, url: String, title: String?, selecting: Bool, at insertionIndex: Int?, isPrivate: Bool = false) -> Int {
        let tab = Tab(session: session, isPrivate: isPrivate)
        let mode: TabMode = isPrivate ? .private : .regular
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates)
        applyTransferredState(to: tab, url: url, title: title)
        recordNavigation(url, for: tab)
        
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
        sessionManager.activate(selectedTab.session)
        systemMediaSession.select(session: selectedTab.session)
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
            delegate?.tabManagerDidChangeTabs(self)
            persistState()
            sessionManager.discard(removedTab.session, forTab: removedTab.id, keepingHistory: mode == .regular)
            return
        }
        
        delegate?.tabManagerDidChangeTabs(self)
        
        if wasSelected {
            if !tabs(for: mode).isEmpty {
                selectTab(at: min(index, tabs(for: mode).count - 1), mode: mode)
            } else {
                let fallbackMode: TabMode = mode == .regular ? .private : .regular
                selectTab(at: max(selectedIndex(for: fallbackMode), 0), mode: fallbackMode)
            }
        } else {
            persistState()
        }
        
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
        delegate?.tabManagerDidChangeTabs(self)
        
        if mode == selectedTabMode {
            if mode == .private && !regularTabs.isEmpty {
                selectTab(at: max(selectedRegularTabIndex, 0), mode: .regular)
            } else if mode == .regular && !privateTabs.isEmpty {
                selectTab(at: max(selectedPrivateTabIndex, 0), mode: .private)
            } else {
                persistState()
            }
        } else {
            persistState()
        }
        
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
    
    func goBack() {
        guard let tab = selectedTab,
              let transition = sessionManager.goBack(
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
        guard let tab = selectedTab,
              let transition = sessionManager.goForward(
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
    
    // MARK: - Session Replacement
    
    func replaceSelectedSession(with session: GeckoSession, url: String, title: String?) {
        guard let tab = selectedTab else {
            return
        }
        
        let oldSession = tab.session
        
        sessionManager.adopt(session, asTab: tab.id, url: url, delegates: sessionDelegates)
        tab.session = session
        applyTransferredState(to: tab, url: url, title: title)
        tab.state.sessionNavigationAvailability = .unavailable
        recordNavigation(url, for: tab)
        tab.state.navigationState = sessionManager.useStoredNavigationHistory(for: tab.id)
        sessionManager.activate(session)
        
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
    
    // MARK: - Session Factory
    
    private func createSession(
        tabID: UUID,
        url: String?,
        windowId: String?,
        isPrivate: Bool
    ) -> GeckoSession {
        return sessionManager.createSession(
            url: url,
            tabID: tabID,
            isPrivate: isPrivate,
            opening: .immediate(windowID: windowId),
            delegates: sessionDelegates
        )
    }
}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let location = tabLocation(for: session) else {
            return
        }
        
        let tab = tabs(for: location.mode)[location.index]
        tab.title = title
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
        
        delegate?.tabManager(self, didChangeFullscreen: fullScreen, for: session)
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
        guard let location = tabLocation(for: session) else {
            return
        }
        removeTab(at: location.index, mode: location.mode)
    }
    
    func onKill(session: GeckoSession) {
        guard let location = tabLocation(for: session) else {
            return
        }
        removeTab(at: location.index, mode: location.mode)
    }
    
    func onFirstComposite(session: GeckoSession) {}
    
    func onFirstContentfulPaint(session: GeckoSession) {}
    
    func onPaintStatusReset(session: GeckoSession) {}
    
    func onWebAppManifest(session: GeckoSession, manifest: Any) {}
    
    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        return .halt
    }
    
    func onShowDynamicToolbar(session: GeckoSession) {}
    
    func onCookieBannerDetected(session: GeckoSession) {}
    
    func onCookieBannerHandled(session: GeckoSession) {}
    
    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) {
        if delegate?.tabManager(self, shouldHandleExternalResponse: response, for: session) == true {
            return
        }
        guard let download = DownloadStore.shared.pendingDownload(from: response) else {
            return
        }
        
        delegate?.tabManager(self, didRequestDownload: download)
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
        
        if let normalizedURL, !normalizedURL.isEmpty {
            tab.state.suppressInitialNavigation = false
        }
        
        if let url {
            sessionManager.updateSettings(of: session, for: url, tabID: tab.id)
            permissionCoordinator.restorePermissions(for: session, at: url)
        }
        
        tab.url = url
        if let url {
            recordNavigation(url, for: tab)
        }
        tab.state.displayState = .committed
        tab.favicon = nil
        notifyUpdate(at: location.index, mode: location.mode, reason: .location)
        scheduleFaviconUpdate(forTabAt: location.index, mode: location.mode)
        persistState()
        
        guard !tab.isPrivate,
              let url = remoteURL(from: tab.url) else {
            return
        }
        
        historyStore.recordVisit(url: url, title: tab.title)
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
        return .allow
    }
    
    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return .allow
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
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

extension TabManagerImplementation: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        if url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank"),
           hasDisplayURL(for: tab) {
            tab.state.isSuppressingInitialBlankPageLoad = true
            return
        }
        
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
