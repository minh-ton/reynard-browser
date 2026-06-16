//
//  SidebarViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarViewController: UISplitViewController, UISplitViewControllerDelegate {
    // MARK: - UX

    private enum UX {
        static let preferredPrimaryWidth: CGFloat = 320
        static let minimumPrimaryWidth: CGFloat = 280
        static let maximumPrimaryWidth: CGFloat = 360
        static let collapseAnimationDuration: TimeInterval = 0.14
    }

    // MARK: - State

    private let browser: BrowserViewController
    private var sidebarVisible = false

    var contentBrowser: BrowserViewController {
        browser
    }

    var isVisible: Bool {
        sidebarVisible
    }

    // MARK: - View Controllers

    private lazy var menuController = SidebarMenuViewController()

    private lazy var browserNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: browser)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()

    private lazy var menuNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: menuController)
        navigationController.navigationBar.tintColor = .label
        return navigationController
    }()

    // MARK: - Lifecycle

    override var childForStatusBarHidden: UIViewController? {
        browserNavigationController
    }

    init(browserViewController: BrowserViewController) {
        self.browser = browserViewController
        if #available(iOS 14.0, *) {
            super.init(style: .doubleColumn)
        } else {
            super.init(nibName: nil, bundle: nil)
        }
        configureSplitView()
        observeApplicationActivation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool) {
        sidebarVisible = visible
        if #available(iOS 14.0, *) {
            if visible {
                show(.primary)
            } else {
                hide(.primary)
            }
        } else {
            preferredDisplayMode = visible ? .allVisible : .primaryHidden
        }
        updateBrowserLayoutIfNeeded()
    }

    func collapse(from sourceView: UIView?) {
        guard let sourceView,
              browser.isViewLoaded,
              let containerView = viewIfLoaded,
              let snapshot = sourceView.snapshotView(afterScreenUpdates: false) else {
            setVisible(false)
            return
        }

        let sourceFrame = sourceView.convert(sourceView.bounds, to: containerView)
        snapshot.frame = sourceFrame
        containerView.addSubview(snapshot)

        sourceView.isHidden = true
        setVisible(false)
        containerView.layoutIfNeeded()
        browser.view.layoutIfNeeded()

        let destinationFrame = browser.browserChrome.sidebarButtonFrame(in: containerView)
        browser.browserChrome.setSidebarButtonTransition(alpha: 0, hidden: false)

        UIView.animate(withDuration: UX.collapseAnimationDuration, delay: 0, options: [.curveEaseOut]) {
            snapshot.frame = destinationFrame
            self.browser.browserChrome.setSidebarButtonTransition(alpha: 1, hidden: false)
        } completion: { _ in
            sourceView.isHidden = false
            self.browser.browserChrome.setSidebarButtonTransition(alpha: 1, hidden: false)
            snapshot.removeFromSuperview()
        }
    }

    func refreshVisibility() {
        sidebarVisible = displayMode != .secondaryOnly
        updateBrowserLayoutIfNeeded()
    }

    // MARK: - Sections

    func showSection(_ section: LibrarySection) {
        setVisible(true)
        menuController.showSection(section, animated: false)
    }

    // MARK: - UISplitViewControllerDelegate

    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {
        sidebarVisible = displayMode != .secondaryOnly
        updateBrowserLayoutIfNeeded()
    }

    // MARK: - Notifications

    @objc private func applicationDidBecomeActive() {
        refreshVisibility()
    }

    // MARK: - View Setup

    private func configureSplitView() {
        delegate = self
        presentsWithGesture = false
        if #available(iOS 14.0, *) {
            preferredDisplayMode = .secondaryOnly
            preferredSplitBehavior = .tile
            preferredPrimaryColumnWidth = UX.preferredPrimaryWidth
            minimumPrimaryColumnWidth = UX.minimumPrimaryWidth
            maximumPrimaryColumnWidth = UX.maximumPrimaryWidth
            showsSecondaryOnlyButton = false
            if #available(iOS 14.5, *) {
                displayModeButtonVisibility = .never
            }
            setViewController(menuNavigationController, for: .primary)
            setViewController(browserNavigationController, for: .secondary)
        } else {
            preferredDisplayMode = .primaryHidden
            viewControllers = [menuNavigationController, browserNavigationController]
        }
    }

    private func observeApplicationActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func updateBrowserLayoutIfNeeded() {
        if browser.isViewLoaded {
            browser.updateBrowserLayout(animated: false)
        }
    }
}
