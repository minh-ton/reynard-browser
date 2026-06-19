//
//  BrowserViewController+Sidebar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

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
    
    func openExternalURL(_ url: URL) {
        tabManager.openExternalURL(url)
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
        return BrowserViewController(canHostSidebar: false)
    }
    
    func sidebarCoordinatorDidChangeVisibility(_ coordinator: SidebarCoordinator, animated: Bool) {
        updateBrowserLayout(animated: animated)
    }
}
