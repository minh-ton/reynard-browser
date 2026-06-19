//
//  SidebarCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

protocol SidebarContentController: AnyObject {
    var sidebarContentViewController: UIViewController { get }
    var sidebarContentChrome: BrowserChrome { get }
    var sidebarContentLayout: BrowserLayout { get }
    
    func updateBrowserLayout(animated: Bool, duration: TimeInterval)
    func openExternalURL(_ url: URL)
}

protocol SidebarCoordinatorHost: AnyObject {
    var sidebarHostViewController: UIViewController { get }
    var sidebarInterfaceIdiom: UIUserInterfaceIdiom { get }
    var sidebarChromeMode: BrowserChromeMode { get }
    var sidebarSplitViewController: UISplitViewController? { get }
    var sidebarFallbackTopInsetSourceView: UIView { get }
    
    func makeSidebarContentController() -> SidebarContentController
    func sidebarCoordinatorDidChangeVisibility(_ coordinator: SidebarCoordinator, animated: Bool)
}

final class SidebarCoordinator {
    private weak var host: SidebarCoordinatorHost?
    private let canHostSidebar: Bool
    private var sidebar: SidebarViewController?
    private var preFullscreenVisibility: Bool?
    
    var statusBarController: UIViewController? {
        return hostsSidebar ? sidebar : nil
    }
    
    var contentBrowser: SidebarContentController? {
        return sidebar?.contentBrowser ?? host as? SidebarContentController
    }
    
    var showChromeSidebarButton: Bool {
        return (host?.sidebarSplitViewController as? SidebarViewController)?.showChromeSidebarButton ?? true
    }
    
    var hostsSidebar: Bool {
        return canHostSidebar && host?.sidebarInterfaceIdiom == .pad
    }
    
    // MARK: - Lifecycle
    
    init(host: SidebarCoordinatorHost, canHostSidebar: Bool) {
        self.host = host
        self.canHostSidebar = canHostSidebar
    }
    
    // MARK: - Installation
    
    @discardableResult
    func installHostIfNeeded() -> Bool {
        guard hostsSidebar else {
            return false
        }
        
        guard sidebar == nil else {
            return true
        }
        
        guard let host else {
            return false
        }
        
        let contentBrowser = host.makeSidebarContentController()
        let sidebar = SidebarViewController(contentController: contentBrowser)
        host.sidebarHostViewController.addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        host.sidebarHostViewController.view.addSubview(sidebar.view)
        NSLayoutConstraint.activate([
            sidebar.view.topAnchor.constraint(equalTo: host.sidebarHostViewController.view.topAnchor),
            sidebar.view.leadingAnchor.constraint(equalTo: host.sidebarHostViewController.view.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: host.sidebarHostViewController.view.trailingAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: host.sidebarHostViewController.view.bottomAnchor),
        ])
        sidebar.didMove(toParent: host.sidebarHostViewController)
        self.sidebar = sidebar
        return true
    }
    
    // MARK: - Visibility
    
    func toggle(animated: Bool) {
        guard host?.sidebarInterfaceIdiom == .pad else {
            return
        }
        
        (host?.sidebarSplitViewController as? SidebarViewController)?.toggleVisibility()
        host?.sidebarCoordinatorDidChangeVisibility(self, animated: animated)
    }
    
    func refreshVisibility() {
        sidebar?.refreshVisibility()
    }
    
    func setFullscreen(_ fullscreen: Bool) {
        guard let splitViewController = host?.sidebarSplitViewController as? SidebarViewController else {
            return
        }
        
        if fullscreen {
            preFullscreenVisibility = splitViewController.isSidebarVisible
            splitViewController.setVisible(false)
        } else if let preFullscreenVisibility {
            splitViewController.setVisible(preFullscreenVisibility)
            self.preFullscreenVisibility = nil
        }
    }
    
    @discardableResult
    func refreshHostVisibility() -> Bool {
        guard hostsSidebar else {
            return false
        }
        
        refreshVisibility()
        return true
    }
    
    // MARK: - Sections
    
    func showSection(_ section: LibrarySection) {
        (host?.sidebarSplitViewController as? SidebarViewController)?.showSection(section)
    }
    
    func topInset(fallback: CGFloat) -> CGFloat {
        guard let host else {
            return fallback
        }
        
        guard host.sidebarInterfaceIdiom == .pad,
              host.sidebarSplitViewController is SidebarViewController else {
            return host.sidebarFallbackTopInsetSourceView.safeAreaInsets.top
        }
        
        if let statusBarHeight = host.sidebarHostViewController.view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
           statusBarHeight > 0 {
            return statusBarHeight
        }
        
        return fallback
    }
    
    // MARK: - Content
    
    func loadContentIfNeeded() {
        contentBrowser?.sidebarContentViewController.loadViewIfNeeded()
    }
    
    func updateContentLayout(animated: Bool, duration: TimeInterval) {
        contentBrowser?.updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func openExternalURL(_ url: URL) {
        contentBrowser?.openExternalURL(url)
    }
}
