//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

struct BrowserLayout: Equatable {
    enum Orientation: Equatable {
        case portrait
        case landscape
    }

    let interfaceIdiom: UIUserInterfaceIdiom
    let orientation: Orientation
    let browserChromeMode: browserChromeMode
    let browserChromePosition: browserChromePosition
    let tabOverviewToolbarPosition: TabOverview.ToolbarPosition
    let overlayContentPlacement: SearchOverlayPlacement

    static func initial(interfaceIdiom: UIUserInterfaceIdiom) -> BrowserLayout {
        BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: .portrait,
            browserChromeMode: interfaceIdiom == .pad ? .pad : .phone,
            browserChromePosition: .bottom,
            tabOverviewToolbarPosition: interfaceIdiom == .pad ? .top : .bottom,
            overlayContentPlacement: interfaceIdiom == .pad ? .detached : .embedded
        )
    }
}

final class BrowserViewController: UIViewController {
    // MARK: - UX

    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.22
        static let fallbackTopInset: CGFloat = 24
        static let keyboardAnimationDuration: TimeInterval = 0.25
        static let keyboardAnimationCurve: UInt = 7
    }

    private struct KeyboardAnimation {
        let duration: TimeInterval
        let curve: UIView.AnimationOptions
    }

    // MARK: - State

    lazy var tabManager: TabManager = TabManagerImplementation(delegate: self)
    private var orientationBeforeFullscreen: UIInterfaceOrientation?
    weak var activeFullscreenSession: GeckoSession?
    private let canHostSidebar: Bool
    private(set) var browserLayout = BrowserLayout.initial(
        interfaceIdiom: UIDevice.current.userInterfaceIdiom
    )

    // MARK: - Views And Coordinators

    let contentView = ContentView()
    lazy var browserChrome = BrowserChrome(controller: self)
    lazy var overlayCoordinator = OverlayCoordinator(controller: self)
    lazy var searchOverlayCoordinator = SearchOverlayCoordinator(
        controller: self,
        overlayCoordinator: overlayCoordinator
    )
    lazy var contextMenuCoordinator = ContextMenuCoordinator(browserViewController: self)
    let tabBar = TabBar()
    let tabOverview = TabOverview()
    lazy var sidebarCoordinator = SidebarCoordinator(
        browserViewController: self,
        canHostSidebar: canHostSidebar
    )
    
    private(set) var isInFullscreenMedia = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return isInFullscreenMedia
    }
    
    override var childForStatusBarHidden: UIViewController? {
        sidebarCoordinator.statusBarController
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if isInFullscreenMedia && browserLayout.interfaceIdiom == .phone {
            return .landscape
        }

        return browserLayout.interfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if isInFullscreenMedia && browserLayout.interfaceIdiom == .phone {
            return .landscapeRight
        }

        return .portrait
    }
    
    init(canHostSidebar: Bool = true) {
        self.canHostSidebar = canHostSidebar
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if isInFullscreenMedia {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        if sidebarCoordinator.installHostIfNeeded() {
            return
        }
        
        observeNotifications()
        contextMenuCoordinator.configure()
        observeDownloadState()
        syncDownloadButtonState()
        configureBrowserInterface()
        tabOverview.restoreMode(TabOverview.Mode(tabMode: TabManagementStore.shared.restoredTabMode()))
        syncBrowserNavigationChrome(animated: false)
        browserChrome.syncSidebarButton(splitViewController: splitViewController)
        applyUpdateMenuButtonBadge()
        
        tabManager.createInitialTab()
        refreshAddressBar()
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            SitePermissionController.shared.attach(controller: self)
            SitePermissionController.shared.start()
            await self.addonController.start()
            self.tabManager.selectedTab?.session.setAddonTabActive(true)
        }
        
        updateBrowserLayout(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        performContentLifecycle {
            syncBrowserNavigationChrome(animated: animated)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        performContentLifecycle {
            view.endEditing(true)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performContentLifecycle {
            syncBrowserNavigationChrome(animated: false)
            browserChrome.syncSidebarButton(splitViewController: splitViewController)
            syncDownloadButtonState()
            updateBrowserLayout(animated: false)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if sidebarCoordinator.refreshHostVisibility() {
            return
        }
        syncBrowserNavigationChrome(animated: false)
        browserChrome.syncSidebarButton(splitViewController: splitViewController)
        refreshAddressBar()
        updateBrowserLayout(animated: false)
        tabOverview.invalidateCollectionLayouts()
        tabBar.invalidateLayout()
        tabOverview.refreshForCurrentOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        performContentLifecycle {
            coordinator.animate { _ in
                self.syncBrowserNavigationChrome(animated: false)
                self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
                self.tabOverview.invalidateCollectionLayouts()
                self.tabBar.invalidateLayout()
            } completion: { _ in
                self.syncBrowserNavigationChrome(animated: false)
                self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
                self.contentView.setTransitionTransform(.identity)
                self.browserChrome.resetHorizontalTransition()
                self.tabOverview.refreshForCurrentOrientation()
                DispatchQueue.main.async {
                    guard self.isViewLoaded, self.view.window != nil else {
                        return
                    }
                    self.updateBrowserLayout(animated: false)
                }
            }
        }
    }
    
    // MARK: - Browser Layout

    private func configureBrowserInterface() {
        browserChrome.configureAddressBarSearchDelegate(searchOverlayCoordinator)
        tabBar.tabManager = tabManager
        tabOverview.configure(browserViewController: self)

        view.addSubview(contentView)
        view.addSubview(tabBar)
        view.addSubview(browserChrome)
        view.addSubview(tabOverview)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).withPriority(.defaultHigh),
            contentView.bottomAnchor.constraint(equalTo: browserChrome.bottomToolbarTopAnchor).withPriority(.defaultHigh),

            browserChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserChrome.topAnchor.constraint(equalTo: view.topAnchor),
            browserChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: browserChrome.topToolbarBottomAnchor),

            tabOverview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabOverview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabOverview.topAnchor.constraint(equalTo: view.topAnchor),
            tabOverview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func updateBrowserLayout(
        animated: Bool,
        duration: TimeInterval = UX.layoutAnimationDuration
    ) {
        if sidebarCoordinator.hostsSidebar {
            sidebarCoordinator.contentBrowser.updateBrowserLayout(
                animated: animated,
                duration: duration
            )
            return
        }

        browserLayout = resolveBrowserLayout()
        applyBrowserLayout()
        searchOverlayCoordinator.updateLayoutIfNeeded()

        let layoutBlock = {
            self.view.layoutIfNeeded()
            self.tabOverview.collection.applyPresentationTransforms()
        }

        animated
            ? UIView.animate(withDuration: duration, animations: layoutBlock)
            : layoutBlock()
    }

    func applyBrowserLayout() {
        if isInFullscreenMedia {
            applyFullscreenLayout()
        } else {
            switch browserLayout.browserChromeMode {
            case .phone:
                applyPhoneLayout()
            case .compact:
                applyCompactLayout()
            case .pad:
                applyPadLayout()
            }
        }

        applyTabOverviewLayout()
        applyBrowserChromeLayout()
        updateNavigationButtons()
    }

    private func applyFullscreenLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .fullscreen),
            topAnchor: view.topAnchor,
            bottomAnchor: view.bottomAnchor
        )
        tabBar.setVisibility(.hidden, animated: false)
    }

    private func applyPhoneLayout() {
        let isSearchFocused = searchOverlayCoordinator.isFocused && !tabOverview.isPresented
        contentView.applyLayout(
            ContentView.LayoutState(mode: isSearchFocused ? .searchFocused : .standard),
            topAnchor: view.safeAreaLayoutGuide.topAnchor,
            bottomAnchor: isSearchFocused
                ? view.safeAreaLayoutGuide.bottomAnchor
                : browserChrome.bottomToolbarTopAnchor
        )
        setTabBarVisible(false)
    }

    private func applyCompactLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: tabBar.bottomAnchor,
            bottomAnchor: browserChrome.bottomToolbarTopAnchor
        )
        setTabBarVisible(
            browserLayout.interfaceIdiom == .pad && activeTabCount > 1
        )
    }

    private func applyPadLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: tabBar.bottomAnchor,
            bottomAnchor: view.bottomAnchor
        )
        let showsTabBar = browserLayout.interfaceIdiom == .pad
            ? activeTabCount > 1
            : activeTabCount > 1 && Prefs.AppearanceSettings.showsLandscapeTabBar
        setTabBarVisible(showsTabBar)
    }

    private var activeTabCount: Int {
        let tabs = tabManager.selectedTabMode == .private
            ? tabManager.privateTabs
            : tabManager.regularTabs
        return tabs.count
    }

    private func setTabBarVisible(_ visible: Bool) {
        tabBar.setVisibility(
            visible ? (tabOverview.isPresented ? .layoutReserved : .visible) : .hidden,
            animated: false
        )
    }

    private func applyTabOverviewLayout() {
        tabOverview.applyLayout(
            toolbarPosition: browserLayout.tabOverviewToolbarPosition,
            animated: false
        )
    }

    private func applyBrowserChromeLayout() {
        browserChrome.apply(state: BrowserChrome.State(
            position: browserLayout.browserChromePosition,
            mode: browserLayout.browserChromeMode,
            presentation: isInFullscreenMedia
                ? .fullscreenMedia
                : (tabOverview.isPresented ? .tabOverview : .browsing),
            search: isInFullscreenMedia ? .inactive : searchOverlayCoordinator.chromeState,
            topInset: browserTopInset(),
            interfaceIdiom: browserLayout.interfaceIdiom,
            sidebarVisible: sidebarCoordinator.isVisible
        ))
    }

    private func resolveBrowserLayout() -> BrowserLayout {
        let interfaceIdiom = traitCollection.userInterfaceIdiom
        let orientation = currentBrowserOrientation()

        if interfaceIdiom == .pad {
            return traitCollection.horizontalSizeClass == .compact
                ? resolveCompactLayout(interfaceIdiom: .pad, orientation: orientation)
                : resolvePadLayout(interfaceIdiom: .pad, orientation: orientation)
        }

        guard orientation == .portrait else {
            return resolvePadLayout(interfaceIdiom: .phone, orientation: .landscape)
        }

        return Prefs.AppearanceSettings.addressBarPosition == .top
            ? resolveCompactLayout(interfaceIdiom: .phone, orientation: .portrait)
            : resolvePhoneLayout()
    }

    private func currentBrowserOrientation() -> BrowserLayout.Orientation {
        if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
           interfaceOrientation != .unknown {
            return interfaceOrientation.isLandscape ? .landscape : .portrait
        }

        return view.bounds.width > view.bounds.height ? .landscape : .portrait
    }

    private func resolvePhoneLayout() -> BrowserLayout {
        BrowserLayout(
            interfaceIdiom: .phone,
            orientation: .portrait,
            browserChromeMode: .phone,
            browserChromePosition: .bottom,
            tabOverviewToolbarPosition: .bottom,
            overlayContentPlacement: .embedded
        )
    }

    private func resolveCompactLayout(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: BrowserLayout.Orientation
    ) -> BrowserLayout {
        BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            browserChromeMode: .compact,
            browserChromePosition: interfaceIdiom == .phone ? .top : .bottom,
            tabOverviewToolbarPosition: interfaceIdiom == .phone ? .bottom : .top,
            overlayContentPlacement: .embedded
        )
    }

    private func resolvePadLayout(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: BrowserLayout.Orientation
    ) -> BrowserLayout {
        BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            browserChromeMode: .pad,
            browserChromePosition: .bottom,
            tabOverviewToolbarPosition: .top,
            overlayContentPlacement: .detached
        )
    }

    private func browserTopInset() -> CGFloat {
        sidebarCoordinator.topInset(fallback: UX.fallbackTopInset)
    }

    // MARK: - Sidebar

    @objc func librarySidebarTapped() {
        sidebarCoordinator.toggle(animated: true)
    }

    private func performContentLifecycle(_ action: () -> Void) {
        guard !sidebarCoordinator.hostsSidebar else {
            return
        }

        action()
    }

    // MARK: - Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBarPositionDidChange),
            name: .addressBarPositionDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(landscapeTabBarDidChange),
            name: .landscapeTabBarDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyUpdateMenuButtonBadge),
            name: .appUpdateAvailable,
            object: nil
        )
    }

    // MARK: - Keyboard

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let keyboardInset = max(
            0,
            view.bounds.maxY - keyboardFrame.minY - view.safeAreaInsets.bottom
        )
        let animation = keyboardAnimation(from: notification)
        if !searchOverlayCoordinator.isFocused && !tabOverview.isPresented && keyboardInset > 0 {
            contentView.relocateFocusedInput(
                above: keyboardFrame,
                animationDuration: animation.duration,
                animationOptions: animation.curve
            )
        } else {
            contentView.resetFocusedInputRelocation(
                animationDuration: animation.duration,
                animationOptions: animation.curve
            )
        }

        let shouldDockChrome = browserLayout.browserChromeMode == .phone
            && searchOverlayCoordinator.isFocused
            && !tabOverview.isPresented
            && keyboardInset > 0
        browserChrome.dockAddressBar(offset: shouldDockChrome ? -keyboardInset : 0)
        animateLayout(animation)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let animation = keyboardAnimation(from: notification)
        contentView.resetFocusedInputRelocation(
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
        browserChrome.dockAddressBar(offset: 0)
        animateLayout(animation)
    }

    private func keyboardAnimation(from notification: Notification) -> KeyboardAnimation {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            ?? UX.keyboardAnimationDuration
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UX.keyboardAnimationCurve
        return KeyboardAnimation(
            duration: duration,
            curve: UIView.AnimationOptions(rawValue: rawCurve << 16)
        )
    }

    private func animateLayout(_ animation: KeyboardAnimation) {
        UIView.animate(withDuration: animation.duration, delay: 0, options: [animation.curve]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc func addressBarPositionDidChange() {
        updateBrowserLayout(animated: true)
    }

    @objc func landscapeTabBarDidChange() {
        updateBrowserLayout(animated: true)
    }

    @objc func applyUpdateMenuButtonBadge() {
        browserChrome.setMenuButtonIndicatesUpdate(AppUpdates.shared.hasUpdate)
    }

    // MARK: - Browser UI Updates

    func syncBrowserNavigationChrome(animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }

    func updateNavigationButtons() {
        guard let tab = tabManager.selectedTab else {
            return
        }

        browserChrome.updateNavigation(
            canGoBack: tab.state.navigationState.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            canShare: tabManager.shareableURL(for: tab) != nil
        )
    }

    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let displayText: String?
        if case let .pending(text) = selectedTab?.state.displayState {
            displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            displayText = nil
        }
        let selectedURL = selectedTab?.url
        browserChrome.setAddressBarText(
            displayText?.isEmpty == false ? displayText : selectedURL,
            locationText: selectedURL,
            locationTitle: selectedTab?.title,
            showsBarMenu: displayText?.isEmpty != false && selectedURL?.isEmpty == false
        )
        browserChrome.setAddressBarLoadingProgress(
            selectedTab?.state.loadingState.progress ?? 0,
            isLoading: selectedTab?.state.loadingState.isLoading ?? false
        )
        addonController.prepareVisibleAddonIcons()
        browserChrome.updateAddressBarMenu(selectedTab: selectedTab, url: selectedURL)
    }

    func tabPreviewAspectRatio() -> CGFloat {
        let width = max(contentView.bounds.width, 1)
        return max(contentView.bounds.height, 1) / width
    }

    func captureThumbnail(for index: Int) {
        guard !contentView.isHidden,
              let tab = tabManager.activeTabs[safe: index],
              contentView.isDisplaying(session: tab.session),
              let image = contentView.makeThumbnail() else {
            return
        }
        tabManager.updateThumbnail(image, forTabAt: index)
    }

    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        if visible {
            contentView.resetFocusedInputRelocation()
            searchOverlayCoordinator.tabOverviewWillPresent()
        }
        tabOverview.setPresented(visible, animated: animated)
    }
    
    func applyFullscreenState(_ fullScreen: Bool, for session: GeckoSession?) {
        if fullScreen {
            activeFullscreenSession = session
        } else if activeFullscreenSession === session || session == nil {
            activeFullscreenSession = nil
        }
        
        guard isInFullscreenMedia != fullScreen else {
            return
        }
        
        if fullScreen {
            if tabOverview.isPresented {
                tabOverview.setPresented(false, animated: false)
            }
            searchOverlayCoordinator.setFocused(false, animated: false)
            view.endEditing(true)
        }
        
        isInFullscreenMedia = fullScreen
        updateBrowserLayout(animated: true)
        updateFullscreenOrientation(fullScreen)
        UIApplication.shared.isIdleTimerDisabled = fullScreen
    }
    
    private func updateFullscreenOrientation(_ fullScreen: Bool) {
        guard browserLayout.interfaceIdiom == .phone else {
            return
        }
        
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        
        if fullScreen {
            if let currentOrientation = view.window?.windowScene?.interfaceOrientation,
               currentOrientation != .unknown {
                orientationBeforeFullscreen = currentOrientation
            } else if orientationBeforeFullscreen == nil {
                orientationBeforeFullscreen = .portrait
            }
            
            let targetOrientation: UIInterfaceOrientation
            if let currentOrientation = view.window?.windowScene?.interfaceOrientation,
               currentOrientation.isLandscape {
                targetOrientation = currentOrientation
            } else {
                targetOrientation = .landscapeRight
            }
            forceInterfaceOrientation(targetOrientation)
        } else {
            let targetOrientation = orientationBeforeFullscreen ?? .portrait
            forceInterfaceOrientation(targetOrientation)
            orientationBeforeFullscreen = nil
        }
    }
    
    private func forceInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        let orientationMask: UIInterfaceOrientationMask
        switch orientation {
        case .portrait:
            orientationMask = .portrait
        case .portraitUpsideDown:
            orientationMask = .portraitUpsideDown
        case .landscapeLeft:
            orientationMask = .landscapeLeft
        case .landscapeRight:
            orientationMask = .landscapeRight
        default:
            return
        }
        
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else {
                return
            }
            
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientationMask)
            windowScene.requestGeometryUpdate(geometryPreferences)
            UIViewController.attemptRotationToDeviceOrientation()
            return
        }
        
        let deviceOrientation: UIDeviceOrientation
        switch orientation {
        case .portrait:
            deviceOrientation = .portrait
        case .portraitUpsideDown:
            deviceOrientation = .portraitUpsideDown
        case .landscapeLeft:
            deviceOrientation = .landscapeRight
        case .landscapeRight:
            deviceOrientation = .landscapeLeft
        default:
            return
        }
        
        UIDevice.current.setValue(deviceOrientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
