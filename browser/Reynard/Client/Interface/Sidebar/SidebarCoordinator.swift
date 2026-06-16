//
//  SidebarCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarCoordinator {
    // MARK: - State

    private unowned let browser: BrowserViewController
    private let canHostSidebar: Bool
    private var sidebar: SidebarViewController?

    var statusBarController: UIViewController? {
        hostsSidebar ? sidebar : nil
    }

    var contentBrowser: BrowserViewController {
        sidebar?.contentBrowser ?? browser
    }

    var isVisible: Bool {
        (browser.splitViewController as? SidebarViewController)?.isVisible ?? false
    }

    var hostsSidebar: Bool {
        canHostSidebar && browser.browserLayout.interfaceIdiom == .pad
    }

    // MARK: - Lifecycle

    init(browserViewController: BrowserViewController, canHostSidebar: Bool) {
        self.browser = browserViewController
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

        let contentBrowser = BrowserViewController(canHostSidebar: false)
        let sidebar = SidebarViewController(browserViewController: contentBrowser)
        browser.addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        browser.view.addSubview(sidebar.view)
        NSLayoutConstraint.activate([
            sidebar.view.topAnchor.constraint(equalTo: browser.view.topAnchor),
            sidebar.view.leadingAnchor.constraint(equalTo: browser.view.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: browser.view.trailingAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: browser.view.bottomAnchor),
        ])
        sidebar.didMove(toParent: browser)
        self.sidebar = sidebar
        return true
    }

    // MARK: - Visibility

    func toggle(animated: Bool) {
        guard browser.browserLayout.interfaceIdiom == .pad else {
            return
        }

        (browser.splitViewController as? SidebarViewController)?.setVisible(!isVisible)
        browser.updateBrowserLayout(animated: animated)
    }

    func refreshVisibility() {
        sidebar?.refreshVisibility()
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
        (browser.splitViewController as? SidebarViewController)?.showSection(section)
    }

    func topInset(fallback: CGFloat) -> CGFloat {
        guard browser.browserLayout.interfaceIdiom == .pad,
              browser.splitViewController is SidebarViewController else {
            return browser.view.safeAreaInsets.top
        }

        if let statusBarHeight = browser.view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
           statusBarHeight > 0 {
            return statusBarHeight
        }

        return fallback
    }
}
