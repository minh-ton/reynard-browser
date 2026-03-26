//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController, AddressBarDelegate, PhoneToolbarDelegate, TabManagerDelegate {
    let overviewInset: CGFloat = 16
    let overviewSpacing: CGFloat = 16
    private let actsAsRootContainer: Bool
    private var embeddedSplitController: BrowserSplitViewController?
    
    lazy var tabCollectionCoordinator = TabCollectionCoordinator(controller: self)
    
    lazy var browserUI = BrowserUI(
        controller: self,
        overviewInset: overviewInset,
        overviewSpacing: overviewSpacing,
        tabCollectionHandler: tabCollectionCoordinator
    )
    
    lazy var tabManager: TabManager = TabManagerImplementation(delegate: self)
    lazy var browserActions = BrowserActions(controller: self)
    lazy var browserLayout = BrowserLayout(controller: self)
    lazy var addressBarGestures = AddressBarGestures(controller: self)
    lazy var tabOverviewPresentation = TabOverviewPresentation(controller: self)
    
    var isSearchFocused = false
    private var pendingSelectionAnimation = false
    
    var isLibrarySidebarVisible: Bool {
        (splitViewController as? BrowserSplitViewController)?.isLibrarySidebarVisible ?? false
    }
    
    var isPadLayout: Bool {
        traitCollection.userInterfaceIdiom == .pad
    }
    
    var usesCompactPadChromeMode: Bool {
        isPadLayout && traitCollection.horizontalSizeClass == .compact
    }
    
    var usesPadChromeLayout: Bool {
        if isPadLayout {
            return true
        }
        
        // Also use the pad layout in iPhone landscape mode
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }
        
        return view.bounds.width > view.bounds.height
    }
    
    var activeAddressBar: AddressBar {
        browserUI.addressBar
    }
    
    init(actsAsRootContainer: Bool = true) {
        self.actsAsRootContainer = actsAsRootContainer
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private var usesEmbeddedSplitRoot: Bool {
        actsAsRootContainer && traitCollection.userInterfaceIdiom == .pad
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        if usesEmbeddedSplitRoot {
            configureEmbeddedSplitRoot()
            return
        }
        
        browserLayout.configureLayout()
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        addressBarGestures.configureGestures()
        browserLayout.observeKeyboard()
        
        tabManager.createInitialTab()
        browserLayout.applyChromeLayout(animated: false)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        syncBrowserNavigationChrome(animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        view.endEditing(true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        browserLayout.applyChromeLayout(animated: false)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard !usesEmbeddedSplitRoot else {
            embeddedSplitController?.refreshSidebarVisibility()
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        browserLayout.applyChromeLayout(animated: false)
        browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        browserUI.padTabBar.collectionView.collectionViewLayout.invalidateLayout()
        tabOverviewPresentation.refreshForCurrentOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        
        coordinator.animate { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserLayout.applyChromeLayout(animated: false)
            self.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
            self.browserUI.padTabBar.collectionView.collectionViewLayout.invalidateLayout()
        } completion: { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.geckoView.transform = .identity
            self.addressBarGestures.resetHorizontalTransition()
            self.browserLayout.applyChromeLayout(animated: false)
            self.tabOverviewPresentation.refreshForCurrentOrientation()
            self.view.layoutIfNeeded()
        }
    }
    
    @discardableResult
    func createTab(selecting: Bool, windowId: String? = nil, at index: Int? = nil) -> Int {
        tabManager.addTab(selecting: selecting, windowId: windowId, at: index)
    }
    
    func selectTab(at index: Int, animated: Bool) {
        pendingSelectionAnimation = animated
        tabManager.selectTab(at: index)
    }
    
    func closeTab(at index: Int) {
        tabManager.removeTab(at: index)
    }
    
    func clearAllTabs() {
        tabManager.removeAllTabs()
    }
    
    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        tabOverviewPresentation.setVisible(visible, animated: animated)
    }
    
    func setSearchFocused(_ focused: Bool, animated: Bool) {
        browserLayout.setSearchFocused(focused, animated: animated)
    }
    
    func applyChromeLayout(animated: Bool) {
        browserLayout.applyChromeLayout(animated: animated)
    }
    
    func centerSelectedPadTab(animated: Bool) {
        guard usesPadChromeLayout, tabManager.tabs.indices.contains(tabManager.selectedTabIndex) else {
            return
        }
        
        let indexPath = IndexPath(item: tabManager.selectedTabIndex, section: 0)
        browserUI.padTabBar.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
    }
    
    func browse(to term: String) {
        tabManager.browse(to: term)
    }
    
    func updateNavigationButtons() {
        guard let tab = tabManager.selectedTab else {
            return
        }
        
        browserUI.toolbarView.updateBackButton(canGoBack: tab.canGoBack)
        browserUI.toolbarView.updateForwardButton(canGoForward: tab.canGoForward)
        let shareEnabled = tabManager.shareableURL(for: tab) != nil
        browserUI.toolbarView.updateShareButton(isEnabled: shareEnabled)
        browserUI.padTopBarButtons.shareButton.isEnabled = shareEnabled
        browserUI.padTopBarButtons.backButton.isEnabled = tab.canGoBack
        browserUI.padTopBarButtons.forwardButton.isEnabled = tab.canGoForward
    }
    
    private func syncPadSidebarButtonItem() {
        browserUI.padTopBarButtons.syncSidebarButton(splitViewController: splitViewController)
    }
    
    private func syncBrowserNavigationChrome(animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }
    
    private func configureEmbeddedSplitRoot() {
        guard embeddedSplitController == nil else {
            return
        }
        
        let splitController = BrowserSplitViewController(browserViewController: BrowserViewController(actsAsRootContainer: false))
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
        guard isPadLayout else {
            return
        }
        
        (splitViewController as? BrowserSplitViewController)?.setLibrarySidebarVisible(visible)
        browserLayout.applyChromeLayout(animated: animated)
    }
    
    func captureThumbnail(for index: Int) {
        guard tabManager.tabs.indices.contains(index),
              index == tabManager.selectedTabIndex,
              !browserUI.geckoView.isHidden else {
            return
        }
        
        guard let tab = tabManager.tabs[safe: index] else {
            return
        }
        
        let bounds = browserUI.geckoView.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        
        browserUI.geckoView.layoutIfNeeded()
        
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { context in
            browserUI.geckoView.layer.render(in: context.cgContext)
        }
        tab.thumbnail = image
    }
    
    func syncAddressBarLoadingState(progress: Float, isLoading: Bool) {
        browserUI.addressBar.setLoadingProgress(progress, isLoading: isLoading)
    }
    
    func tabManagerDidChangeTabs(_ tabManager: TabManager) {
        if let selectedTab = tabManager.selectedTab {
            if browserUI.geckoView.session !== selectedTab.session {
                browserUI.geckoView.session = selectedTab.session
            }
        } else {
            browserUI.geckoView.session = nil
        }
        
        browserUI.tabOverviewCollection.collectionView.reloadData()
        browserUI.padTabBar.collectionView.reloadData()
        browserLayout.applyChromeLayout(animated: false)
    }
    
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        if let previousIndex {
            captureThumbnail(for: previousIndex)
        }
        
        guard tabManager.tabs.indices.contains(index) else {
            return
        }
        
        let selectedTab = tabManager.tabs[index]
        browserUI.geckoView.session = selectedTab.session
        
        syncAddressBarLoadingState(progress: selectedTab.progress, isLoading: selectedTab.isLoading)
        
        if !browserUI.addressBar.isEditingText {
            let value = selectedTab.url ?? ""
            browserUI.addressBar.setText(value)
        }
        
        updateNavigationButtons()
        browserUI.tabOverviewCollection.collectionView.reloadData()
        browserUI.padTabBar.collectionView.reloadData()
        
        if usesPadChromeLayout {
            centerSelectedPadTab(animated: pendingSelectionAnimation)
        }
        pendingSelectionAnimation = false
    }
    
    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        guard tabManager.tabs.indices.contains(index) else {
            return
        }
        
        switch reason {
        case .title:
            browserUI.padTabBar.collectionView.reloadData()
            browserUI.tabOverviewCollection.collectionView.reloadData()
            
        case .location:
            if index == tabManager.selectedTabIndex,
               !browserUI.addressBar.isEditingText {
                browserUI.addressBar.setText(tabManager.tabs[index].url)
            }
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
            }
            
        case .navigationState:
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
            }
            
        case .loading:
            if index == tabManager.selectedTabIndex {
                let tab = tabManager.tabs[index]
                syncAddressBarLoadingState(progress: tab.progress, isLoading: tab.isLoading)
            }
            
        case .thumbnail:
            if index == tabManager.selectedTabIndex {
                captureThumbnail(for: index)
            }
            browserUI.tabOverviewCollection.collectionView.reloadData()
        }
    }
    
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        guard tabManager.tabs.indices.contains(index) else {
            completion()
            return
        }

        addressBarGestures.animateAutomaticNewTabTransition(to: tabManager.tabs[index], completion: completion)
    }

    func tabManager(_ tabManager: TabManager, presentContextMenuAt point: CGPoint, element: ContextElement) {
        // TODO(human): Build the context menu actions based on element type
        presentContextMenu(at: point, element: element)
    }
    
    func backButtonClicked() {
        browserActions.goBack()
    }
    
    func forwardButtonClicked() {
        browserActions.goForward()
    }
    
    func shareButtonClicked() {
        browserActions.presentShareSheet()
    }
    
    func menuButtonClicked() {
        browserActions.presentMenuSheet()
    }
    
    func tabsButtonClicked() {
        browserActions.showTabOverview()
    }
    
    func addressBarDidSubmit(_ searchTerm: String) {
        browse(to: searchTerm)
        view.endEditing(true)
    }
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        setSearchFocused(true, animated: true)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if !browserUI.addressBar.isEditingText {
            setSearchFocused(false, animated: true)
        }
    }
    
    @objc func tabsTapped() {
        browserActions.showTabOverview()
    }
    
    @objc func doneTapped() {
        browserActions.hideTabOverview()
    }
    
    @objc func newTabTapped() {
        browserActions.createNewTab()
    }
    
    @objc func clearAllTabsTapped() {
        browserActions.clearAllTabs()
    }
    
    @objc func shareTapped() {
        browserActions.presentShareSheet()
    }
    
    @objc func librarySidebarTapped() {
        setLibrarySidebarVisible(!isLibrarySidebarVisible, animated: true)
    }
    
    @objc func padBackTapped() {
        browserActions.goBack()
    }
    
    @objc func padForwardTapped() {
        browserActions.goForward()
    }
    
    @objc func topBarMenuTapped() {
        browserActions.presentMenuSheet()
    }
    
    @objc func dismissKeyboardTapped() {
        browserActions.dismissKeyboard()
    }
}

// MARK: - Context Menu

extension BrowserViewController {
    func presentContextMenu(at point: CGPoint, element: ContextElement) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if let text = element.textContent, !text.isEmpty {
            alert.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
                UIPasteboard.general.string = text
                if element.isEditable {
                    self?.tabManager.selectedTab?.session.load("javascript:void(document.execCommand('copy'))")
                }
            })
        }

        if element.isEditable {
            if UIPasteboard.general.hasStrings {
                alert.addAction(UIAlertAction(title: "Paste", style: .default) { [weak self] _ in
                    guard let self, let text = UIPasteboard.general.string else { return }
                    let escaped = text
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                        .replacingOccurrences(of: "\n", with: "\\n")
                        .replacingOccurrences(of: "\r", with: "")
                    self.tabManager.selectedTab?.session.load("javascript:void(document.execCommand('insertText',false,'\(escaped)'))")
                })
            }
            alert.addAction(UIAlertAction(title: "Select All", style: .default) { [weak self] _ in
                guard let self else { return }
                self.tabManager.selectedTab?.session.load("javascript:void(document.execCommand('selectAll'))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let followUp = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                    followUp.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
                        self?.tabManager.selectedTab?.session.load("javascript:void(document.execCommand('copy'))")
                    })
                    if UIPasteboard.general.hasStrings {
                        followUp.addAction(UIAlertAction(title: "Paste", style: .default) { [weak self] _ in
                            guard let self, let text = UIPasteboard.general.string else { return }
                            let escaped = text
                                .replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
                                .replacingOccurrences(of: "\n", with: "\\n")
                                .replacingOccurrences(of: "\r", with: "")
                            self.tabManager.selectedTab?.session.load("javascript:void(document.execCommand('insertText',false,'\(escaped)'))")
                        })
                    }
                    followUp.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    if let popover = followUp.popoverPresentationController {
                        popover.sourceView = self.browserUI.geckoView
                        popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
                    }
                    self.present(followUp, animated: true)
                }
            })
        }

        if let linkUri = element.linkUri, !linkUri.isEmpty {
            alert.addAction(UIAlertAction(title: "Copy Link", style: .default) { _ in
                UIPasteboard.general.string = linkUri
            })
            alert.addAction(UIAlertAction(title: "Open in New Tab", style: .default) { [weak self] _ in
                guard let self else { return }
                self.createTab(selecting: true)
                self.tabManager.browse(to: linkUri)
            })
        }

        if let srcUri = element.srcUri, !srcUri.isEmpty {
            switch element.type {
            case .image:
                alert.addAction(UIAlertAction(title: "Copy Image URL", style: .default) { _ in
                    UIPasteboard.general.string = srcUri
                })
            case .video, .audio:
                alert.addAction(UIAlertAction(title: "Copy Media URL", style: .default) { _ in
                    UIPasteboard.general.string = srcUri
                })
            case .none:
                break
            }
        }

        guard alert.actions.count > 0 else { return }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = browserUI.geckoView
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }

        present(alert, animated: true)
    }
}

final class BrowserSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let browserViewController: BrowserViewController
    private var sidebarVisible = false
    
    private lazy var browserNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()
    
    private lazy var libraryNavigationController: UINavigationController = {
        let libraryViewController = LibrarySidebarViewController()
        let navigationController = UINavigationController(rootViewController: libraryViewController)
        navigationController.navigationBar.tintColor = .label
        return navigationController
    }()
    
    init(browserViewController: BrowserViewController) {
        self.browserViewController = browserViewController
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
        delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        setViewController(libraryNavigationController, for: .primary)
        setViewController(browserNavigationController, for: .secondary)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setLibrarySidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        if visible {
            show(.primary)
        } else {
            hide(.primary)
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
