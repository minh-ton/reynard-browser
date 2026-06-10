//
//  BrowserViewController+TabMgmt.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import GeckoView
import ObjectiveC
import UIKit

private enum TabMgmtAssociatedKeys {
    static var pendingSelectionAnimation = 0
    static var pendingExpandedTabBarIndex = 0
    static var activeFullscreenSession = 0
}

private final class WeakSessionBox {
    weak var value: GeckoSession?
    
    init(_ value: GeckoSession?) {
        self.value = value
    }
}

extension BrowserViewController {
    var pendingSelectionAnimation: Bool {
        get {
            (objc_getAssociatedObject(self, &TabMgmtAssociatedKeys.pendingSelectionAnimation) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &TabMgmtAssociatedKeys.pendingSelectionAnimation,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    var pendingExpandedTabBarIndex: Int? {
        get {
            (objc_getAssociatedObject(self, &TabMgmtAssociatedKeys.pendingExpandedTabBarIndex) as? NSNumber)?.intValue
        }
        set {
            let boxedValue = newValue.map { NSNumber(value: $0) }
            objc_setAssociatedObject(
                self,
                &TabMgmtAssociatedKeys.pendingExpandedTabBarIndex,
                boxedValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    var activeFullscreenSession: GeckoSession? {
        get {
            (objc_getAssociatedObject(self, &TabMgmtAssociatedKeys.activeFullscreenSession) as? WeakSessionBox)?.value
        }
        set {
            objc_setAssociatedObject(
                self,
                &TabMgmtAssociatedKeys.activeFullscreenSession,
                WeakSessionBox(newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
}

extension BrowserViewController: TabManagerDelegate {
    func tabManagerDidChangeTabs(_ tabManager: TabManager) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        if let pendingExpandedTabBarIndex,
           !activeTabs.indices.contains(pendingExpandedTabBarIndex) {
            self.pendingExpandedTabBarIndex = nil
        }
        
        if let selectedTab = tabManager.selectedTab {
            if browserUI.geckoView.session !== selectedTab.session {
                browserUI.geckoView.session = selectedTab.session
            }
        } else {
            browserUI.geckoView.session = nil
        }
        refreshAddressBar()
        
        if !browserUI.tabOverview.isPresented {
            let overviewMode: TabOverview.Mode = tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
            browserUI.tabOverview.setMode(overviewMode, animated: false)
        }
        browserUI.tabOverview.applyPendingTabChanges()
        browserUI.tabBar.collectionView.reloadData()
        browserUI.applyChromeLayout(animated: false)
        browserUI.tabBar.refreshLayout(
            fallbackWidth: view.bounds.width,
            tabCount: activeTabs.count,
            selectedIndex: tabManager.selectedTabIndex,
            pendingExpandedIndex: pendingExpandedTabBarIndex
        )
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        pendingExpandedTabBarIndex = nil
        if let previousIndex {
            captureThumbnail(for: previousIndex)
        }
        
        guard activeTabs.indices.contains(index) else {
            return
        }
        
        let selectedTab = activeTabs[index]
        browserUI.geckoView.session = selectedTab.session
        addonController.handleTabSelectionChange(selectedIndex: index, previousIndex: previousIndex)
        
        syncAddressBarLoadingState(progress: selectedTab.progress, isLoading: selectedTab.isLoading)
        refreshAddressBar()
        
        updateNavigationButtons()
        if !browserUI.tabOverview.isPresented {
            let overviewMode: TabOverview.Mode = tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
            browserUI.tabOverview.setMode(overviewMode, animated: false)
        }
        if !browserUI.tabOverview.isPresented {
            browserUI.tabOverview.reloadTabs()
        }
        browserUI.tabBar.collectionView.reloadData()
        browserUI.tabBar.refreshLayout(
            fallbackWidth: view.bounds.width,
            tabCount: activeTabs.count,
            selectedIndex: tabManager.selectedTabIndex,
            pendingExpandedIndex: pendingExpandedTabBarIndex
        )
        
        if isInFullscreenMedia,
           activeFullscreenSession !== selectedTab.session {
            applyFullscreenState(false, for: activeFullscreenSession)
        }
        pendingSelectionAnimation = false
    }
    
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {
        guard browserUI.geckoView.session === session else {
            return
        }
        
        if element.type == .image,
           let source = element.srcUri?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: source) {
            presentContextMenu(at: point, target: .image(url))
            return
        }
        
        guard let link = element.linkUri?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: link) else {
            return
        }
        
        presentContextMenu(at: point, target: .link(url))
    }
    
    func tabManager(_ tabManager: TabManager, didChangeFullscreen fullScreen: Bool, for session: GeckoSession) {
        guard tabManager.selectedTab?.session === session else {
            return
        }
        applyFullscreenState(fullScreen, for: session)
    }
    
    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard activeTabs.indices.contains(index) else {
            return
        }
        
        switch reason {
        case .title:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
            }
            browserUI.tabBar.collectionView.reloadData()
            if browserUI.tabOverview.isPresented {
                browserUI.tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            } else {
                browserUI.tabOverview.reloadTabs()
            }
            
        case .location:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
                updateNavigationButtons()
            }
            
        case .favicon:
            browserUI.tabBar.collectionView.reloadData()
            if browserUI.tabOverview.isPresented {
                browserUI.tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            } else {
                browserUI.tabOverview.reloadTabs()
            }
            
        case .navigationState:
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
            }
            
        case .loading:
            if index == tabManager.selectedTabIndex {
                let tab = activeTabs[index]
                syncAddressBarLoadingState(progress: tab.progress, isLoading: tab.isLoading)
            }
            
        case .thumbnail:
            if index == tabManager.selectedTabIndex {
                captureThumbnail(for: index)
            }
            if browserUI.tabOverview.isPresented {
                browserUI.tabOverview.refreshTab(at: index, mode: tabManager.selectedTabMode)
            } else {
                browserUI.tabOverview.reloadTabs()
            }
        }
    }
    
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard activeTabs.indices.contains(index) else {
            completion()
            return
        }
        
        browserUI.browserChrome.animateAutomaticNewTabTransition(to: activeTabs[index], completion: completion)
    }
    
    func tabManager(_ tabManager: TabManager, didRequestDownload download: DownloadStore.PendingDownload) {
        DispatchQueue.main.async { [weak self] in
            self?.enqueueDownloadConfirmation(download)
        }
    }
    
    func tabManager(_ tabManager: TabManager, shouldHandleExternalResponse response: ExternalResponseInfo, for session: GeckoSession) -> Bool {
        addonController.handleExternalResponse(response)
    }
}
