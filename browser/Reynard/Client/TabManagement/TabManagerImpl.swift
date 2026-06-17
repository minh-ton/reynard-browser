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
        selectedIndex(for: selectedTabMode)
    }
    
    var selectedTab: Tab? {
        tabs(for: selectedTabMode)[safe: selectedTabIndex]
    }
    
    private let enginePromptCoordinator = EnginePromptCoordinator()
    private let engineSelectionActionCoordinator = EngineSelectionActionCoordinator()
    private let engineMediaSessionCoordinator = EngineMediaSessionCoordinator()
    private let enginePermissionCoordinator = EnginePermissionCoordinator()

    private weak var delegate: TabManagerDelegate?
    private let store: TabManagementStore
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    private let sessionStore: TabSessionStore
    private var faviconTasks: [UUID: Task<Void, Never>] = [:]
    private var selectionCounter = 0
    
    private lazy var isURLLenient: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    init(
        delegate: TabManagerDelegate?,
        store: TabManagementStore = .shared,
        sessionStore: TabSessionStore = .shared,
        faviconStore: FaviconStore = .shared,
        historyStore: HistoryStore = .shared
    ) {
        self.delegate = delegate
        self.store = store
        self.sessionStore = sessionStore
        self.faviconStore = faviconStore
        self.historyStore = historyStore
    }
    
    private func closeSession(_ session: GeckoSession) {
        SitePermissionStore.shared.removePrivateTabPerms(for: session)
        if session.isOpen() {
            session.setActive(false)
        }
        session.close()
    }
    
    private func cancelFaviconTask(for tabID: UUID) {
        faviconTasks.removeValue(forKey: tabID)?.cancel()
    }
    
    private func persistState() {
        store.saveTabs(
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
    
    private func loadURL(_ url: String, in tab: Tab) {
        tab.session.updateSettings(GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id))
        tab.session.load(url)
    }
    
    private func applyNavigationState(to tab: Tab) {
        let snapshot = sessionStore.loadSnapshot(for: tab.id)
        if snapshot.ownsNav {
            tab.state.navigationState = .history(back: snapshot.canGoBack, forward: snapshot.canGoForward)
            return
        }
        
        tab.state.navigationState = .session(
            back: snapshot.canGoBack || tab.state.sessionNavigationState.canGoBack,
            forward: snapshot.canGoForward || tab.state.sessionNavigationState.canGoForward
        )
    }
    
    private func recordNavigation(_ url: String, for tab: Tab) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              trimmedURL.lowercased() != "about:blank" else {
            return
        }
        
        let snapshot = sessionStore.recordNavigation(to: trimmedURL, for: tab.id)
        if snapshot.ownsNav {
            tab.state.navigationState = .history(back: snapshot.canGoBack, forward: snapshot.canGoForward)
            return
        }
        
        tab.state.navigationState = .session(
            back: snapshot.canGoBack || tab.state.sessionNavigationState.canGoBack,
            forward: snapshot.canGoForward || tab.state.sessionNavigationState.canGoForward
        )
    }
    
    private func makeTab(windowId: String?, isPrivate: Bool) -> Tab {
        Tab(session: createSession(windowId: windowId, isPrivate: isPrivate), isPrivate: isPrivate)
    }
    
    private func bindDelegates(to session: GeckoSession) {
        session.contentDelegate = self
        session.progressDelegate = self
        session.navigationDelegate = self
        session.permissionDelegate = enginePermissionCoordinator
        session.promptDelegate = enginePromptCoordinator
        session.selectionActionDelegate = engineSelectionActionCoordinator
        session.mediaSessionDelegate = engineMediaSessionCoordinator
    }
    
    private func applyTransferredState(to tab: Tab, url: String, title: String?) {
        tab.url = url
        if let title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab.title = title
        }
        tab.state.displayState = .committed
        tab.state.suppressInitialNavigation = true
        tab.favicon = cachedFavicon(for: url)
        tab.session.updateSettings(GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id))
    }
    
    private func recordTransferredHistory(for tab: Tab, title: String?) {
        guard !tab.isPrivate,
              let url = remoteURL(from: tab.url) else {
            return
        }
        
        historyStore.recordVisit(url: url, title: tab.title)
        if let title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            historyStore.updateTitle(for: url, title: title)
        }
    }
    
    private func restoredURL(from value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty,
              trimmedValue.lowercased() != "about:blank" else {
            return nil
        }
        
        return trimmedValue
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
    
    private func cachedFavicon(for value: String?) -> UIImage? {
        guard let url = remoteURL(from: value) else {
            return nil
        }
        
        return faviconStore.cachedImage(for: url)
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
            
            let image = await self.faviconStore.resolveFavicon(for: url)
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
    
    private func restoreTabsIfNeeded() -> Bool {
        guard regularTabs.isEmpty && privateTabs.isEmpty else {
            return true
        }
        
        let snapshot = store.loadSnapshot()
        guard !snapshot.regularTabs.isEmpty || !snapshot.privateTabs.isEmpty else {
            return false
        }
        
        regularTabs = snapshot.regularTabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                session: createSession(windowId: nil, isPrivate: false),
                title: snapshot.title,
                url: snapshot.url,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isPrivate: false
            )
            tab.state.restoreState = restoredURL(from: snapshot.url).map(TabRestoreState.pending) ?? .none
            let sessionSnapshot = sessionStore.loadSnapshot(for: tab.id)
            if sessionSnapshot.canGoBack || sessionSnapshot.canGoForward {
                _ = sessionStore.setOwnsNav(true, for: tab.id)
            }
            applyNavigationState(to: tab)
            return tab
        }
        
        privateTabs = snapshot.privateTabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                session: createSession(windowId: nil, isPrivate: true),
                title: snapshot.title,
                url: snapshot.url,
                favicon: cachedFavicon(for: snapshot.url),
                thumbnail: snapshot.thumbnail,
                isPrivate: true
            )
            tab.state.restoreState = restoredURL(from: snapshot.url).map(TabRestoreState.pending) ?? .none
            let sessionSnapshot = sessionStore.loadSnapshot(for: tab.id)
            if sessionSnapshot.canGoBack || sessionSnapshot.canGoForward {
                _ = sessionStore.setOwnsNav(true, for: tab.id)
            }
            applyNavigationState(to: tab)
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
    
    func createInitialTab() {
        if restoreTabsIfNeeded() {
            return
        }
        
        addTab(selecting: true, windowId: nil, at: nil, isPrivate: false)
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
        bindDelegates(to: session)
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
            selectedTabMode = mode
            delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
                self?.selectTab(at: index, mode: mode)
            }
            session.setFocused(true)
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
        
        let previousMode = selectedTabMode
        let previousIndex = previousMode == mode && tabs(for: previousMode).indices.contains(selectedTabIndex) ? selectedTabIndex : nil
        
        selectedTabMode = mode
        selectionCounter += 1
        setSelectedIndex(index, for: mode)
        tabs(for: mode)[index].state.selectionOrder = selectionCounter
        tabs(for: mode)[index].session.setActive(true)
        applyNavigationState(to: tabs(for: mode)[index])
        
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
        cancelFaviconTask(for: removedTab.id)
        GeckoSessionController.shared.clearOverrides(forTabID: removedTab.id)
        sessionStore.removeSession(for: removedTab.id)
        
        if tabs(for: mode).isEmpty {
            setSelectedIndex(-1, for: mode)
        } else if index < selectedIndex(for: mode) {
            setSelectedIndex(selectedIndex(for: mode) - 1, for: mode)
        }
        
        if regularTabs.isEmpty && privateTabs.isEmpty {
            delegate?.tabManagerDidChangeTabs(self)
            persistState()
            closeSession(removedTab.session)
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
        
        closeSession(removedTab.session)
    }
    
    func removeAllTabs(mode: TabMode? = nil) {
        let mode = mode ?? selectedTabMode
        guard !tabs(for: mode).isEmpty else {
            return
        }
        
        let removedTabs = tabs(for: mode)
        if mode == .regular {
            regularTabs.removeAll(keepingCapacity: true)
            selectedRegularTabIndex = -1
        } else {
            privateTabs.removeAll(keepingCapacity: true)
            selectedPrivateTabIndex = -1
        }
        removedTabs.forEach { cancelFaviconTask(for: $0.id) }
        removedTabs.forEach { GeckoSessionController.shared.clearOverrides(forTabID: $0.id) }
        removedTabs.forEach { sessionStore.removeSession(for: $0.id) }
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
        
        removedTabs.forEach { closeSession($0.session) }
    }
    
    func browse(to term: String) {
        guard let tab = selectedTab else {
            return
        }
        browse(to: term, in: tab)
    }
    
    func browse(to term: String, in tab: Tab) {
        let trimmedValue = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }
        
        tab.state.suppressInitialNavigation = false
        tab.state.displayState = .pending(trimmedValue)
        
        let fullRange = NSRange(location: 0, length: (trimmedValue as NSString).length)
        let isURL = isURLLenient.firstMatch(in: trimmedValue, range: fullRange) != nil
        
        if isURL {
            loadURL(trimmedValue, in: tab)
            return
        }
        
        let searchTarget = searchURL(for: trimmedValue)
        loadURL(searchTarget, in: tab)
    }
    
    func goBack() {
        guard let tab = selectedTab else {
            return
        }
        
        let snapshot = sessionStore.loadSnapshot(for: tab.id)
        if !snapshot.ownsNav && tab.state.sessionNavigationState.canGoBack {
            _ = sessionStore.previousURL(for: tab.id)
            applyNavigationState(to: tab)
            delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
            tab.session.goBack()
            return
        }
        
        guard let url = sessionStore.previousURL(for: tab.id) else {
            return
        }
        
        _ = sessionStore.setOwnsNav(true, for: tab.id)
        applyNavigationState(to: tab)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
        loadURL(url, in: tab)
    }
    
    func goForward() {
        guard let tab = selectedTab else {
            return
        }
        
        let snapshot = sessionStore.loadSnapshot(for: tab.id)
        if !snapshot.ownsNav && tab.state.sessionNavigationState.canGoForward {
            _ = sessionStore.nextURL(for: tab.id)
            applyNavigationState(to: tab)
            delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
            tab.session.goForward()
            return
        }
        
        guard let url = sessionStore.nextURL(for: tab.id) else {
            return
        }
        
        _ = sessionStore.setOwnsNav(true, for: tab.id)
        applyNavigationState(to: tab)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .navigationState)
        loadURL(url, in: tab)
    }
    
    func replaceSelectedSession(with session: GeckoSession, url: String, title: String?) {
        guard let tab = selectedTab else {
            return
        }
        
        let oldSession = tab.session
        closeSession(oldSession)
        
        bindDelegates(to: session)
        tab.session = session
        applyTransferredState(to: tab, url: url, title: title)
        tab.state.sessionNavigationState = .unavailable
        recordNavigation(url, for: tab)
        _ = sessionStore.setOwnsNav(true, for: tab.id)
        applyNavigationState(to: tab)
        session.setActive(true)
        session.setFocused(true)
        
        delegate?.tabManagerDidChangeTabs(self)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .location)
        delegate?.tabManager(self, didUpdateTabAt: selectedTabIndex, reason: .title)
        scheduleFaviconUpdate(forTabAt: selectedTabIndex)
        persistState()
        recordTransferredHistory(for: tab, title: title)
    }
    
    func tabIndex(for session: GeckoSession) -> Int? {
        tabs(for: selectedTabMode).firstIndex(where: { $0.session === session })
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
    
    func updateThumbnail(_ image: UIImage?, forTabAt index: Int) {
        guard tabs(for: selectedTabMode).indices.contains(index) else {
            return
        }
        
        let tab = tabs(for: selectedTabMode)[index]
        tab.thumbnail = image
        store.saveThumbnail(image, for: tab.id)
    }
    
    private func createSession(windowId: String?, isPrivate: Bool) -> GeckoSession {
        let session = GeckoSession()
        session.isPrivateMode = isPrivate
        session.contentDelegate = self
        session.progressDelegate = self
        session.navigationDelegate = self
        session.permissionDelegate = enginePermissionCoordinator
        session.promptDelegate = enginePromptCoordinator
        session.selectionActionDelegate = engineSelectionActionCoordinator
        session.mediaSessionDelegate = engineMediaSessionCoordinator
        session.open(windowId: windowId)
        return session
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
            historyStore.updateTitle(for: url, title: title)
        }
        notifyUpdate(at: location.index, mode: location.mode, reason: .title)
        persistState()
    }
    
    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}
    
    func onFocusRequest(session: GeckoSession) {
        guard selectedTab?.session === session else {
            return
        }
        
        session.setActive(true)
        session.setFocused(true)
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
        .halt
    }
    
    func onShowDynamicToolbar(session: GeckoSession) {}
    
    func onCookieBannerDetected(session: GeckoSession) {}
    
    func onCookieBannerHandled(session: GeckoSession) {}
    
    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) {
        if delegate?.tabManager(self, shouldHandleExternalResponse: response, for: session) == true {
            return
        }
        guard let download = DownloadStore.shared.prepareDownload(from: response) else {
            return
        }
        
        delegate?.tabManager(self, didRequestDownload: download)
    }
    
    func onSavePdf(session: GeckoSession, request: SavePdfInfo) {
        guard let download = DownloadStore.shared.prepareDownload(from: request) else {
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
        
        if tab.state.suppressInitialNavigation,
           let normalizedURL,
           normalizedURL.hasPrefix("about:blank") {
            return
        }
        
        if let normalizedURL, !normalizedURL.isEmpty {
            tab.state.suppressInitialNavigation = false
        }
        
        if let url {
            session.updateSettings(GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id))
            enginePermissionCoordinator.applyStoredPermissions(to: session, urlString: url)
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
        
        tab.state.sessionNavigationState = .available(
            back: canGoBack,
            forward: tab.state.sessionNavigationState.canGoForward
        )
        applyNavigationState(to: tab)
        notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
    }
    
    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let location = tabLocation(for: session) else {
            return
        }
        let tab = tabs(for: location.mode)[location.index]
        
        tab.state.sessionNavigationState = .available(
            back: tab.state.sessionNavigationState.canGoBack,
            forward: canGoForward
        )
        applyNavigationState(to: tab)
        notifyUpdate(at: location.index, mode: location.mode, reason: .navigationState)
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }
    
    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        let newSession = GeckoSession()
        
        let sourceLocation = tabLocation(for: session)
        let mode = sourceLocation?.mode ?? selectedTabMode
        let sourceIsPrivate = mode == .private
        newSession.isPrivateMode = sourceIsPrivate
        newSession.contentDelegate = self
        newSession.progressDelegate = self
        newSession.navigationDelegate = self
        newSession.permissionDelegate = enginePermissionCoordinator
        newSession.promptDelegate = enginePromptCoordinator
        newSession.selectionActionDelegate = engineSelectionActionCoordinator
        newSession.mediaSessionDelegate = engineMediaSessionCoordinator
        let newTab = Tab(session: newSession, isPrivate: sourceIsPrivate)
        newSession.updateSettings(GeckoSessionController.shared.sessionSettings(for: uri, tabID: newTab.id))
        enginePermissionCoordinator.applyStoredPermissions(to: newSession, urlString: uri)
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
        
        let currentHost = tab.url.flatMap { GeckoSessionController.shared.extractHost(from: $0) }
        let requestedHost = GeckoSessionController.shared.extractHost(from: url)
        let desiredSettings = GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id)
        
        if currentHost != nil,
           requestedHost != nil,
           currentHost != requestedHost,
           (desiredSettings.userAgentOverride != session.userAgentOverride ||
            desiredSettings.userAgentMode != session.userAgentMode ||
            desiredSettings.viewportMode != session.viewportMode) {
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
