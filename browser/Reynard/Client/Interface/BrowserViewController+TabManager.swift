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
        updateNavigationButtons()
        
        contentView.setSession(selectedTab.session)
        addonCoordinator.handleTabSelectionChange(selectedIndex: index, previousIndex: previousIndex)
        
        if !tabOverview.isPresented {
            tabOverview.setMode(TabOverview.Mode(tabMode: tabManager.selectedTabMode), animated: false)
            tabOverview.reloadTabs()
        }
        tabBar.reloadTabs()
        
        if isShowingFullscreenMedia,
           fullscreenSession !== selectedTab.session {
            applyFullscreenState(false, for: fullscreenSession)
        }
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
                refreshAddressBar()
                updateNavigationButtons()
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
            }
            
        case .thumbnail:
            if index == tabManager.selectedTabIndex {
                captureThumbnailForVisibleTab(at: index)
            }
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
        
        tabBar.setPendingExpansion(at: index)
        browserChrome.animateAutomaticNewTabTransition(to: tabManager.activeTabs[index], completion: completion)
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
    func captureThumbnailForVisibleTab(at index: Int) {
        guard !contentView.isHidden,
              let tab = tabManager.activeTabs[safe: index],
              contentView.isDisplaying(session: tab.session),
              let image = contentView.makeThumbnail() else {
            return
        }
        
        tabManager.updateThumbnail(image, forTabAt: index)
    }
}
