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
                contentView.setSession(selectedTab.session)
            }
        } else {
            contentView.setSession(nil)
        }
        refreshAddressBar()
        
        if !tabOverview.isPresented {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
        }
        tabOverview.applyPendingTabChanges()
        tabBar.reloadTabs()
        updateBrowserLayout(animated: false)
        homepageOverlayCoordinator.updatePresentation(animated: false)
        tabBar.updateLayout()
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        tabBar.setPendingExpansion(at: nil)
        
        guard let selectedTab = tabManager.activeTabs[safe: index] else {
            return
        }
        
        browserChrome.setAddressBarLoadingProgress(
            selectedTab.state.loadingState.progress,
            isLoading: selectedTab.state.loadingState.isLoading
        )
        refreshAddressBar()
        browserChrome.updatePageZoomLevel(selectedTab.session.settings.pageZoom.level)
        updateNavigationButtons()
        
        contentView.setSession(selectedTab.session)
        addonCoordinator.handleTabSelectionChange(selectedIndex: index, previousIndex: previousIndex)
        
        if !tabOverview.isPresented && !tabOverview.isTransitionRunning {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
            tabOverview.reloadTabs()
        }
        tabBar.reloadTabs()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        updateBrowserLayout(animated: false)
        
        if isShowingFullscreenMedia,
           fullscreenSession !== selectedTab.session {
            applyFullscreenState(false, for: fullscreenSession)
        }
    }
    
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession) {
        addonCoordinator.handleSelectedTabSessionReplacement(from: previousSession, to: replacementSession)
    }
    
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {
        guard contentView.isDisplaying(session: session) else {
            return
        }
        
        if element.type == .image,
           let source = element.srcUri?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: source) {
            contextMenuCoordinator.present(at: point, target: .image(url))
            return
        }
        
        guard let link = element.linkUri?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: link) else {
            return
        }
        
        contextMenuCoordinator.present(at: point, target: .link(url))
    }
    
    func tabManager(_ tabManager: TabManager, didChangeFullscreen fullScreen: Bool, for session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        applyFullscreenState(fullScreen, for: session)
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
                let tab = tabManager.activeTabs[index]
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
                
                if !tab.state.loadingState.isLoading {
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
    
    func tabManager(_ tabManager: TabManager, shouldHandleExternalResponse response: ExternalResponseInfo, for session: GeckoSession) -> Bool {
        return addonCoordinator.handleExternalResponse(response)
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
            homepageOverlayCoordinator.captureHomepageThumbnail(targetTab, size: contentView.bounds.size) { [weak self] thumbnail in
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
        
        guard let thumbnail = contentView.makeThumbnail() else {
            completion?(nil)
            return
        }
        
        tabManager.updateThumbnail(thumbnail, forTabAt: index, mode: mode)
        completion?(thumbnail)
    }
}
