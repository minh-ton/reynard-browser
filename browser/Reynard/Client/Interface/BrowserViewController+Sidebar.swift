//
//  BrowserViewController+Sidebar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: SidebarContentController, SidebarCoordinatorHost {
    var sidebarContentViewController: UIViewController {
        return self
    }
    
    var sidebarContentChrome: BrowserChrome {
        return browserChrome
    }
    
    var sidebarContentLayout: BrowserLayout {
        return browserLayout
    }
    
    var sidebarContentIsPrivate: Bool {
        return tabManager.selectedTabMode == .private
    }
    
    func openExternalURL(_ url: URL) {
        tabManager.openExternalURL(url)
    }
    
    func notifyScreenOrientationChanged(to interfaceOrientation: UIInterfaceOrientation) {
        tabManager.selectedTab?.session.notifyScreenOrientationChanged(to: interfaceOrientation)
    }
    
    func sidebarDidEndEditing() {
        guard tabManager.selectedTab?.session.engineView?.isFirstResponder != true else {
            return
        }
        
        requestContentKeyboardFocus()
    }
    
    var contentBrowserViewController: BrowserViewController {
        return sidebarCoordinator.contentBrowser?.sidebarContentViewController as? BrowserViewController ?? self
    }
    
    var sidebarHostViewController: UIViewController {
        return self
    }
    
    var sidebarInterfaceIdiom: UIUserInterfaceIdiom {
        return browserLayout.interfaceIdiom
    }
    
    var sidebarChromeMode: BrowserChromeMode {
        return browserLayout.chromeMode
    }
    
    var sidebarSplitViewController: UISplitViewController? {
        return splitViewController
    }
    
    var sidebarFallbackTopInsetSourceView: UIView {
        return view
    }
    
    func makeSidebarContentController() -> SidebarContentController {
        let browserViewController = BrowserViewController(canHostSidebar: false, startup: startup)
        browserViewController.sessionManager.setApplicationForeground(sessionManager.isForeground)
        return browserViewController
    }
    
    func sidebarCoordinatorDidChangeVisibility(_ coordinator: SidebarCoordinator, animated: Bool) {
        toolbarController.reset()
        updateBrowserLayout(animated: animated)
    }
}
