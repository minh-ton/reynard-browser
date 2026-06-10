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

extension BrowserViewController: TabBarDataSource, TabBarDelegate {
    var tabsForTabBar: [Tab] {
        tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
    }

    var selectedTabForTabBar: Tab? {
        tabManager.selectedTab
    }

    func tabBar(_ tabBar: TabBar, didSelectTabAt index: Int) {
        selectTab(at: index, animated: true)
    }

    func tabBar(_ tabBar: TabBar, didCloseTabAt index: Int) {
        closeTab(at: index)
    }

    func tabBar(_ tabBar: TabBar, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int) {
        tabManager.moveTab(
            from: sourceIndex,
            to: destinationIndex,
            mode: tabManager.selectedTabMode
        )
    }
}

extension BrowserViewController: TabManagerDelegate {
    func tabManagerDidChangeTabs(_ tabManager: TabManager) {
        if let selectedTab = tabManager.selectedTab {
            if !browserUI.contentView.isDisplaying(session: selectedTab.session) {
                browserUI.contentView.setSession(selectedTab.session)
            }
        } else {
            browserUI.contentView.setSession(nil)
        }
        refreshAddressBar()
        
        if !browserUI.tabOverview.isPresented {
            let overviewMode: TabOverview.Mode = tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
            browserUI.tabOverview.setMode(overviewMode, animated: false)
        }
        browserUI.tabOverview.applyPendingTabChanges()
        browserUI.tabBar.reloadTabs()
        browserUI.applyChromeLayout(animated: false)
        browserUI.tabBar.updateLayout()
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        browserUI.tabBar.setPendingExpansion(at: nil)
        if let previousIndex {
            captureThumbnail(for: previousIndex)
        }
        
        guard activeTabs.indices.contains(index) else {
            return
        }
        
        let selectedTab = activeTabs[index]
        browserUI.contentView.setSession(selectedTab.session)
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
        browserUI.tabBar.reloadTabs()
        
        if isInFullscreenMedia,
           activeFullscreenSession !== selectedTab.session {
            applyFullscreenState(false, for: activeFullscreenSession)
        }
        pendingSelectionAnimation = false
    }
    
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {
        guard browserUI.contentView.isDisplaying(session: session) else {
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
            browserUI.tabBar.reloadTab(at: index)
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
            browserUI.tabBar.reloadTab(at: index)
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
