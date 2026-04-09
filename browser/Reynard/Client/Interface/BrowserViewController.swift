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
    private var pendingDownloadConfirmations: [DownloadStore.PendingDownload] = []
    private var isPresentingDownloadConfirmation = false
    
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
        
        observeDownloadState()
        syncDownloadButtonState()
        
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
        syncDownloadButtonState()
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
    
    func openExternalURL(_ url: URL) {
        browse(to: url.absoluteString)
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
    
    private func observeDownloadState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadStoreDidChange),
            name: .downloadStoreDidChange,
            object: nil
        )
    }
    
    @objc private func handleDownloadStoreDidChange() {
        syncDownloadButtonState()
    }
    
    private func syncDownloadButtonState() {
        let previousPadShowsDownloads = browserUI.padTopBarButtons.downloadButton.isShowingDownloads
        let summary = DownloadStore.shared.snapshot().summary
        browserUI.toolbarView.updateDownloadButton(summary: summary)
        browserUI.padTopBarButtons.updateDownloadButton(summary: summary)
        let showsPadDownloads = browserUI.padTopBarButtons.downloadButton.isShowingDownloads
        
        if !usesEmbeddedSplitRoot,
           isPadLayout,
           !usesCompactPadChromeMode,
           previousPadShowsDownloads != showsPadDownloads {
            browserLayout.applyChromeLayout(animated: false)
        }
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
        guard !browserUI.geckoView.isHidden,
              let tab = tabManager.tabs[safe: index],
              browserUI.geckoView.session === tab.session else {
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
        tabManager.updateThumbnail(image, forTabAt: index)
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
    
    func tabManager(_ tabManager: TabManager, didRequestDownload download: DownloadStore.PendingDownload) {
        DispatchQueue.main.async { [weak self] in
            self?.pendingDownloadConfirmations.append(download)
            self?.presentNextDownloadConfirmationIfNeeded()
        }
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
    
    func downloadsButtonClicked() {
        presentDownloadsFromToolbar()
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
    
    private func presentNextDownloadConfirmationIfNeeded() {
        guard !isPresentingDownloadConfirmation,
              let download = pendingDownloadConfirmations.first,
              let presenter = topPresentedViewController else {
            return
        }
        
        isPresentingDownloadConfirmation = true
        
        let alert = UIAlertController(
            title: "Do you want to download \"\(download.fileName)\"?",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finishDownloadConfirmation(startDownload: false)
        })
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            self?.finishDownloadConfirmation(startDownload: true)
        })
        
        presenter.present(alert, animated: true)
    }
    
    private func finishDownloadConfirmation(startDownload: Bool) {
        guard !pendingDownloadConfirmations.isEmpty else {
            isPresentingDownloadConfirmation = false
            return
        }
        
        let download = pendingDownloadConfirmations.removeFirst()
        isPresentingDownloadConfirmation = false
        
        if startDownload {
            DownloadStore.shared.startDownload(download)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.presentNextDownloadConfirmationIfNeeded()
        }
    }
    
    private var topPresentedViewController: UIViewController? {
        var controller: UIViewController? = self
        
        while let presentedViewController = controller?.presentedViewController {
            controller = presentedViewController
        }
        
        return controller
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
    
    @objc func topBarDownloadsTapped() {
        presentDownloadsFromToolbar()
    }
    
    @objc func dismissKeyboardTapped() {
        browserActions.dismissKeyboard()
    }
    
    private func presentDownloadsFromToolbar() {
        DownloadStore.shared.markCompletedDownloadsViewed()
        if isPadLayout,
           !usesCompactPadChromeMode,
           let splitViewController = splitViewController as? BrowserSplitViewController {
            splitViewController.showLibrarySection(.downloads)
            return
        }
        
        browserActions.presentMenuSheet(initialSection: .downloads)
    }
    
}

final class BrowserSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let browserViewController: BrowserViewController
    private var sidebarVisible = false
    private lazy var libraryViewController = LibrarySidebarViewController()
    
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
