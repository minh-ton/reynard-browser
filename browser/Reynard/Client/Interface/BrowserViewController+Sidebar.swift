//
//  BrowserViewController+Sidebar.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import ObjectiveC
import UIKit

private enum SidebarAssociatedKeys {
    static var isSidebarContainerHost = 0
    static var embeddedSplitController = 0
}

extension BrowserViewController {
    var isSidebarContainerHost: Bool {
        get {
            (objc_getAssociatedObject(self, &SidebarAssociatedKeys.isSidebarContainerHost) as? NSNumber)?.boolValue ?? true
        }
        set {
            objc_setAssociatedObject(
                self,
                &SidebarAssociatedKeys.isSidebarContainerHost,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    var embeddedSplitController: BrowserSplitViewController? {
        get {
            objc_getAssociatedObject(self, &SidebarAssociatedKeys.embeddedSplitController) as? BrowserSplitViewController
        }
        set {
            objc_setAssociatedObject(
                self,
                &SidebarAssociatedKeys.embeddedSplitController,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    var isLibrarySidebarVisible: Bool {
        (splitViewController as? BrowserSplitViewController)?.isLibrarySidebarVisible ?? false
    }
    
    var shouldEmbedSidebarContainer: Bool {
        isSidebarContainerHost && traitCollection.userInterfaceIdiom == .pad
    }
    
    func syncPadSidebarButtonItem() {
        browserUI.padTopBarButtons.syncSidebarButton(splitViewController: splitViewController)
    }
    
    func setupEmbeddedSidebarContainer() {
        guard embeddedSplitController == nil else {
            return
        }
        
        let splitController = BrowserSplitViewController(browserViewController: BrowserViewController(isSidebarContainerHost: false))
        addChild(splitController)
        splitController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitController.view)
        NSLayoutConstraint.activate([
            splitController.view.topAnchor.constraint(equalTo: view.topAnchor),
            splitController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        splitController.didMove(toParent: self)
        embeddedSplitController = splitController
    }
    
    func setLibrarySidebarVisible(_ visible: Bool, animated: Bool) {
        guard isPad else {
            return
        }
        
        (splitViewController as? BrowserSplitViewController)?.setLibrarySidebarVisible(visible)
        browserUI.applyChromeLayout(animated: animated)
    }
    
    @objc func librarySidebarTapped() {
        setLibrarySidebarVisible(!isLibrarySidebarVisible, animated: true)
    }
}

final class BrowserSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let browserViewController: BrowserViewController
    private var sidebarVisible = false
    private lazy var libraryViewController = LibrarySidebarViewController()
    
    var contentBrowserViewController: BrowserViewController {
        browserViewController
    }
    
    private lazy var browserNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()
    
    private lazy var libraryNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: libraryViewController)
        navigationController.navigationBar.tintColor = .label
        return navigationController
    }()
    
    init(browserViewController: BrowserViewController) {
        self.browserViewController = browserViewController
        if #available(iOS 14.0, *) {
            super.init(style: .doubleColumn)
            preferredDisplayMode = .secondaryOnly
            preferredSplitBehavior = .tile
            preferredPrimaryColumnWidth = 320
            minimumPrimaryColumnWidth = 280
            maximumPrimaryColumnWidth = 360
            presentsWithGesture = false
            showsSecondaryOnlyButton = false
            if #available(iOS 14.5, *) {
                displayModeButtonVisibility = .never
            }
            setViewController(libraryNavigationController, for: .primary)
            setViewController(browserNavigationController, for: .secondary)
        } else {
            super.init(nibName: nil, bundle: nil)
            preferredDisplayMode = .primaryHidden
            presentsWithGesture = false
            viewControllers = [libraryNavigationController, browserNavigationController]
        }
        delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setLibrarySidebarVisible(_ visible: Bool) {
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
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }
    
    func collapseLibrarySidebar(from sourceView: UIView?) {
        guard let sourceView,
              browserViewController.isViewLoaded,
              let containerView = viewIfLoaded,
              let snapshot = sourceView.snapshotView(afterScreenUpdates: false) else {
            setLibrarySidebarVisible(false)
            return
        }
        
        let destinationButton = browserViewController.browserUI.padTopBarButtons.sidebarButton
        let sourceFrame = sourceView.convert(sourceView.bounds, to: containerView)
        snapshot.frame = sourceFrame
        containerView.addSubview(snapshot)
        
        sourceView.isHidden = true
        setLibrarySidebarVisible(false)
        containerView.layoutIfNeeded()
        browserViewController.view.layoutIfNeeded()
        
        let destinationFrame = destinationButton.convert(destinationButton.bounds, to: containerView)
        destinationButton.alpha = 0
        destinationButton.isHidden = false
        
        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut]) {
            snapshot.frame = destinationFrame
            destinationButton.alpha = 1
        } completion: { _ in
            sourceView.isHidden = false
            destinationButton.alpha = 1
            snapshot.removeFromSuperview()
        }
    }
    
    func showLibrarySection(_ section: LibrarySection) {
        setLibrarySidebarVisible(true)
        libraryViewController.showSection(section, animated: false)
    }
    
    var isLibrarySidebarVisible: Bool {
        sidebarVisible
    }
    
    func refreshSidebarVisibility() {
        sidebarVisible = displayMode != .secondaryOnly
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }
    
    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {
        sidebarVisible = displayMode != .secondaryOnly
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }
    
    @objc private func applicationDidBecomeActive() {
        refreshSidebarVisibility()
    }
}

enum SidebarToggleButtonConfiguration {
    private static let fallbackImage = UIImage(systemName: "sidebar.left")
    
    static func configure(_ button: UIButton, in splitViewController: UISplitViewController?) {
        button.setImage(resolvedImage(in: splitViewController), for: .normal)
        button.accessibilityLabel = resolvedAccessibilityLabel(in: splitViewController)
    }
    
    private static func resolvedImage(in splitViewController: UISplitViewController?) -> UIImage? {
        splitViewController?.displayModeButtonItem.image ?? fallbackImage
    }
    
    private static func resolvedAccessibilityLabel(in splitViewController: UISplitViewController?) -> String? {
        splitViewController?.displayModeButtonItem.accessibilityLabel
    }
}
