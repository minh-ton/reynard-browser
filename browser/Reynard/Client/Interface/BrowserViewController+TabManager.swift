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
        captureThumbnail(
            forTabAt: tabManager.selectedTabIndex,
            mode: tabManager.selectedTabMode
        )
    }
    
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession) {
        contentView.didFinishLoading(session: session)
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        browserChrome.addressBar.clearKeyCommandHint()
        toolbarController.unlock(for: .pageNavigation)
        toolbarController.reset()
        tabBar.setPendingExpansion(at: nil)
        
        guard let selectedTab = tabManager.activeTabs[safe: index] else {
            return
        }
        
        if selectedTab.state.loadingState.isLoading {
            toolbarController.lock(for: .pageNavigation)
        }
        
        browserChrome.addressBar.setLoadingProgress(
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
    
    func tabManager(_ tabManager: TabManager, didRequestContentKeyboardFocusFor session: GeckoSession) {
        requestContentKeyboardFocus(for: session)
    }
    
    func tabManager(_ tabManager: TabManager, didRequestFindInPage query: String, in session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        
        browserChrome.showActionBar(.findInPage(query: query), animated: true)
    }
    
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailForTabAt index: Int, mode: TabMode, url: String) {
        guard index == tabManager.selectedTabIndex,
              mode == tabManager.selectedTabMode,
              tabManager.selectedTab?.url == url else {
            return
        }
        
        captureHistoryThumbnail()
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
    
    func tabManager(_ tabManager: TabManager, didChangeFullscreen fullScreen: Bool, for session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        applyFullscreenState(fullScreen, for: session)
    }
    
    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        guard let tab = tabManager.activeTabs[safe: index] else {
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
                contentView.keyCommandDelegate = self
                browserChrome.addressBar.clearKeyCommandHint()
                contentView.resetScrollTracking()
                toolbarController.reset(preserveManualCollapse: true)
                contentView.noteHistoryLocationChange()
                refreshAddressBar()
                browserChrome.updatePageZoomLevel(tab.session.settings.pageZoom.level)
                updateNavigationButtons()
                homepageOverlayCoordinator.updatePresentation(animated: true)
                requestHomepageAddressBarFocus()
            }
            
        case .favicon:
            tabBar.reloadTab(at: index)
            tabOverview.isPresented
            ? tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            : tabOverview.reloadTabs()
            
        case .navigationState:
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
                contentView.updateLoadError(for: tab)
            }
            
        case .loadError:
            if index == tabManager.selectedTabIndex {
                contentView.updateLoadError(for: tab)
                refreshAddressBar()
                homepageOverlayCoordinator.updatePresentation(animated: false)
                toolbarController.reset()
            }
            
        case .loading:
            if index == tabManager.selectedTabIndex {
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
            contentView.setPageBackgroundColor(sessionManager.pageBackgroundColor(for: tab.session))
            
        case .readerMode:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
            }
            
        case .audio:
            refreshAddressBarAudioButton()
        }
    }
    
    func tabManager(_ tabManager: TabManager, animateReturnTo tab: Tab, completion: @escaping () -> Void) {
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab, returning: true, completion: completion)
    }
    
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        guard tabManager.activeTabs.indices.contains(index) else {
            completion()
            return
        }
        
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
        tabBar.setPendingExpansion(at: index)
        browserChrome.addressBar.animateAutomaticTabTransition(to: tabManager.activeTabs[index], completion: completion)
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
    // Returns the new tab's thumbnail when it shows the homepage or a blank page.
    @discardableResult
    func applyNewTabDisplayOption(toTabAt index: Int, mode: TabMode) -> UIImage? {
        switch Prefs.NewTabSettings.newTabDisplayOption {
        case .homepage, .blankPage:
            return captureThumbnail(forTabAt: index, mode: mode)
        case .customURL:
            guard let tab = tabManager.tabs(for: mode)[safe: index],
                  URLUtils.normalizedNewTabURL(from: Prefs.NewTabSettings.customNewTabURL) != nil else {
                return nil
            }
            
            tabManager.browse(to: Prefs.NewTabSettings.customNewTabURL, in: tab)
            return nil
        }
    }
}
