//
//  TabSessionHandler.swift
//  Reynard
//
//  Created by Minh Ton on 22/11/26.
//

import GeckoView
import Network
import UIKit

protocol TabSessionHandlerDelegate: AnyObject {
    func tabSessionHandler(_ handler: TabSessionHandler, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession)
    func tabSessionHandler(_ handler: TabSessionHandler, didChangeFullscreen fullScreen: Bool, for session: GeckoSession)
    func tabSessionHandler(_ handler: TabSessionHandler, didRequestDownload download: DownloadStore.PendingDownload)
    func tabSessionHandler(_ handler: TabSessionHandler, shouldStartExternalResponse response: ExternalResponseInfo, for session: GeckoSession) async -> Bool
    func tabSessionHandler(_ handler: TabSessionHandler, shouldContinueExternalResponseAt localFilePath: String, bytesReceived: Int64) -> Bool
    func tabSessionHandler(_ handler: TabSessionHandler, didCompleteExternalResponseAt localFilePath: String, succeeded: Bool)
}

final class TabSessionHandler {
    weak var tab: Tab?
    
    private weak var delegate: TabSessionHandlerDelegate?
    private let tabManager: TabManager
    private let sessionManager: SessionManager
    private let faviconStore: FaviconStore
    private let historyStore: HistoryStore
    private let readerMode: ReaderModeController
    private let permissionCoordinator: PermissionCoordinator
    private let systemMediaSession: SystemMediaSession
    private let networkMonitor: NWPathMonitor
    private var faviconTask: Task<Void, Never>?
    
    init(
        delegate: TabSessionHandlerDelegate?,
        tabManager: TabManager,
        sessionManager: SessionManager,
        faviconStore: FaviconStore,
        historyStore: HistoryStore,
        readerMode: ReaderModeController,
        permissionCoordinator: PermissionCoordinator,
        systemMediaSession: SystemMediaSession,
        networkMonitor: NWPathMonitor
    ) {
        self.delegate = delegate
        self.tabManager = tabManager
        self.sessionManager = sessionManager
        self.faviconStore = faviconStore
        self.historyStore = historyStore
        self.readerMode = readerMode
        self.permissionCoordinator = permissionCoordinator
        self.systemMediaSession = systemMediaSession
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Tab Lookup
    
    private func currentTab(for session: GeckoSession) -> Tab? {
        guard let tab,
              tab.session === session,
              tabManager.tabs(for: tab.mode).contains(where: { $0 === tab }) else {
            return nil
        }
        
        return tab
    }
    
    // MARK: - Loading
    
    func load(_ url: String) {
        guard let tab else {
            return
        }
        
        tab.state.loadError = nil
        tab.state.restoreState = .none
        tab.state.showsStartupHomepage = false
        tab.state.loadingState = .loading(progress: 0)
        tabManager.notifyUpdate(for: tab, reason: .loading)
        
        sessionManager.updateSettings(of: tab.session, for: url, tabID: tab.id)
        tab.session.load(url)
    }
    
    // MARK: - Favicons
    
    func scheduleFaviconUpdate() {
        guard let tab else {
            return
        }
        
        cancelFaviconUpdate()
        
        let cachedImage = faviconStore.cachedFavicon(for: tab.url)
        tab.favicon = cachedImage
        tabManager.notifyUpdate(for: tab, reason: .favicon)
        
        guard cachedImage == nil,
              let url = URLUtils.webURL(from: tab.url) else {
            return
        }
        
        resolveFavicon(for: url) { [faviconStore] in
            await faviconStore.favicon(for: url)
        }
    }
    
    func cancelFaviconUpdate() {
        faviconTask?.cancel()
        faviconTask = nil
    }
    
    private func resolveFavicon(for url: URL, using fetch: @escaping () async -> UIImage?) {
        cancelFaviconUpdate()
        
        let expectedURL = url.absoluteString
        faviconTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            let image = await fetch()
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                self.applyResolvedFavicon(image, expectedURL: expectedURL)
            }
        }
    }
    
    @MainActor
    private func applyResolvedFavicon(_ image: UIImage?, expectedURL: String) {
        faviconTask = nil
        
        guard let tab,
              tab.url == expectedURL else {
            return
        }
        
        tab.favicon = image
        tabManager.notifyUpdate(for: tab, reason: .favicon)
    }
}

extension TabSessionHandler: ScrollDelegate {
    func onScrollChanged(session: GeckoSession, scrollX: Int, scrollY: Int) {
        guard let tab = currentTab(for: session),
              tab.state.readerMode.isActive else {
            return
        }
        
        tab.state.readerMode.sourceScrollY = scrollY
    }
}

extension TabSessionHandler: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let tab = currentTab(for: session) else {
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
           let url = URLUtils.webURL(from: tab.url) {
            historyStore.updatePageTitle(for: url, title: title)
        }
        
        tabManager.notifyUpdate(for: tab, reason: .title)
        tabManager.persistState()
    }
    
    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}
    
    func onFocusRequest(session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        
        sessionManager.activate(session)
    }
    
    func onCloseRequest(session: GeckoSession) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        tabManager.removeTab(tab, behavior: .recent)
    }
    
    func onFullScreen(session: GeckoSession, fullScreen: Bool) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        
        delegate?.tabSessionHandler(
            self,
            didChangeFullscreen: fullScreen,
            for: session
        )
    }
    
    func onPictureInPictureRestore(session: GeckoSession) {
        guard tabManager.selectedTab?.session !== session,
              let tab = currentTab(for: session) else {
            return
        }
        
        tabManager.selectTab(tab)
    }
    
    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {}
    
    func onProductUrl(session: GeckoSession) {}
    
    func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: ContextElement) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        
        let imageSource = element.srcUri?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = element.linkUri?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasImageSource = element.type == .image && !imageSource.isEmpty
        guard hasImageSource || !link.isEmpty else {
            return
        }
        
        delegate?.tabSessionHandler(
            self,
            didRequestContextMenuAt: CGPoint(x: screenX, y: screenY),
            for: element,
            in: session
        )
    }
    
    func onCrash(session: GeckoSession) {
        tabManager.handleSessionTermination(session, recoverAutomatically: false)
    }
    
    func onKill(session: GeckoSession) {
        tabManager.handleSessionTermination(session, recoverAutomatically: true)
    }
    
    func onFirstComposite(session: GeckoSession) {}
    
    func onFirstContentfulPaint(session: GeckoSession) {}
    
    func onPaintStatusReset(session: GeckoSession) {}
    
    func onPageBackgroundColorChange(session: GeckoSession, color: UIColor) {
        sessionManager.setPageBackgroundColor(color, for: session)
        
        guard let tab = currentTab(for: session),
              tab.mode == tabManager.selectedTabMode else {
            return
        }
        
        tabManager.notifyUpdate(for: tab, reason: .pageBackgroundColor)
    }
    
    func onWebAppManifest(session: GeckoSession, manifest: Any) {
        guard let tab = currentTab(for: session),
              let url = URLUtils.webURL(from: tab.url) else {
            return
        }
        
        resolveFavicon(for: url) { [faviconStore] in
            await faviconStore.favicon(for: url, webAppManifest: manifest)
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
        
        let shouldStart = await delegate?.tabSessionHandler(
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
        return delegate?.tabSessionHandler(
            self,
            shouldContinueExternalResponseAt: localFilePath,
            bytesReceived: bytesReceived
        ) ?? false
    }
    
    func onExternalResponseComplete(session: GeckoSession, localFilePath: String, succeeded: Bool) {
        delegate?.tabSessionHandler(
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
        
        delegate?.tabSessionHandler(self, didRequestDownload: download)
    }
}

extension TabSessionHandler: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let tab = currentTab(for: session) else {
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
        
        if let error = tab.state.loadError,
           url != error.uri {
            tab.state.loadError = nil
            tabManager.notifyUpdate(for: tab, reason: .loadError)
        }
        
        let engineURL = url
        let url = url.map { readerMode.displayedURL(for: $0, in: tab) }
        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shouldPreserveDisplayedURL = tab.displayedURL != nil
        
        if let normalizedURL,
           normalizedURL.hasPrefix("about:blank"),
           (tab.state.suppressInitialNavigation || shouldPreserveDisplayedURL) {
            return
        }
        
        sessionManager.universalLinkManager.didCommitNavigation(in: session)
        
        if let normalizedURL,
           !normalizedURL.isEmpty {
            tab.state.suppressInitialNavigation = false
        }
        
        if let url {
            sessionManager.updateSettings(of: session, for: url, tabID: tab.id)
            permissionCoordinator.restorePermissions(for: session, at: url)
            
            if let currentURL = tab.url,
               currentURL != url,
               tab.state.preparedNavigationThumbnailURL != currentURL {
                tabManager.requestHistoryThumbnail(for: tab, url: currentURL)
            }
        }
        
        tab.state.preparedNavigationThumbnailURL = nil
        tab.url = url
        tab.state.committedEngineURL = engineURL
        tab.state.displayedHistoryEntry = tab.state.matchingHistoryEntry
        tab.state.displayState = .committed
        tab.favicon = nil
        
        tabManager.notifyUpdate(for: tab, reason: .location)
        scheduleFaviconUpdate()
        tabManager.persistState()
        session.flushSessionState()
    }
    
    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        tab.state.navigationState = NavigationAvailability(
            canGoBack: canGoBack,
            canGoForward: tab.state.navigationState.canGoForward
        )
        tabManager.notifyUpdate(for: tab, reason: .navigationState)
    }
    
    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        tab.state.navigationState = NavigationAvailability(
            canGoBack: tab.state.navigationState.canGoBack,
            canGoForward: canGoForward
        )
        tabManager.notifyUpdate(for: tab, reason: .navigationState)
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
        guard let tab = currentTab(for: session) else {
            return nil
        }
        
        var error = error
        if error.kind == .unknownHost,
           networkMonitor.currentPath.status != .satisfied {
            error.kind = .noInternet
        }
        
        tab.state.loadError = error
        tab.state.loadingState = .idle
        tab.state.showsStartupHomepage = false
        
        if let uri = error.uri,
           !uri.isEmpty {
            tab.url = uri
            tab.state.displayState = .committed
            tab.state.committedEngineURL = uri
            tab.state.displayedHistoryEntry = tab.state.matchingHistoryEntry
        }
        
        tabManager.notifyUpdate(for: tab, reason: .loadError)
        tabManager.notifyUpdate(for: tab, reason: .loading)
        return error.pageURI
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String, target: LoadRequestTarget) async -> GeckoSession? {
        return tabManager.addNewWindowTab(
            openedBy: currentTab(for: session),
            from: session,
            uri: uri,
            target: target
        )
    }
}

extension TabSessionHandler: HistoryDelegate {
    func onVisited(
        session: GeckoSession,
        url: String,
        lastVisitedURL: String?,
        flags: HistoryVisitFlags
    ) async -> Bool {
        guard !session.isPrivateMode,
              flags.contains(.topLevel),
              !flags.contains(.unrecoverableError),
              let pageURL = URLUtils.webURL(from: url) else {
            return false
        }
        
        let title = currentTab(for: session)?.title ?? ""
        let isRedirectSource = flags.contains(.redirectSource) || flags.contains(.redirectSourcePermanent)
        return await historyStore.recordVisitImmediately(
            url: pageURL,
            title: title,
            isRedirectSource: isRedirectSource
        )
    }
    
    func getVisited(session: GeckoSession, urls: [String]) async -> [Bool]? {
        guard !session.isPrivateMode else {
            return Array(repeating: false, count: urls.count)
        }
        
        return await historyStore.visitedStatuses(for: urls)
    }
}

extension TabSessionHandler: ProgressDelegate {
    func onSessionStateChange(session: GeckoSession, sessionState: GeckoSessionState) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        tab.state.tabSessionState = sessionState
        if let entry = tab.state.matchingHistoryEntry {
            tab.state.displayedHistoryEntry = entry
        }
        
        tabManager.notifyUpdate(for: tab, reason: .navigationState)
        tabManager.persistState()
    }
    
    func onPageStart(session: GeckoSession, url: String) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        if url == tab.state.loadError?.pageURI {
            return
        }
        
        let shouldPreservePlayback = tab.isMuted && tab.state.isPlayingAudio && tab.url == url
        systemMediaSession.navigationStarted(in: session, preservingPlayback: shouldPreservePlayback)
        
        let isBlankPage = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank")
        if isBlankPage,
           tab.displayedURL != nil {
            tab.state.isSuppressingInitialBlankPageLoad = true
            return
        }
        
        if tab.state.loadError != nil {
            tab.state.loadError = nil
            tabManager.notifyUpdate(for: tab, reason: .loadError)
        }
        
        sessionManager.trackingProtection.clearBlockedTrackers(for: session)
        
        if sessionManager.needsSettingsUpdate(
            to: session,
            currentURL: tab.url,
            requestedURL: url,
            tabID: tab.id
        ) {
            load(url)
        }
        
        tab.state.loadingState = .loading(progress: 0)
        tabManager.notifyUpdate(for: tab, reason: .loading)
    }
    
    func onPageStop(session: GeckoSession, success: Bool) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        if let error = session.currentLoadError,
           error != tab.state.loadError {
            _ = onLoadError(session: session, error: error)
        }
        
        if tab.state.isSuppressingInitialBlankPageLoad {
            tab.state.isSuppressingInitialBlankPageLoad = false
            return
        }
        
        tab.state.loadingState = .idle
        tabManager.notifyUpdate(for: tab, reason: .loading)
        tabManager.notifyUpdate(for: tab, reason: .thumbnail)
        tabManager.notifyFinishedLoading(session)
    }
    
    func onReloadCancelled(session: GeckoSession) {
        tabManager.notifyFinishedLoading(session)
    }
    
    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let tab = currentTab(for: session) else {
            return
        }
        
        tab.state.loadingState = .loading(progress: Float(progress) / 100)
        tabManager.notifyUpdate(for: tab, reason: .loading)
    }
}
