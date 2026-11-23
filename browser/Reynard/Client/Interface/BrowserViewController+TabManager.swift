//
//  BrowserViewController+TabManager.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import GeckoView
import UIKit

extension BrowserViewController: TabManagerDelegate {
    func tabManagerDidChangeTabs(_ tabManager: TabManager) {
        if let selectedTab = tabManager.selectedTab {
            if !contentView.isDisplaying(session: selectedTab.session) {
                browserChrome.addressBar.clearKeyCommandHint()
                contentView.setTab(
                    selectedTab,
                    pageBackgroundColor: sessionManager.pageBackgroundColor(for: selectedTab.session)
                )
            }
        } else {
            browserChrome.addressBar.clearKeyCommandHint()
            contentView.setTab(nil)
        }
        
        refreshAddressBar()
        updateNavigationButtons()
        updatePageActionButtons()
        
        if !tabOverview.isPresented {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
        }
        
        tabOverview.applyPendingTabChanges()
        let animateTabBarVisibility = tabBar.visibility != targetTabBarVisibility
        tabBar.reloadTabs()
        updateBrowserLayout(animated: animateTabBarVisibility)
        homepageOverlayCoordinator.updatePresentation(animated: false)
        tabBar.updateLayout()
    }
    
    func tabManagerDidTerminateSelectedTab(_ tabManager: TabManager) {
        guard let tab = tabManager.selectedTab else {
            return
        }
        
        toolbarController.reset()
        contentView.updateLoadError(for: tab)
        captureThumbnail(for: tab)
    }
    
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession) {
        contentView.didFinishLoading(session: session)
    }
    
    func tabManager(_ tabManager: TabManager, didSelect tab: Tab, previous previousTab: Tab?) {
        browserChrome.addressBar.clearKeyCommandHint()
        toolbarController.unlock(for: .pageNavigation)
        toolbarController.reset()
        tabBar.setPendingExpansion(to: nil)
        
        if tab.state.loadingState.isLoading {
            toolbarController.lock(for: .pageNavigation)
        }
        
        browserChrome.addressBar.setLoadingProgress(
            tab.state.loadingState.progress,
            isLoading: tab.state.loadingState.isLoading
        )
        refreshAddressBar()
        browserChrome.updatePageZoomLevel(tab.session.settings.pageZoom.level)
        updateNavigationButtons()
        updatePageActionButtons()
        
        if !tabOverview.isPresented && !tabOverview.isTransitionRunning {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
            tabOverview.reloadTabs()
        }
        
        let animateTabBarVisibility = tabBar.visibility != targetTabBarVisibility
        tabBar.reloadTabs()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        updateBrowserLayout(animated: animateTabBarVisibility)
        
        contentView.setTab(
            tab,
            pageBackgroundColor: sessionManager.pageBackgroundColor(for: tab.session)
        )
        addonCoordinator.handleTabSelectionChange(from: previousTab, to: tab)
        
        if isShowingFullscreenMedia,
           fullscreenSession !== tab.session {
            applyFullscreenState(false, for: fullscreenSession)
        }
        
        requestHomepageAddressBarFocus()
    }
    
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession) {
        browserChrome.addressBar.clearKeyCommandHint()
        if contentView.isDisplaying(session: previousSession) {
            contentView.setTab(
                tabManager.selectedTab,
                pageBackgroundColor: tabManager.selectedTab.map {
                    sessionManager.pageBackgroundColor(for: $0.session)
                }
            )
        }
        
        addonCoordinator.handleSelectedTabSessionReplacement(from: previousSession, to: replacementSession)
    }
    
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailFor tab: Tab, url: String) {
        guard tab === tabManager.selectedTab,
              tab.url == url else {
            return
        }
        
        captureHistoryThumbnail()
    }
    
    func tabManager(_ tabManager: TabManager, didUpdate tab: Tab, reason: TabManagerUpdateReason) {
        guard let index = tabManager.activeTabs.firstIndex(where: { $0 === tab }) else {
            return
        }
        
        let isSelectedTab = tab === tabManager.selectedTab
        
        switch reason {
        case .title:
            if isSelectedTab {
                refreshAddressBar()
            }
            
            tabBar.reloadTab(at: index)
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .location:
            if isSelectedTab {
                contentView.keyCommandDelegate = self
                browserChrome.addressBar.clearKeyCommandHint()
                contentView.resetScrollTracking()
                toolbarController.reset(preserveManualCollapse: true)
                contentView.noteHistoryLocationChange(isLoading: tab.state.loadingState.isLoading)
                refreshAddressBar()
                browserChrome.updatePageZoomLevel(tab.session.settings.pageZoom.level)
                updateNavigationButtons()
                updatePageActionButtons()
                homepageOverlayCoordinator.updatePresentation(animated: true)
                requestHomepageAddressBarFocus()
            }
            
        case .favicon:
            tabBar.reloadTab(at: index)
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .navigationState:
            if isSelectedTab {
                updateNavigationButtons()
                contentView.updateLoadError(for: tab)
            }
            
        case .loadError:
            if isSelectedTab {
                contentView.updateLoadError(for: tab)
                refreshAddressBar()
                homepageOverlayCoordinator.updatePresentation(animated: false)
                toolbarController.reset()
            }
            
        case .loading:
            if isSelectedTab {
                browserChrome.addressBar.setLoadingProgress(
                    tab.state.loadingState.progress,
                    isLoading: tab.state.loadingState.isLoading
                )
                
                if tab.state.loadingState.isLoading {
                    contentView.updateLoadError(for: tab)
                    contentView.resetScrollTracking()
                    toolbarController.lock(for: .pageNavigation)
                } else {
                    toolbarController.unlock(for: .pageNavigation)
                }
                
                if !tab.state.loadingState.isLoading {
                    contentView.finishHistoryLoad()
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              tab === self.tabManager.selectedTab else {
                            return
                        }
                        
                        self.captureThumbnail(for: tab)
                    }
                }
            }
            
        case .thumbnail:
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .pageBackgroundColor:
            guard isSelectedTab else {
                return
            }
            
            contentView.setPageBackgroundColor(sessionManager.pageBackgroundColor(for: tab.session))
            
        case .firstContentfulPaint:
            if isSelectedTab {
                contentView.finishHistoryLoad()
            }
            
        case .readerMode:
            if isSelectedTab {
                refreshAddressBar()
                updatePageActionButtons()
            }
            
        case .audio:
            refreshAddressBarAudioButton()
        }
    }
    
    func tabManager(_ tabManager: TabManager, animateReturnTo tab: Tab, completion: @escaping () -> Void) {
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab, returning: true, completion: completion)
    }
    
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionTo tab: Tab, completion: @escaping () -> Void) {
        guard tabManager.activeTabs.contains(where: { $0 === tab }) else {
            completion()
            return
        }
        
        captureThumbnail(for: tabManager.selectedTab)
        tabBar.setPendingExpansion(to: tab)
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab, completion: completion)
    }
    
    func reloadTerminatedTab() {
        guard let tab = tabManager.selectedTab,
              !tab.session.isOpen() else {
            return
        }
        
        tabManager.selectTab(tab)
    }
}

extension BrowserViewController: TabSessionHandlerDelegate {
    func tabSessionHandler(_ handler: TabSessionHandler, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {
        guard contentView.isDisplaying(session: session) else {
            return
        }
        
        if element.type == .image,
           let source = element.srcUri?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: source) {
            let linkURL = element.linkUri
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { URL(string: $0) }
            contextMenuCoordinator.present(
                at: point,
                target: .image(url, linkURL: linkURL),
                allowsPreview: !element.isMouseInput
            )
            return
        }
        
        guard let link = element.linkUri?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: link) else {
            return
        }
        
        contextMenuCoordinator.present(at: point, target: .link(url), allowsPreview: !element.isMouseInput)
    }
    
    func tabSessionHandler(_ handler: TabSessionHandler, didChangeFullscreen fullScreen: Bool, for session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        
        applyFullscreenState(fullScreen, for: session)
    }
    
    func tabSessionHandler(_ handler: TabSessionHandler, didRequestDownload download: DownloadStore.PendingDownload) {
        DispatchQueue.main.async { [weak self] in
            self?.downloadsCoordinator.enqueueConfirmation(download)
        }
    }
    
    func tabSessionHandler(_ handler: TabSessionHandler, shouldStartExternalResponse response: ExternalResponseInfo, for session: GeckoSession) async -> Bool {
        if addonCoordinator.handleExternalResponse(response) {
            return true
        }
        
        guard let download = DownloadStore.shared.pendingDownload(from: response, session: session) else {
            return false
        }
        
        return await downloadsCoordinator.confirm(download)
    }
    
    func tabSessionHandler(_ handler: TabSessionHandler, shouldContinueExternalResponseAt localFilePath: String, bytesReceived: Int64) -> Bool {
        if addonCoordinator.shouldContinueExternalResponse(localFilePath: localFilePath) {
            return true
        }
        
        return DownloadStore.shared.updateCapturedDownload(
            localFilePath: localFilePath,
            bytesReceived: bytesReceived
        )
    }
    
    func tabSessionHandler(_ handler: TabSessionHandler, didCompleteExternalResponseAt localFilePath: String, succeeded: Bool) {
        if addonCoordinator.completeExternalResponse(
            localFilePath: localFilePath,
            succeeded: succeeded
        ) {
            return
        }
        
        DownloadStore.shared.completeCapturedDownload(
            localFilePath: localFilePath,
            succeeded: succeeded
        )
    }
}
