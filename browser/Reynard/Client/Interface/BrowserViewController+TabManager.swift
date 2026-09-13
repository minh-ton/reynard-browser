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
                contentView.setTab(
                    selectedTab,
                    pageBackgroundColor: sessionManager.pageBackgroundColor(for: selectedTab.session)
                )
            }
        } else {
            contentView.setTab(nil)
        }
        refreshAddressBar()
        
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
        contentView.showPageError(for: tab.url)
        captureThumbnail(
            forTabAt: tabManager.selectedTabIndex,
            mode: tabManager.selectedTabMode
        )
    }
    
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession) {
        contentView.didFinishLoading(session: session)
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        toolbarController.unlock(for: .pageNavigation)
        toolbarController.reset()
        tabBar.setPendingExpansion(at: nil)
        
        guard let selectedTab = tabManager.activeTabs[safe: index] else {
            return
        }
        
        if selectedTab.state.loadingState.isLoading {
            toolbarController.lock(for: .pageNavigation)
        }
        
        browserChrome.setAddressBarLoadingProgress(
            selectedTab.state.loadingState.progress,
            isLoading: selectedTab.state.loadingState.isLoading
        )
        refreshAddressBar()
        browserChrome.updatePageZoomLevel(selectedTab.session.settings.pageZoom.level)
        updateNavigationButtons()
        
        if !tabOverview.isPresented && !tabOverview.isTransitionRunning {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
            tabOverview.reloadTabs()
        }
        let animateTabBarVisibility = tabBar.visibility != targetTabBarVisibility
        tabBar.reloadTabs()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        updateBrowserLayout(animated: animateTabBarVisibility)
        
        contentView.setTab(
            selectedTab,
            pageBackgroundColor: sessionManager.pageBackgroundColor(for: selectedTab.session)
        )
        addonCoordinator.handleTabSelectionChange(selectedIndex: index, previousIndex: previousIndex)
        
        if isShowingFullscreenMedia,
           fullscreenSession !== selectedTab.session {
            applyFullscreenState(false, for: fullscreenSession, mediaIsPlaying: false)
        }
    }
    
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession) {
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
    
    func tabManager(_ tabManager: TabManager, didRequestContentKeyboardFocusFor session: GeckoSession) {
        requestContentKeyboardFocus(for: session)
    }
    
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailForTabAt index: Int, mode: TabMode, url: String) {
        captureHistoryThumbnail(forTabAt: index, mode: mode, url: url)
    }
    
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {
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
    
    func tabManager(_ tabManager: TabManager, didChangeFullscreen fullScreen: Bool, mediaIsPlaying: Bool, for session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        applyFullscreenState(fullScreen, for: session, mediaIsPlaying: mediaIsPlaying)
    }
    
    func tabManager(_ tabManager: TabManager, didChangeMediaPlayback isPlaying: Bool, for session: GeckoSession) {
        guard isShowingFullscreenMedia,
              fullscreenSession === session else {
            return
        }
        UIApplication.shared.isIdleTimerDisabled = isPlaying
    }
    
    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        guard tabManager.activeTabs.indices.contains(index) else {
            return
        }
        
        switch reason {
        case .title:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
            }
            tabBar.reloadTab(at: index)
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .location:
            if index == tabManager.selectedTabIndex {
                contentView.resetScrollTracking()
                toolbarController.reset(preserveManualCollapse: true)
                let tab = tabManager.activeTabs[index]
                contentView.noteHistoryLocationChange()
                refreshAddressBar()
                browserChrome.updatePageZoomLevel(tab.session.settings.pageZoom.level)
                updateNavigationButtons()
                homepageOverlayCoordinator.updatePresentation(animated: true)
            }
            
        case .favicon:
            tabBar.reloadTab(at: index)
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .navigationState:
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
            }
            
        case .loading:
            if index == tabManager.selectedTabIndex {
                let tab = tabManager.activeTabs[index]
                browserChrome.setAddressBarLoadingProgress(
                    tab.state.loadingState.progress,
                    isLoading: tab.state.loadingState.isLoading
                )
                
                if tab.state.loadingState.isLoading {
                    contentView.resetScrollTracking()
                    toolbarController.lock(for: .pageNavigation)
                } else {
                    toolbarController.unlock(for: .pageNavigation)
                }
                
                if !tab.state.loadingState.isLoading {
                    contentView.finishHistoryLoad()
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              index == self.tabManager.selectedTabIndex else {
                            return
                        }
                        
                        self.captureThumbnail(forTabAt: index, mode: self.tabManager.selectedTabMode)
                    }
                }
            }
            
        case .thumbnail:
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .pageBackgroundColor:
            guard index == tabManager.selectedTabIndex else {
                return
            }
            let tab = tabManager.activeTabs[index]
            contentView.setPageBackgroundColor(sessionManager.pageBackgroundColor(for: tab.session))
        }
    }
    
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        guard tabManager.activeTabs.indices.contains(index) else {
            completion()
            return
        }
        
        let selectedIndex = tabManager.selectedTabIndex
        let selectedMode = tabManager.selectedTabMode
        captureThumbnail(forTabAt: selectedIndex, mode: selectedMode) { [weak self] _ in
            guard let self,
                  tabManager.activeTabs.indices.contains(index) else {
                completion()
                return
            }
            
            self.tabBar.setPendingExpansion(at: index)
            self.browserChrome.animateAutomaticNewTabTransition(to: tabManager.activeTabs[index], completion: completion)
        }
    }
    
    func tabManager(_ tabManager: TabManager, didRequestDownload download: DownloadStore.PendingDownload) {
        DispatchQueue.main.async { [weak self] in
            self?.downloadsCoordinator.enqueueConfirmation(download)
        }
    }
    
    func tabManager(_ tabManager: TabManager, shouldStartExternalResponse response: ExternalResponseInfo, for session: GeckoSession) async -> Bool {
        if addonCoordinator.handleExternalResponse(response) {
            return true
        }
        guard let download = DownloadStore.shared.pendingDownload(from: response, session: session) else {
            return false
        }
        return await downloadsCoordinator.confirm(download)
    }
    
    func tabManager(_ tabManager: TabManager, shouldContinueExternalResponseAt localFilePath: String, bytesReceived: Int64) -> Bool {
        if addonCoordinator.shouldContinueExternalResponse(localFilePath: localFilePath) {
            return true
        }
        return DownloadStore.shared.updateCapturedDownload(
            localFilePath: localFilePath,
            bytesReceived: bytesReceived
        )
    }
    
    func tabManager(_ tabManager: TabManager, didCompleteExternalResponseAt localFilePath: String, succeeded: Bool) {
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
    
    func reloadTerminatedTab() {
        guard tabManager.selectedTab?.session.isOpen() == false else {
            return
        }
        
        let index = tabManager.selectedTabIndex
        let mode = tabManager.selectedTabMode
        tabManager.selectTab(at: index, mode: mode)
    }
}

extension BrowserViewController {
    func applyNewTabDisplayOption(toTabAt index: Int) {
        switch Prefs.NewTabSettings.newTabDisplayOption {
        case .homepage, .blankPage:
            captureThumbnail(forTabAt: index, mode: tabManager.selectedTabMode)
        case .customURL:
            guard let tab = tabManager.activeTabs[safe: index],
                  URLUtils.isWebURL(Prefs.NewTabSettings.customNewTabURL) else {
                return
            }
            
            tabManager.browse(to: Prefs.NewTabSettings.customNewTabURL, in: tab)
        }
    }
    
    func captureThumbnail(forTabAt index: Int, mode: TabMode, completion: ((UIImage?) -> Void)? = nil) {
        let targetTabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard let targetTab = targetTabs[safe: index] else {
            completion?(nil)
            return
        }
        
        let targetTabID = targetTab.id
        if homepageOverlayCoordinator.needsHomepageThumbnail(for: targetTab) {
            homepageOverlayCoordinator.captureHomepageThumbnail(targetTab) { [weak self] thumbnail in
                guard let self,
                      let thumbnail,
                      (mode == .private ? self.tabManager.privateTabs : self.tabManager.regularTabs)[safe: index]?.id == targetTabID else {
                    completion?(nil)
                    return
                }
                
                self.tabManager.updateThumbnail(thumbnail, forTabAt: index, mode: mode)
                completion?(thumbnail)
            }
            return
        }
        
        guard mode == tabManager.selectedTabMode,
              index == tabManager.selectedTabIndex,
              let tab = tabManager.activeTabs[safe: index],
              tab.id == targetTabID,
              !contentView.isHidden,
              contentView.isDisplaying(session: tab.session) else {
            completion?(nil)
            return
        }
        
        guard let thumbnail = contentView.makeWebThumbnail() else {
            completion?(nil)
            return
        }
        
        tabManager.updateThumbnail(thumbnail, forTabAt: index, mode: mode)
        completion?(thumbnail)
    }
    
    func captureOutgoingHistoryThumbnail() {
        guard let url = tabManager.selectedTab?.url else {
            return
        }
        
        captureHistoryThumbnail(
            forTabAt: tabManager.selectedTabIndex,
            mode: tabManager.selectedTabMode,
            url: url
        )
    }
    
    func prepareThumbnailForNavigation() {
        guard let url = tabManager.selectedTab?.url else {
            return
        }
        
        captureHistoryThumbnail(
            forTabAt: tabManager.selectedTabIndex,
            mode: tabManager.selectedTabMode,
            url: url,
            isPreparedForNavigation: true
        )
    }
    
    private func captureHistoryThumbnail(
        forTabAt index: Int,
        mode: TabMode,
        url: String,
        isPreparedForNavigation: Bool = false
    ) {
        guard mode == tabManager.selectedTabMode,
              index == tabManager.selectedTabIndex,
              let tab = tabManager.activeTabs[safe: index],
              tab.url == url,
              !contentView.isHidden,
              contentView.isDisplaying(session: tab.session) else {
            return
        }
        
        guard let thumbnail = contentView.makeWebThumbnail() else {
            return
        }
        
        tabManager.updateThumbnail(thumbnail, forTabAt: index, mode: mode)
        tabManager.updateHistoryThumbnail(
            thumbnail,
            for: tab,
            url: url,
            isPreparedForNavigation: isPreparedForNavigation
        )
    }
}
