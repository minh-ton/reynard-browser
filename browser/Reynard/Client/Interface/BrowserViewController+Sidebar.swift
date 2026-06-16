//
//  BrowserViewController+Sidebar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: SidebarContentController, SidebarCoordinatorHost {
    // MARK: - SidebarContentController

    var sidebarContentViewController: UIViewController {
        self
    }

    var sidebarContentChrome: BrowserChrome {
        browserChrome
    }

    func openExternalURL(_ url: URL) {
        tabManager.openExternalURL(url)
    }

    // MARK: - SidebarCoordinatorHost

    var sidebarHostViewController: UIViewController {
        self
    }

    var sidebarInterfaceIdiom: UIUserInterfaceIdiom {
        browserLayout.interfaceIdiom
    }

    var sidebarChromeMode: browserChromeMode {
        browserLayout.chromeMode
    }

    var sidebarSplitViewController: UISplitViewController? {
        splitViewController
    }

    var sidebarFallbackTopInsetSourceView: UIView {
        view
    }

    func makeSidebarContentController() -> SidebarContentController {
        BrowserViewController(canHostSidebar: false)
    }

    func sidebarCoordinatorDidChangeVisibility(_ coordinator: SidebarCoordinator, animated: Bool) {
        updateBrowserLayout(animated: animated)
    }
}
