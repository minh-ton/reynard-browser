//
//  BrowserViewController+UI.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import ObjectiveC
import GeckoView
import UIKit

private enum UIAssociatedKeys {
    static var tabCollectionCoordinator = 0
    static var browserUI = 0
    static var addressBarGestures = 0
    static var isSearchFocused = 0
}

extension BrowserViewController {
    var overviewInset: CGFloat {
        16
    }
    
    var overviewSpacing: CGFloat {
        16
    }
    
    var tabCollectionCoordinator: TabCollectionCoordinator {
        get {
            if let coordinator = objc_getAssociatedObject(self, &UIAssociatedKeys.tabCollectionCoordinator) as? TabCollectionCoordinator {
                return coordinator
            }
            
            let coordinator = TabCollectionCoordinator(controller: self)
            objc_setAssociatedObject(self, &UIAssociatedKeys.tabCollectionCoordinator, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return coordinator
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.tabCollectionCoordinator, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var browserUI: BrowserUI {
        get {
            if let ui = objc_getAssociatedObject(self, &UIAssociatedKeys.browserUI) as? BrowserUI {
                return ui
            }
            
            let ui = BrowserUI(controller: self, tabCollectionHandler: tabCollectionCoordinator)
            objc_setAssociatedObject(self, &UIAssociatedKeys.browserUI, ui, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return ui
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.browserUI, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var addressBarGestures: AddressBarGestures {
        get {
            if let gestures = objc_getAssociatedObject(self, &UIAssociatedKeys.addressBarGestures) as? AddressBarGestures {
                return gestures
            }
            
            let gestures = AddressBarGestures(controller: self)
            objc_setAssociatedObject(self, &UIAssociatedKeys.addressBarGestures, gestures, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return gestures
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.addressBarGestures, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var isSearchFocused: Bool {
        get {
            (objc_getAssociatedObject(self, &UIAssociatedKeys.isSearchFocused) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.isSearchFocused, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var usesCompactPadChrome: Bool {
        if isPad && traitCollection.horizontalSizeClass == .compact { return true }
        return usesTopPhoneAddressBar
    }
    
    var usesPadChrome: Bool {
        if isPad { return true }
        if usesTopPhoneAddressBar { return true }
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }
        return view.bounds.width > view.bounds.height
    }
    
    var usesTopPhoneAddressBar: Bool {
        guard !isPad else { return false }
        let isLandscape: Bool
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            isLandscape = orientation.isLandscape
        } else {
            isLandscape = view.bounds.width > view.bounds.height
        }
        guard !isLandscape else { return false }
        return Prefs.AppearanceSettings.addressBarPosition == .top
    }
    
    var usesBottomPhoneOverview: Bool {
        guard !isPad else { return false }
        return usesTopPhoneAddressBar || !usesPadChrome
    }
    
    var activeAddressBar: AddressBar {
        browserUI.addressBar
    }
    
    @objc func applyUpdateMenuButtonBadge() {
        browserUI.toolbarView.setMenuButtonIndicatesUpdate(true)
        browserUI.padTopBarButtons.setMenuButtonIndicatesUpdate(true)
    }
    
    func setSearchFocused(_ focused: Bool, animated: Bool) {
        browserUI.setSearchFocused(focused, animated: animated)
    }
    
    func applyChromeLayout(animated: Bool) {
        browserUI.applyChromeLayout(animated: animated)
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
    
    @objc func addressBarPositionDidChange() {
        browserUI.applyChromeLayout(animated: true)
    }
    
    @objc func landscapeTabBarDidChange() {
        browserUI.applyChromeLayout(animated: true)
    }
    
    func syncBrowserNavigationChrome(animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }
    
    private func activeTabBarHeight() -> CGFloat {
        guard usesPadChrome,
              tabManager.tabs.count > 1 else {
            return 0
        }
        
        if !isPad {
            guard Prefs.AppearanceSettings.showsLandscapeTabBar else {
                return 0
            }
            let isLandscape: Bool
            if let orientation = view.window?.windowScene?.interfaceOrientation {
                isLandscape = orientation.isLandscape
            } else {
                isLandscape = view.bounds.width > view.bounds.height
            }
            guard isLandscape else {
                return 0
            }
        }
        
        return 36
    }
    
    func tabPreviewAspectRatio() -> CGFloat {
        let bounds = browserUI.geckoView.bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height + activeTabBarHeight(), 1)
        return height / width
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
    
    func dismissalContentFrame() -> CGRect {
        let frame = browserUI.geckoView.frame
        let tabBarHeight = activeTabBarHeight()
        guard tabBarHeight > 0,
              usesPadChrome,
              tabOverviewPresentation.isVisible else {
            return frame
        }
        
        return CGRect(
            x: frame.minX,
            y: frame.minY + tabBarHeight,
            width: frame.width,
            height: max(1, frame.height - tabBarHeight)
        )
    }
    
    func syncAddressBarLoadingState(progress: Float, isLoading: Bool) {
        browserUI.addressBar.setLoadingProgress(progress, isLoading: isLoading)
    }
    
    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let pendingDisplayText = selectedTab?.pendingDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPendingDisplayText = !(pendingDisplayText?.isEmpty ?? true)
        let selectedURL = selectedTab?.url
        let displayedText = hasPendingDisplayText ? pendingDisplayText : selectedURL
        if !browserUI.addressBar.isEditingText {
            browserUI.addressBar.setText(
                displayedText,
                locationText: selectedURL,
                locationTitle: selectedTab?.title,
                showsBarMenu: !hasPendingDisplayText && selectedURL?.isEmpty == false
            )
        }
        browserUI.addressBar.setLoadingProgress(selectedTab?.progress ?? 0, isLoading: selectedTab?.isLoading ?? false)
        addonsController.prepareVisibleAddonIcons()
        let addonItems = addonsController.visibleMenuItemsForCurrentSite().map { item in
            AddressBarMenu.AddonItem(menuItem: item, image: addonsController.iconImage(for: item.addon))
        }
        browserUI.addressBar.setAddonsMenu(
            AddressBarMenu.makeMenu(
                selectedTab: selectedTab,
                selectedURL: selectedURL,
                addonItems: addonItems
            )
        )
    }
    
    @objc func presentAddonSettingsRequested(_ notification: Notification) {
        guard let item = notification.userInfo?["addonItem"] as? AddonMenuItem else {
            return
        }
        
        addonsController.presentCurrentSiteSettings(for: item)
    }
    
    func addressBarDidSubmit(_ searchTerm: String) {
        browse(to: searchTerm)
        view.endEditing(true)
    }
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        refreshAddressBar()
        setSearchFocused(true, animated: true)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        refreshAddressBar()
        if !browserUI.addressBar.isEditingText {
            setSearchFocused(false, animated: true)
        }
    }
    
    func addressBarDidTapTrailingButton(_ addressBar: AddressBar) {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }
        
        if selectedTab.isLoading {
            selectedTab.session.stop()
            return
        }
        
        selectedTab.session.reload()
    }
}

final class BrowserUI {
    typealias TabCollectionHandler = UICollectionViewDataSource & UICollectionViewDelegate & UICollectionViewDelegateFlowLayout
    
    let geckoView: GeckoView = {
        let view = GeckoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let chromeContainer = ChromeContainer()
    
    let addressBar: AddressBar = {
        let bar = AddressBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()
    
    let keyboardDismissButton = KeyboardDismissButton()
    
    let toolbarView: PhoneToolbar = {
        let bar = PhoneToolbar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()
    
    let topBar = PadTopBar()
    let padTopBarButtons: PadTopBarButtons
    let tabBar: TabBar
    
    let tabOverview = TabOverview()
    let tabOverviewCollection: TabOverviewCollection
    let tabOverviewBottomBar = TabOverviewBottomBar()
    let tabOverviewTopBar = TabOverviewTopBar()
    let tabOverviewBarButtons: TabOverviewBarButtons
    
    var geckoTopPhoneConstraint: NSLayoutConstraint!
    var geckoTopPadConstraint: NSLayoutConstraint!
    var geckoBottomPhoneConstraint: NSLayoutConstraint!
    var geckoBottomPhoneSearchPinnedConstraint: NSLayoutConstraint!
    var geckoBottomPhoneKeyboardOverlayConstraint: NSLayoutConstraint!
    var geckoBottomPadConstraint: NSLayoutConstraint!
    var geckoBottomCompactPadConstraint: NSLayoutConstraint!
    var geckoLeadingPhoneConstraint: NSLayoutConstraint!
    var geckoTrailingPhoneConstraint: NSLayoutConstraint!
    var geckoLeadingPadConstraint: NSLayoutConstraint!
    var geckoTrailingPadConstraint: NSLayoutConstraint!
    var geckoTopFullscreenConstraint: NSLayoutConstraint!
    var geckoBottomFullscreenConstraint: NSLayoutConstraint!
    
    var phoneChromeBottomConstraint: NSLayoutConstraint!
    var phoneChromeHeightConstraint: NSLayoutConstraint!
    var phoneToolbarHeightConstraint: NSLayoutConstraint!
    var phoneToolbarTopConstraint: NSLayoutConstraint!
    var phoneToolbarCompactPadTopConstraint: NSLayoutConstraint!
    var addressBarPhoneLeadingConstraint: NSLayoutConstraint!
    var addressBarPhoneTrailingFullConstraint: NSLayoutConstraint!
    var addressBarPhoneTrailingFocusedConstraint: NSLayoutConstraint!
    var addressBarPhoneTopConstraint: NSLayoutConstraint!
    var addressBarPhoneHeightConstraint: NSLayoutConstraint!
    var addressBarPadLeadingConstraint: NSLayoutConstraint!
    var addressBarPadTrailingConstraint: NSLayoutConstraint!
    var addressBarCompactPadLeadingConstraint: NSLayoutConstraint!
    var addressBarCompactPadTrailingConstraint: NSLayoutConstraint!
    var addressBarPadCenterYConstraint: NSLayoutConstraint!
    var addressBarPadHeightConstraint: NSLayoutConstraint!
    
    private unowned let controller: BrowserViewController
    private let tabCollectionHandler: TabCollectionHandler
    private var keyboardHeight: CGFloat = 0
    private var keyboardFrame: CGRect = .zero
    private var focusedInputBottomRatio: CGFloat?
    private var geckoPhoneVerticalOffset: CGFloat = 0
    private var focusedInputMetricsTask: Task<Void, Never>?
    
    init(
        controller: BrowserViewController,
        tabCollectionHandler: TabCollectionHandler
    ) {
        self.controller = controller
        self.tabCollectionHandler = tabCollectionHandler
        
        padTopBarButtons = PadTopBarButtons(controller: controller)
        tabBar = TabBar(tabCollectionHandler: tabCollectionHandler)
        tabOverviewCollection = TabOverviewCollection(
            overviewInset: controller.overviewInset,
            overviewSpacing: controller.overviewSpacing,
            tabCollectionHandler: tabCollectionHandler
        )
        tabOverviewBarButtons = TabOverviewBarButtons(controller: controller)
        
        addressBar.configure(delegate: controller)
        keyboardDismissButton.button.addTarget(controller, action: #selector(BrowserViewController.dismissKeyboardTapped), for: .touchUpInside)
        toolbarView.delegate = controller
    }
    
    deinit {
        focusedInputMetricsTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    func configureLayout() {
        let ui = controller.browserUI
        let view = controller.view!
        
        view.addSubview(ui.chromeContainer.bottomSafeAreaFillView)
        view.addSubview(ui.geckoView)
        view.addSubview(ui.chromeContainer.containerView)
        view.addSubview(ui.topBar.safeAreaFillView)
        ui.chromeContainer.containerView.addSubview(ui.addressBar)
        
        ui.chromeContainer.containerView.addSubview(ui.toolbarView)
        
        view.addSubview(ui.topBar.barView)
        ui.topBar.barView.addSubview(ui.topBar.contentView)
        ui.topBar.contentView.addSubview(ui.padTopBarButtons.leftStack)
        ui.topBar.contentView.addSubview(ui.padTopBarButtons.rightStack)
        
        setAddressBarHost(isPad: controller.usesPadChrome)
        setKeyboardDismissButtonHost(isPad: controller.usesPadChrome)
        
        ui.topBar.barView.addSubview(ui.tabBar.collectionView)
        
        view.addSubview(ui.tabOverview.containerView)
        ui.tabOverview.containerView.addSubview(ui.tabOverview.blurView)
        ui.tabOverview.containerView.addSubview(ui.tabOverviewCollection.collectionView)
        ui.tabOverview.containerView.addSubview(ui.tabOverviewBottomBar.safeAreaFillView)
        ui.tabOverview.containerView.addSubview(ui.tabOverviewBottomBar.barView)
        ui.tabOverview.containerView.addSubview(ui.tabOverviewTopBar.barView)
        ui.tabOverviewBarButtons.attach(to: ui.tabOverviewBottomBar.barView)
        
        ui.geckoTopPhoneConstraint = ui.geckoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ui.geckoTopPadConstraint = ui.geckoView.topAnchor.constraint(equalTo: ui.topBar.barView.bottomAnchor)
        ui.geckoBottomPhoneConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: ui.chromeContainer.containerView.topAnchor)
        ui.geckoBottomPhoneSearchPinnedConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -94)
        ui.geckoBottomPhoneKeyboardOverlayConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ui.geckoBottomPadConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ui.geckoBottomCompactPadConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: ui.chromeContainer.containerView.topAnchor)
        ui.geckoLeadingPhoneConstraint = ui.geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ui.geckoTrailingPhoneConstraint = ui.geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ui.geckoLeadingPadConstraint = ui.geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ui.geckoTrailingPadConstraint = ui.geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ui.geckoTopFullscreenConstraint = ui.geckoView.topAnchor.constraint(equalTo: view.topAnchor)
        ui.geckoBottomFullscreenConstraint = ui.geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        ui.phoneChromeBottomConstraint = ui.chromeContainer.containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ui.phoneChromeHeightConstraint = ui.chromeContainer.containerView.heightAnchor.constraint(equalToConstant: 94)
        ui.phoneToolbarHeightConstraint = ui.toolbarView.heightAnchor.constraint(equalToConstant: 30)
        ui.phoneToolbarTopConstraint = ui.toolbarView.topAnchor.constraint(equalTo: ui.addressBar.bottomAnchor, constant: 7)
        ui.phoneToolbarCompactPadTopConstraint = ui.toolbarView.topAnchor.constraint(equalTo: ui.chromeContainer.containerView.topAnchor, constant: 7)
        
        ui.addressBarPhoneLeadingConstraint = ui.addressBar.leadingAnchor.constraint(equalTo: ui.chromeContainer.containerView.leadingAnchor, constant: 12)
        ui.addressBarPhoneTrailingFullConstraint = ui.addressBar.trailingAnchor.constraint(equalTo: ui.chromeContainer.containerView.trailingAnchor, constant: -12)
        ui.addressBarPhoneTrailingFocusedConstraint = ui.addressBar.trailingAnchor.constraint(equalTo: ui.keyboardDismissButton.button.leadingAnchor, constant: -9)
        ui.addressBarPhoneTopConstraint = ui.addressBar.topAnchor.constraint(equalTo: ui.chromeContainer.containerView.topAnchor, constant: 8)
        ui.addressBarPhoneHeightConstraint = ui.addressBar.heightAnchor.constraint(equalToConstant: 42)
        
        ui.addressBarPadLeadingConstraint = ui.addressBar.leadingAnchor.constraint(equalTo: ui.padTopBarButtons.leftStack.trailingAnchor, constant: 12)
        ui.addressBarPadTrailingConstraint = ui.addressBar.trailingAnchor.constraint(equalTo: ui.padTopBarButtons.rightStack.leadingAnchor, constant: -12)
        ui.addressBarCompactPadLeadingConstraint = ui.addressBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12)
        ui.addressBarCompactPadTrailingConstraint = ui.addressBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ui.addressBarPadCenterYConstraint = ui.addressBar.centerYAnchor.constraint(equalTo: ui.topBar.contentView.centerYAnchor)
        ui.addressBarPadHeightConstraint = ui.addressBar.heightAnchor.constraint(equalToConstant: 38)
        
        ui.keyboardDismissButton.trailingPhoneConstraint = ui.keyboardDismissButton.button.trailingAnchor.constraint(equalTo: ui.chromeContainer.containerView.trailingAnchor, constant: -12)
        ui.keyboardDismissButton.trailingPadConstraint = ui.keyboardDismissButton.button.trailingAnchor.constraint(equalTo: ui.padTopBarButtons.rightStack.leadingAnchor, constant: -12)
        ui.keyboardDismissButton.trailingCompactPadConstraint = ui.keyboardDismissButton.button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ui.keyboardDismissButton.centerYConstraint = ui.keyboardDismissButton.button.centerYAnchor.constraint(equalTo: ui.addressBar.centerYAnchor)
        ui.keyboardDismissButton.widthConstraint = ui.keyboardDismissButton.button.widthAnchor.constraint(equalToConstant: 42)
        ui.keyboardDismissButton.heightConstraint = ui.keyboardDismissButton.button.heightAnchor.constraint(equalToConstant: 42)
        
        ui.topBar.heightConstraint = ui.topBar.barView.heightAnchor.constraint(equalToConstant: 52)
        ui.topBar.topConstraint = ui.topBar.barView.topAnchor.constraint(equalTo: view.topAnchor)
        ui.topBar.contentHeightConstraint = ui.topBar.contentView.heightAnchor.constraint(equalToConstant: 52)
        
        ui.padTopBarButtons.leftLeadingConstraint = ui.padTopBarButtons.leftStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12)
        ui.padTopBarButtons.rightTrailingConstraint = ui.padTopBarButtons.rightStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ui.padTopBarButtons.leftWidthConstraint = ui.padTopBarButtons.leftStack.widthAnchor.constraint(equalToConstant: 126)
        ui.padTopBarButtons.rightWidthConstraint = ui.padTopBarButtons.rightStack.widthAnchor.constraint(equalToConstant: 126)
        ui.padTopBarButtons.leftHeightConstraint = ui.padTopBarButtons.leftStack.heightAnchor.constraint(equalToConstant: 30)
        ui.padTopBarButtons.rightHeightConstraint = ui.padTopBarButtons.rightStack.heightAnchor.constraint(equalToConstant: 30)
        
        ui.tabBar.heightConstraint = ui.tabBar.collectionView.heightAnchor.constraint(equalToConstant: 36)
        
        ui.tabOverviewCollection.topPhoneConstraint = ui.tabOverviewCollection.collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ui.tabOverviewCollection.bottomPhoneConstraint = ui.tabOverviewCollection.collectionView.bottomAnchor.constraint(equalTo: ui.tabOverviewBottomBar.barView.topAnchor)
        ui.tabOverviewCollection.topPadConstraint = ui.tabOverviewCollection.collectionView.topAnchor.constraint(equalTo: ui.tabOverviewTopBar.barView.bottomAnchor)
        ui.tabOverviewCollection.bottomPadConstraint = ui.tabOverviewCollection.collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        
        ui.tabOverviewBottomBar.bottomConstraint = ui.tabOverviewBottomBar.barView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ui.tabOverviewBottomBar.heightConstraint = ui.tabOverviewBottomBar.barView.heightAnchor.constraint(equalToConstant: 108)
        ui.tabOverviewTopBar.heightConstraint = ui.tabOverviewTopBar.barView.heightAnchor.constraint(equalToConstant: 108)
        
        NSLayoutConstraint.activate([
            ui.geckoLeadingPhoneConstraint,
            ui.geckoTrailingPhoneConstraint,
            ui.geckoTopPhoneConstraint,
            ui.geckoBottomPhoneConstraint,
            
            ui.chromeContainer.containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.chromeContainer.containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.phoneChromeBottomConstraint,
            ui.phoneChromeHeightConstraint,
            
            ui.chromeContainer.bottomSafeAreaFillView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.chromeContainer.bottomSafeAreaFillView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.chromeContainer.bottomSafeAreaFillView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            ui.chromeContainer.bottomSafeAreaFillView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            ui.addressBarPhoneLeadingConstraint,
            ui.addressBarPhoneTrailingFullConstraint,
            ui.addressBarPhoneTopConstraint,
            ui.addressBarPhoneHeightConstraint,
            
            ui.keyboardDismissButton.trailingPhoneConstraint,
            ui.keyboardDismissButton.centerYConstraint,
            ui.keyboardDismissButton.widthConstraint,
            ui.keyboardDismissButton.heightConstraint,
            
            ui.toolbarView.leadingAnchor.constraint(equalTo: ui.chromeContainer.containerView.leadingAnchor, constant: 24),
            ui.toolbarView.trailingAnchor.constraint(equalTo: ui.chromeContainer.containerView.trailingAnchor, constant: -24),
            ui.phoneToolbarTopConstraint,
            ui.phoneToolbarHeightConstraint,
            
            ui.topBar.barView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.topBar.barView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.topBar.topConstraint,
            ui.topBar.heightConstraint,
            
            ui.topBar.contentView.leadingAnchor.constraint(equalTo: ui.topBar.barView.leadingAnchor),
            ui.topBar.contentView.trailingAnchor.constraint(equalTo: ui.topBar.barView.trailingAnchor),
            ui.topBar.contentView.topAnchor.constraint(equalTo: ui.topBar.barView.topAnchor),
            ui.topBar.contentHeightConstraint,
            
            ui.topBar.safeAreaFillView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.topBar.safeAreaFillView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.topBar.safeAreaFillView.topAnchor.constraint(equalTo: view.topAnchor),
            ui.topBar.safeAreaFillView.bottomAnchor.constraint(equalTo: ui.topBar.barView.topAnchor),
            
            ui.padTopBarButtons.leftLeadingConstraint,
            ui.padTopBarButtons.leftStack.centerYAnchor.constraint(equalTo: ui.topBar.contentView.centerYAnchor),
            ui.padTopBarButtons.leftWidthConstraint,
            ui.padTopBarButtons.leftHeightConstraint,
            
            ui.padTopBarButtons.rightTrailingConstraint,
            ui.padTopBarButtons.rightStack.centerYAnchor.constraint(equalTo: ui.topBar.contentView.centerYAnchor),
            ui.padTopBarButtons.rightWidthConstraint,
            ui.padTopBarButtons.rightHeightConstraint,
            
            ui.tabBar.collectionView.leadingAnchor.constraint(equalTo: ui.topBar.barView.leadingAnchor),
            ui.tabBar.collectionView.trailingAnchor.constraint(equalTo: ui.topBar.barView.trailingAnchor),
            ui.tabBar.collectionView.topAnchor.constraint(equalTo: ui.topBar.contentView.bottomAnchor),
            ui.tabBar.heightConstraint,
            
            ui.tabOverview.containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.tabOverview.containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.tabOverview.containerView.topAnchor.constraint(equalTo: view.topAnchor),
            ui.tabOverview.containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            ui.tabOverview.blurView.leadingAnchor.constraint(equalTo: ui.tabOverview.containerView.leadingAnchor),
            ui.tabOverview.blurView.trailingAnchor.constraint(equalTo: ui.tabOverview.containerView.trailingAnchor),
            ui.tabOverview.blurView.topAnchor.constraint(equalTo: ui.tabOverview.containerView.topAnchor),
            ui.tabOverview.blurView.bottomAnchor.constraint(equalTo: ui.tabOverview.containerView.bottomAnchor),
            
            ui.tabOverviewCollection.collectionView.leadingAnchor.constraint(equalTo: ui.tabOverview.containerView.safeAreaLayoutGuide.leadingAnchor),
            ui.tabOverviewCollection.collectionView.trailingAnchor.constraint(equalTo: ui.tabOverview.containerView.safeAreaLayoutGuide.trailingAnchor),
            ui.tabOverviewCollection.topPhoneConstraint,
            ui.tabOverviewCollection.bottomPhoneConstraint,
            
            ui.tabOverviewBottomBar.barView.leadingAnchor.constraint(equalTo: ui.tabOverview.containerView.leadingAnchor),
            ui.tabOverviewBottomBar.barView.trailingAnchor.constraint(equalTo: ui.tabOverview.containerView.trailingAnchor),
            ui.tabOverviewBottomBar.bottomConstraint,
            ui.tabOverviewBottomBar.heightConstraint,
            
            ui.tabOverviewBottomBar.safeAreaFillView.leadingAnchor.constraint(equalTo: ui.tabOverview.containerView.leadingAnchor),
            ui.tabOverviewBottomBar.safeAreaFillView.trailingAnchor.constraint(equalTo: ui.tabOverview.containerView.trailingAnchor),
            ui.tabOverviewBottomBar.safeAreaFillView.topAnchor.constraint(equalTo: ui.tabOverviewBottomBar.barView.bottomAnchor),
            ui.tabOverviewBottomBar.safeAreaFillView.bottomAnchor.constraint(equalTo: ui.tabOverview.containerView.bottomAnchor),
            
            ui.tabOverviewTopBar.barView.leadingAnchor.constraint(equalTo: ui.tabOverview.containerView.leadingAnchor),
            ui.tabOverviewTopBar.barView.trailingAnchor.constraint(equalTo: ui.tabOverview.containerView.trailingAnchor),
            ui.tabOverviewTopBar.barView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            ui.tabOverviewTopBar.heightConstraint,
        ].compactMap { $0 })
        
        ui.addressBarPadLeadingConstraint.isActive = false
        ui.addressBarPadTrailingConstraint.isActive = false
        ui.addressBarCompactPadLeadingConstraint.isActive = false
        ui.addressBarCompactPadTrailingConstraint.isActive = false
        ui.addressBarPadCenterYConstraint.isActive = false
        ui.addressBarPadHeightConstraint.isActive = false
        ui.phoneToolbarCompactPadTopConstraint.isActive = false
        ui.tabOverviewCollection.topPadConstraint.isActive = false
        ui.tabOverviewCollection.bottomPadConstraint.isActive = false
        ui.geckoBottomCompactPadConstraint.isActive = false
        ui.keyboardDismissButton.trailingPadConstraint.isActive = false
        ui.keyboardDismissButton.trailingCompactPadConstraint.isActive = false
        
        view.sendSubviewToBack(ui.chromeContainer.bottomSafeAreaFillView)
    }
    
    func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    func applyChromeLayout(animated: Bool) {
        updateChromeLayoutState()
        
        let layoutBlock = {
            self.controller.view.layoutIfNeeded()
            self.updatePhoneDismissKeyboardButtonShadowPath()
        }
        
        if animated {
            UIView.animate(withDuration: 0.22, animations: layoutBlock)
        } else {
            layoutBlock()
        }
    }
    
    private func updateChromeLayoutState() {
        let ui = controller.browserUI
        let pad = controller.usesPadChrome
        let compactPad = controller.usesCompactPadChrome
        let isInFullscreenMedia = controller.isInFullscreenMedia
        
        if isInFullscreenMedia {
            applyMediaFullscreenLayoutState()
            controller.updateNavigationButtons()
            return
        }
        
        setAddressBarHost(isPad: pad)
        setKeyboardDismissButtonHost(isPad: pad)
        ui.topBar.topConstraint.constant = resolvedPadTopInset()
        let shouldShowGeckoBehindKeyboard = !pad
        && controller.isSearchFocused
        && keyboardHeight > 0
        && !controller.tabOverviewPresentation.isVisible
        let shouldPinSearchFocusedGeckoFrame = !pad
        && controller.isSearchFocused
        && !controller.tabOverviewPresentation.isVisible
        let geckoPhoneOffset = resolvedGeckoPhoneVerticalOffset(
            shouldShowGeckoBehindKeyboard: shouldShowGeckoBehindKeyboard
        )
        let isLandscape: Bool
        if let orientation = controller.view.window?.windowScene?.interfaceOrientation {
            isLandscape = orientation.isLandscape
        } else {
            isLandscape = controller.view.bounds.width > controller.view.bounds.height
        }
        
        ui.geckoTopPhoneConstraint.constant = !pad ? -geckoPhoneOffset : 0
        ui.geckoBottomPhoneConstraint.constant = !pad ? -geckoPhoneOffset : 0
        ui.geckoBottomPhoneSearchPinnedConstraint.constant = -94
        ui.geckoBottomPhoneKeyboardOverlayConstraint.constant = 0
        ui.geckoTopPadConstraint.constant = pad ? -geckoPhoneOffset : 0
        ui.geckoBottomCompactPadConstraint.constant = pad && compactPad ? -geckoPhoneOffset : 0
        ui.geckoBottomPadConstraint.constant = pad && !compactPad ? -geckoPhoneOffset : 0
        
        ui.geckoTopPhoneConstraint.isActive = !pad
        ui.geckoBottomPhoneConstraint.isActive = !pad && !shouldPinSearchFocusedGeckoFrame && !shouldShowGeckoBehindKeyboard
        ui.geckoBottomPhoneSearchPinnedConstraint.isActive = shouldPinSearchFocusedGeckoFrame
        ui.geckoBottomPhoneKeyboardOverlayConstraint.isActive = shouldShowGeckoBehindKeyboard && !shouldPinSearchFocusedGeckoFrame
        ui.geckoLeadingPhoneConstraint.isActive = !pad
        ui.geckoTrailingPhoneConstraint.isActive = !pad
        ui.geckoTopPadConstraint.isActive = pad
        ui.geckoBottomPadConstraint.isActive = pad && !compactPad
        ui.geckoBottomCompactPadConstraint.isActive = compactPad
        ui.geckoLeadingPadConstraint.isActive = pad
        ui.geckoTrailingPadConstraint.isActive = pad
        ui.geckoTopFullscreenConstraint.isActive = false
        ui.geckoBottomFullscreenConstraint.isActive = false
        
        let phoneOverview = controller.usesBottomPhoneOverview
        ui.tabOverviewCollection.topPhoneConstraint.isActive = phoneOverview
        ui.tabOverviewCollection.bottomPhoneConstraint.isActive = phoneOverview
        ui.tabOverviewCollection.topPadConstraint.isActive = !phoneOverview
        ui.tabOverviewCollection.bottomPadConstraint.isActive = !phoneOverview
        
        let showsTabBar = pad && !controller.tabOverviewPresentation.isVisible && controller.tabManager.tabs.count > 1 && (!controller.isPad ? Prefs.AppearanceSettings.showsLandscapeTabBar && isLandscape : true)
        let showsCompactPadBottomToolbar = compactPad && !controller.tabOverviewPresentation.isVisible
        ui.topBar.barView.isHidden = !pad
        ui.topBar.safeAreaFillView.isHidden = !pad
        ui.tabBar.collectionView.isHidden = !showsTabBar
        ui.topBar.heightConstraint.constant = 52 + (showsTabBar ? 36 : 0)
        ui.tabBar.heightConstraint.constant = showsTabBar ? 36 : 0
        
        ui.chromeContainer.containerView.isHidden = (!showsCompactPadBottomToolbar && pad) || controller.tabOverviewPresentation.isVisible
        ui.chromeContainer.bottomSafeAreaFillView.isHidden = (!showsCompactPadBottomToolbar && pad) || controller.tabOverviewPresentation.isVisible
        ui.phoneChromeHeightConstraint.constant = compactPad ? 44 : (controller.isSearchFocused ? 58 : 94)
        ui.chromeContainer.containerView.backgroundColor = controller.isSearchFocused && !pad ? .clear : .systemGray6
        ui.chromeContainer.bottomSafeAreaFillView.backgroundColor = controller.isSearchFocused && !pad ? .clear : .systemGray6
        ui.toolbarView.alpha = compactPad ? 1 : ui.toolbarView.alpha
        
        ui.tabOverviewTopBar.barView.isHidden = phoneOverview
        ui.tabOverviewBottomBar.barView.isHidden = !phoneOverview
        ui.tabOverviewBottomBar.safeAreaFillView.isHidden = true
        ui.tabOverviewBarButtons.attach(to: phoneOverview ? ui.tabOverviewBottomBar.barView : ui.tabOverviewTopBar.barView)
        ui.padTopBarButtons.updateLayout(isPadLayout: controller.isPad, showsCompactPadChrome: compactPad, sidebarVisible: controller.isLibrarySidebarVisible)
        ui.padTopBarButtons.leftStack.isHidden = compactPad
        ui.padTopBarButtons.rightStack.isHidden = compactPad
        ui.padTopBarButtons.leftWidthConstraint.constant = compactPad ? 0 : resolvedPadTopBarLeftWidth(
            isPadLayout: controller.isPad,
            sidebarVisible: controller.isLibrarySidebarVisible,
            showsDownloads: ui.padTopBarButtons.downloadButton.isShowingDownloads
        )
        ui.padTopBarButtons.rightWidthConstraint.constant = compactPad ? 0 : 126
        
        let showDismissButton = controller.isSearchFocused && !controller.tabOverviewPresentation.isVisible
        ui.addressBarPhoneLeadingConstraint.isActive = !pad
        ui.addressBarPhoneTopConstraint.isActive = !pad
        ui.addressBarPhoneHeightConstraint.isActive = !pad
        ui.addressBarPhoneTrailingFullConstraint.isActive = !pad && !showDismissButton
        ui.addressBarPhoneTrailingFocusedConstraint.isActive = showDismissButton
        
        ui.addressBarPadLeadingConstraint.isActive = pad && !compactPad
        ui.addressBarPadTrailingConstraint.isActive = pad && !compactPad && !showDismissButton
        ui.addressBarCompactPadLeadingConstraint.isActive = pad && compactPad
        ui.addressBarCompactPadTrailingConstraint.isActive = pad && compactPad && !showDismissButton
        ui.addressBarPadCenterYConstraint.isActive = pad
        ui.addressBarPadHeightConstraint.isActive = pad
        ui.keyboardDismissButton.trailingPhoneConstraint.isActive = !pad
        ui.keyboardDismissButton.trailingPadConstraint.isActive = pad && !compactPad
        ui.keyboardDismissButton.trailingCompactPadConstraint.isActive = pad && compactPad
        
        ui.phoneToolbarTopConstraint.isActive = !pad && !compactPad
        ui.phoneToolbarCompactPadTopConstraint.isActive = compactPad
        ui.keyboardDismissButton.centerYConstraint.isActive = true
        
        ui.keyboardDismissButton.button.isHidden = !showDismissButton
        let dismissButtonSize = pad ? ui.addressBarPadHeightConstraint.constant : ui.addressBarPhoneHeightConstraint.constant
        ui.keyboardDismissButton.widthConstraint.constant = dismissButtonSize
        ui.keyboardDismissButton.heightConstraint.constant = dismissButtonSize
        ui.keyboardDismissButton.button.layer.cornerRadius = dismissButtonSize / 2
        ui.keyboardDismissButton.button.layer.shadowOpacity = pad ? 0 : 0.2
        ui.addressBar.setShadowEnabled(!pad)
        ui.addressBar.setHidePlaceholderIcon(controller.usesTopPhoneAddressBar || controller.usesPadChrome)
        
        controller.updateNavigationButtons()
    }
    
    private func applyMediaFullscreenLayoutState() {
        let ui = controller.browserUI
        let pad = controller.usesPadChrome
        
        setAddressBarHost(isPad: pad)
        setKeyboardDismissButtonHost(isPad: pad)
        ui.topBar.topConstraint.constant = resolvedPadTopInset()
        
        ui.geckoTopPhoneConstraint.isActive = false
        ui.geckoBottomPhoneConstraint.isActive = false
        ui.geckoBottomPhoneSearchPinnedConstraint.isActive = false
        ui.geckoBottomPhoneKeyboardOverlayConstraint.isActive = false
        ui.geckoTopPadConstraint.isActive = false
        ui.geckoBottomPadConstraint.isActive = false
        ui.geckoBottomCompactPadConstraint.isActive = false
        ui.geckoLeadingPhoneConstraint.isActive = !pad
        ui.geckoTrailingPhoneConstraint.isActive = !pad
        ui.geckoLeadingPadConstraint.isActive = pad
        ui.geckoTrailingPadConstraint.isActive = pad
        ui.geckoTopFullscreenConstraint.isActive = true
        ui.geckoBottomFullscreenConstraint.isActive = true
        
        ui.topBar.barView.isHidden = true
        ui.topBar.safeAreaFillView.isHidden = true
        ui.tabBar.collectionView.isHidden = true
        ui.topBar.heightConstraint.constant = 52
        ui.tabBar.heightConstraint.constant = 0
        
        ui.chromeContainer.containerView.isHidden = true
        ui.chromeContainer.bottomSafeAreaFillView.isHidden = true
        ui.phoneChromeBottomConstraint.constant = 0
        ui.chromeContainer.containerView.backgroundColor = .systemGray6
        ui.chromeContainer.bottomSafeAreaFillView.backgroundColor = .systemGray6
        
        ui.keyboardDismissButton.button.isHidden = true
        ui.keyboardDismissButton.button.alpha = 0
        ui.keyboardDismissButton.centerYConstraint.isActive = true
        ui.keyboardDismissButton.trailingPhoneConstraint.isActive = !pad
        ui.keyboardDismissButton.trailingPadConstraint.isActive = pad && !controller.usesCompactPadChrome
        ui.keyboardDismissButton.trailingCompactPadConstraint.isActive = pad && controller.usesCompactPadChrome
        
        ui.addressBarPhoneLeadingConstraint.isActive = !pad
        ui.addressBarPhoneTopConstraint.isActive = !pad
        ui.addressBarPhoneHeightConstraint.isActive = !pad
        ui.addressBarPhoneTrailingFullConstraint.isActive = !pad
        ui.addressBarPhoneTrailingFocusedConstraint.isActive = false
        ui.addressBarPadLeadingConstraint.isActive = pad && !controller.usesCompactPadChrome
        ui.addressBarPadTrailingConstraint.isActive = pad && !controller.usesCompactPadChrome
        ui.addressBarCompactPadLeadingConstraint.isActive = pad && controller.usesCompactPadChrome
        ui.addressBarCompactPadTrailingConstraint.isActive = pad && controller.usesCompactPadChrome
        ui.addressBarPadCenterYConstraint.isActive = pad
        ui.addressBarPadHeightConstraint.isActive = pad
        
        ui.tabOverviewTopBar.barView.isHidden = controller.usesBottomPhoneOverview
        ui.tabOverviewBottomBar.barView.isHidden = !controller.usesBottomPhoneOverview
        ui.tabOverviewBottomBar.safeAreaFillView.isHidden = true
        ui.padTopBarButtons.leftStack.isHidden = controller.usesCompactPadChrome
        ui.padTopBarButtons.rightStack.isHidden = controller.usesCompactPadChrome
        ui.phoneToolbarTopConstraint.isActive = !pad && !controller.usesCompactPadChrome
        ui.phoneToolbarCompactPadTopConstraint.isActive = controller.usesCompactPadChrome
        
        ui.toolbarView.alpha = 1
        ui.addressBar.setShadowEnabled(!pad)
        ui.addressBar.setHidePlaceholderIcon(controller.usesTopPhoneAddressBar || controller.usesPadChrome)
    }
    
    private func resolvedPadTopInset() -> CGFloat {
        guard controller.isPad,
              controller.splitViewController is BrowserSplitViewController else {
            return controller.view.safeAreaInsets.top
        }
        
        if let statusBarHeight = controller.view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
           statusBarHeight > 0 {
            return statusBarHeight
        }
        
        return 24
    }
    
    private func resolvedPadTopBarLeftWidth(isPadLayout: Bool, sidebarVisible: Bool, showsDownloads: Bool) -> CGFloat {
        guard isPadLayout else {
            return 126
        }
        
        let visibleButtonCount = (sidebarVisible ? 2 : 3) + (showsDownloads ? 1 : 0)
        let buttonWidth: CGFloat = 30
        let spacing: CGFloat = 10
        return (CGFloat(visibleButtonCount) * buttonWidth) + (CGFloat(max(visibleButtonCount - 1, 0)) * spacing)
    }
    
    func setSearchFocused(_ focused: Bool, animated: Bool) {
        let ui = controller.browserUI
        let usesPadChrome = controller.usesPadChrome
        
        controller.isSearchFocused = focused
        if focused {
            resetFocusedInputRelocation()
        }
        if !usesPadChrome {
            ui.phoneToolbarHeightConstraint.constant = focused ? 0 : 30
            ui.phoneChromeHeightConstraint.constant = focused ? 58 : 94
            ui.chromeContainer.containerView.backgroundColor = focused ? .clear : .systemGray6
            ui.chromeContainer.bottomSafeAreaFillView.backgroundColor = focused ? .clear : .systemGray6
        }
        updateChromeLayoutState()
        
        let dismissButtonTargetAlpha: CGFloat = focused ? 1 : 0
        if focused {
            ui.keyboardDismissButton.button.isHidden = false
        }
        
        let animations = {
            if !usesPadChrome {
                ui.toolbarView.alpha = focused ? 0 : 1
            }
            ui.keyboardDismissButton.button.alpha = dismissButtonTargetAlpha
            self.controller.view.layoutIfNeeded()
            self.updatePhoneDismissKeyboardButtonShadowPath()
        }
        
        let completion: (Bool) -> Void = { _ in
            if !focused {
                ui.keyboardDismissButton.button.isHidden = true
            }
        }
        
        if animated {
            UIView.animate(withDuration: 0.2, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }
    
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        
        let ui = controller.browserUI
        updateKeyboardState(screenFrame: frameValue.cgRectValue)
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveRaw = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let curve = UIView.AnimationOptions(rawValue: curveRaw << 16)
        requestFocusedInputMetricsIfNeeded(duration: duration, curve: curve)
        
        let shouldDockChromeToKeyboard = !controller.usesPadChrome
        && controller.isSearchFocused
        && !controller.tabOverviewPresentation.isVisible
        && keyboardHeight > 0
        ui.phoneChromeBottomConstraint.constant = shouldDockChromeToKeyboard ? -keyboardHeight : 0
        updateChromeLayoutState()
        
        UIView.animate(withDuration: duration, delay: 0, options: [curve]) {
            self.controller.view.layoutIfNeeded()
            self.updatePhoneDismissKeyboardButtonShadowPath()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        let ui = controller.browserUI
        
        keyboardHeight = 0
        keyboardFrame = .zero
        resetFocusedInputRelocation()
        ui.phoneChromeBottomConstraint.constant = 0
        updateChromeLayoutState()
        
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let curve = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: [curve]) {
            self.controller.view.layoutIfNeeded()
            self.updatePhoneDismissKeyboardButtonShadowPath()
        }
    }
    
    private func updatePhoneDismissKeyboardButtonShadowPath() {
        let button = controller.browserUI.keyboardDismissButton.button
        guard !controller.usesPadChrome else {
            button.layer.shadowPath = nil
            return
        }
        guard button.bounds.width > 1, button.bounds.height > 1 else {
            button.layer.shadowPath = nil
            return
        }
        button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
    }
    
    private func updateKeyboardState(screenFrame: CGRect) {
        keyboardFrame = controller.view.convert(screenFrame, from: nil)
        let overlap = max(0, controller.view.bounds.maxY - keyboardFrame.minY)
        let safeBottom = controller.view.safeAreaInsets.bottom
        keyboardHeight = max(0, overlap - safeBottom)
    }
    
    private func setAddressBarHost(isPad: Bool) {
        let ui = controller.browserUI
        let targetHost = isPad ? ui.topBar.contentView : ui.chromeContainer.containerView
        guard ui.addressBar.superview !== targetHost else {
            return
        }
        
        ui.addressBar.removeFromSuperview()
        targetHost.addSubview(ui.addressBar)
    }
    
    private func setKeyboardDismissButtonHost(isPad: Bool) {
        let ui = controller.browserUI
        let targetHost = isPad ? ui.topBar.contentView : ui.chromeContainer.containerView
        guard ui.keyboardDismissButton.button.superview !== targetHost else {
            return
        }
        
        ui.keyboardDismissButton.button.removeFromSuperview()
        targetHost.addSubview(ui.keyboardDismissButton.button)
    }
    
    private func requestFocusedInputMetricsIfNeeded(duration: TimeInterval, curve: UIView.AnimationOptions) {
        guard !controller.isSearchFocused,
              !controller.tabOverviewPresentation.isVisible,
              keyboardHeight > 0,
              let session = controller.tabManager.selectedTab?.session else {
            focusedInputBottomRatio = nil
            applyFocusedInputRelocation(duration: duration, curve: curve)
            return
        }
        
        focusedInputMetricsTask?.cancel()
        focusedInputMetricsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            let bottomRatio = await session.focusedInputBottomRatio()
            guard !Task.isCancelled else {
                return
            }
            
            if let bottomRatio {
                self.focusedInputBottomRatio = bottomRatio
            }
            self.applyFocusedInputRelocation(duration: duration, curve: curve)
        }
    }
    
    private func applyFocusedInputRelocation(duration: TimeInterval, curve: UIView.AnimationOptions) {
        let nextOffset = resolvedGeckoPhoneVerticalOffset(
            shouldShowGeckoBehindKeyboard: false
        )
        guard abs(nextOffset - geckoPhoneVerticalOffset) > 0.5 else {
            return
        }
        
        geckoPhoneVerticalOffset = nextOffset
        updateChromeLayoutState()
        UIView.animate(withDuration: duration, delay: 0, options: [curve, .beginFromCurrentState, .allowUserInteraction]) {
            self.controller.view.layoutIfNeeded()
            self.updatePhoneDismissKeyboardButtonShadowPath()
        }
    }
    
    private func resetFocusedInputRelocation() {
        focusedInputMetricsTask?.cancel()
        focusedInputMetricsTask = nil
        focusedInputBottomRatio = nil
        geckoPhoneVerticalOffset = 0
    }
    
    private func resolvedGeckoPhoneVerticalOffset(
        shouldShowGeckoBehindKeyboard: Bool
    ) -> CGFloat {
        guard !controller.isSearchFocused,
              !controller.tabOverviewPresentation.isVisible,
              !shouldShowGeckoBehindKeyboard,
              keyboardHeight > 0,
              let bottomRatio = focusedInputBottomRatio else {
            return 0
        }
        
        controller.view.layoutIfNeeded()
        let geckoFrame = controller.browserUI.geckoView.frame
        guard geckoFrame.height > 1 else {
            return 0
        }
        
        let unshiftedGeckoMinY: CGFloat
        if controller.usesPadChrome {
            unshiftedGeckoMinY = controller.browserUI.topBar.barView.frame.maxY
        } else {
            unshiftedGeckoMinY = controller.view.safeAreaLayoutGuide.layoutFrame.minY
        }
        
        let currentGeckoShift = max(0, unshiftedGeckoMinY - geckoFrame.minY)
        let unshiftedGeckoMaxY = geckoFrame.maxY + currentGeckoShift
        let keyboardOverlap = max(0, unshiftedGeckoMaxY - keyboardFrame.minY)
        guard keyboardOverlap > 0 else {
            return 0
        }
        
        let focusBottom = geckoFrame.height * bottomRatio
        let visibleBottom = max(0, geckoFrame.height - keyboardOverlap - 12)
        return min(keyboardOverlap, max(0, focusBottom - visibleBottom))
    }
}
