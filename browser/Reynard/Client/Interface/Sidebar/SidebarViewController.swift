//
//  SidebarViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarViewController: UISplitViewController, UISplitViewControllerDelegate {
    private enum UX {
        static let preferredPrimaryWidth: CGFloat = 320
        static let minimumPrimaryWidth: CGFloat = 280
        static let maximumPrimaryWidth: CGFloat = 360
        static let collapseAnimationDuration: TimeInterval = 0.14
        static let layoutAnimationDuration: TimeInterval = 0.22
    }
    
    private let contentController: SidebarContentController
    private var sidebarVisible = false
    private weak var activeSidebarTextField: UITextField?
    
    var contentBrowser: SidebarContentController {
        return contentController
    }
    
    var isSidebarVisible: Bool {
        return sidebarVisible
    }
    
    var showChromeSidebarButton: Bool {
        guard sidebarVisible else {
            return true
        }
        if #available(iOS 14.0, *) {
            return usesOverlaySplitBehavior
        }
        return false
    }
    
    private lazy var menuController = SidebarMenuViewController()
    
    private lazy var browserNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: contentController.sidebarContentViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()
    
    private lazy var menuNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: menuController)
        navigationController.navigationBar.tintColor = .label
        return navigationController
    }()
    
    private lazy var primaryNavigationController: UINavigationController = {
        let container = SidebarNavigationContainerViewController(navigationController: menuNavigationController)
        let navigationController = UINavigationController(rootViewController: container)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()
    
    // MARK: - Lifecycle
    
    override var childForStatusBarHidden: UIViewController? {
        return browserNavigationController
    }
    
    init(contentController: SidebarContentController) {
        self.contentController = contentController
        if #available(iOS 14.0, *) {
            super.init(style: .doubleColumn)
        } else {
            super.init(nibName: nil, bundle: nil)
        }
        configureSplitView()
        observeApplicationActivation()
        observeTextInput()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateContentLayoutIfNeeded(animated: false, duration: UX.layoutAnimationDuration)
        updateSplitBehavior()
    }
    
    // MARK: - Visibility
    
    func setVisible(_ visible: Bool) {
        sidebarVisible = visible
        if #available(iOS 14.0, *) {
            updateSplitBehavior()
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
    
    func toggleVisibility() {
        setVisible(!sidebarVisible)
    }
    
    func collapse(from sourceView: UIView?) {
        guard !UIAccessibility.isReduceMotionEnabled,
              let sourceView,
              contentController.sidebarContentViewController.isViewLoaded,
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
        contentController.sidebarContentViewController.view.layoutIfNeeded()
        
        let destinationFrame = contentController.sidebarContentChrome.sidebarButtonFrame(in: containerView)
        contentController.sidebarContentChrome.setSidebarButtonTransition(alpha: 0, hidden: false)
        
        UIView.animate(withDuration: UX.collapseAnimationDuration, delay: 0, options: [.curveEaseOut]) {
            snapshot.frame = destinationFrame
            self.contentController.sidebarContentChrome.setSidebarButtonTransition(alpha: 1, hidden: false)
        } completion: { _ in
            sourceView.isHidden = false
            self.contentController.sidebarContentChrome.setSidebarButtonTransition(alpha: 1, hidden: false)
            snapshot.removeFromSuperview()
        }
    }
    
    func refreshVisibility() {
        sidebarVisible = displayMode != .secondaryOnly
        updateBrowserLayoutIfNeeded()
    }
    
    // MARK: - Sections
    
    func showSection(_ section: LibrarySection, startsEditingBookmarks: Bool = false) {
        setVisible(true)
        menuController.showSection(
            section,
            animated: false,
            startsEditingBookmarks: startsEditingBookmarks
        )
    }
    
    func toggleSection(_ section: LibrarySection) {
        guard section != .history || !contentController.sidebarContentIsPrivate else {
            return
        }
        if isSidebarVisible,
           menuController.shownSection == section {
            setVisible(false)
            return
        }
        
        showSection(section)
    }
    // MARK: - UISplitViewControllerDelegate
    
    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {
        sidebarVisible = displayMode != .secondaryOnly
        updateBrowserLayoutIfNeeded()
        if !sidebarVisible {
            menuNavigationController.view.endEditing(true)
        }
    }
    
    // MARK: - Notifications
    
    @objc private func applicationDidBecomeActive() {
        refreshVisibility()
        menuController.refreshSidebarButton()
    }
    
    @objc private func applicationWillResignActive() {
        menuController.refreshSidebarButton()
    }
    
    @objc private func sidebarTextInputDidBeginEditing(_ notification: Notification) {
        guard let textField = notification.object as? UITextField,
              menuNavigationController.isViewLoaded,
              textField.isDescendant(of: menuNavigationController.view) else {
            return
        }
        activeSidebarTextField = textField
    }
    
    @objc private func sidebarTextInputDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? UITextField,
              activeSidebarTextField === textField else {
            return
        }
        activeSidebarTextField = nil
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  activeSidebarTextField == nil else {
                return
            }
            contentController.sidebarDidEndEditing()
        }
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
            setViewController(primaryNavigationController, for: .primary)
            setViewController(browserNavigationController, for: .secondary)
            menuNavigationController.loadViewIfNeeded()
        } else {
            preferredDisplayMode = .primaryHidden
            viewControllers = [primaryNavigationController, browserNavigationController]
        }
    }
    
    private func observeApplicationActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    private func observeTextInput() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarTextInputDidBeginEditing(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarTextInputDidEndEditing(_:)),
            name: UITextField.textDidEndEditingNotification,
            object: nil
        )
    }
    
    // MARK: - Layout
    
    private var usesOverlaySplitBehavior: Bool {
        let browserLayout = contentController.sidebarContentLayout
        return browserLayout.orientation == .portrait
        || (BrowserLayout.isSidebarOverlayLayout(in: view) && browserLayout.chromeMode != .compact)
    }
    
    private func updateSplitBehavior() {
        guard #available(iOS 14.0, *) else {
            return
        }
        
        let splitBehavior: UISplitViewController.SplitBehavior = usesOverlaySplitBehavior ? .overlay : .tile
        
        if preferredSplitBehavior != splitBehavior {
            preferredSplitBehavior = splitBehavior
        }
    }
    
    private func updateBrowserLayoutIfNeeded() {
        if contentController.sidebarContentViewController.isViewLoaded {
            contentController.updateBrowserLayout(animated: false, duration: UX.layoutAnimationDuration)
        }
    }
    
    private func updateContentLayoutIfNeeded(animated: Bool, duration: TimeInterval) {
        guard contentController.sidebarContentViewController.isViewLoaded else {
            return
        }
        
        contentController.updateBrowserLayoutIfNeeded(animated: animated, duration: duration)
    }
}

extension SidebarViewController {
    @objc private func showHistoryKeyCommand(_ sender: UIKeyCommand) {
        toggleSection(.history)
    }
    
    @objc private func showBookmarksKeyCommand(_ sender: UIKeyCommand) {
        toggleSection(.bookmarks)
    }
    
    @objc private func showDownloadsKeyCommand(_ sender: UIKeyCommand) {
        toggleSection(.downloads)
    }
    
    @objc private func toggleSidebarKeyCommand(_ sender: UIKeyCommand) {
        toggleVisibility()
    }
    
    @objc private func editBookmarksKeyCommand(_ sender: UIKeyCommand) {
        showSection(.bookmarks, startsEditingBookmarks: true)
    }
}
