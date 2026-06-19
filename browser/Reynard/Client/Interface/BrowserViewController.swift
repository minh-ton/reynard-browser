//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController {
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
    
    let sessionManager = SessionManager()
    lazy var tabManager: TabManager = TabManagerImplementation(
        delegate: self,
        sessionManager: sessionManager
    )
    private var preFullscreenOrientation: UIInterfaceOrientation?
    weak var fullscreenSession: GeckoSession?
    private let allowsSidebarHosting: Bool
    private(set) var browserLayout = BrowserLayout.initial(
        interfaceIdiom: UIDevice.current.userInterfaceIdiom
    )
    
    // MARK: - Views And Coordinators
    
    let tabBar = TabBar()
    let tabOverview = TabOverview()
    let contentView = ContentView()
    lazy var browserChrome = BrowserChrome()
    
    lazy var overlayCoordinator = OverlayCoordinator(host: self)
    lazy var searchOverlayCoordinator = SearchOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator
    )
    lazy var contextMenuCoordinator = ContextMenuCoordinator(host: self, sessionManager: sessionManager)
    lazy var downloadsCoordinator = DownloadsCoordinator(delegate: self)
    lazy var sidebarCoordinator = SidebarCoordinator(
        host: self,
        canHostSidebar: allowsSidebarHosting
    )
    lazy var addonCoordinator = AddonCoordinator(
        dataSource: self,
        delegate: self,
        sessionManager: sessionManager
    )
    
    private(set) var isShowingFullscreenMedia = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    // MARK: - Lifecycle
    
    override var prefersStatusBarHidden: Bool {
        return isShowingFullscreenMedia
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return sidebarCoordinator.statusBarController
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if isShowingFullscreenMedia && browserLayout.interfaceIdiom == .phone {
            return .landscape
        }
        
        return browserLayout.interfaceIdiom == .pad ? .all : .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if isShowingFullscreenMedia && browserLayout.interfaceIdiom == .phone {
            return .landscapeRight
        }
        
        return .portrait
    }
    
    init(canHostSidebar: Bool = true) {
        self.allowsSidebarHosting = canHostSidebar
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if isShowingFullscreenMedia {
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
        
        configureBrowserInterface()
        observeNotifications()
        contextMenuCoordinator.configure()
        downloadsCoordinator.startObservingStore()
        downloadsCoordinator.syncToolbarButtonState()
        tabOverview.restoreMode(TabOverview.Mode(tabMode: TabManagementStore.shared.preferredRestoredMode()))
        syncBrowserNavigationChrome(animated: false)
        browserChrome.syncSidebarButton(splitViewController: splitViewController)
        applyUpdateMenuButtonBadge()
        
        tabManager.createInitialTab()
        refreshAddressBar()
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            await self.addonCoordinator.start()
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
            downloadsCoordinator.syncToolbarButtonState()
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
        browserChrome.configureAddressBar(
            delegate: self,
            searchDelegate: searchOverlayCoordinator,
            gestureDelegate: self
        )
        configureBrowserChromeActions()
        tabBar.dataSource = self
        tabOverview.configure(dataSource: self, delegate: self, presentationContext: self)
        
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
    
    private func configureBrowserChromeActions() {
        browserChrome.onSidebar = { [weak self] in
            self?.sidebarCoordinator.toggle(animated: true)
        }
        browserChrome.onBack = { [weak self] in
            self?.tabManager.goBack()
        }
        browserChrome.onForward = { [weak self] in
            self?.tabManager.goForward()
        }
        browserChrome.onShare = { [weak self] in
            self?.presentShareSheet()
        }
        browserChrome.onLibrary = { [weak self] in
            self?.presentLibrary()
        }
        browserChrome.onDownloads = { [weak self] in
            self?.presentLibrary(initialSection: .downloads)
        }
        browserChrome.onNewTab = { [weak self] in
            self?.createNewTab()
        }
        browserChrome.onTabOverview = { [weak self] in
            self?.setTabOverviewVisible(true, animated: true)
        }
    }
    
    func updateBrowserLayout(
        animated: Bool,
        duration: TimeInterval = UX.layoutAnimationDuration
    ) {
        if sidebarCoordinator.hostsSidebar {
            sidebarCoordinator.updateContentLayout(
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
        if isShowingFullscreenMedia {
            applyFullscreenLayout()
        } else {
            switch browserLayout.chromeMode {
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
            browserLayout.interfaceIdiom == .pad && visibleTabCount > 1
        )
    }
    
    private func applyPadLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: tabBar.bottomAnchor,
            bottomAnchor: view.bottomAnchor
        )
        let showsTabBar = browserLayout.interfaceIdiom == .pad
        ? visibleTabCount > 1
        : visibleTabCount > 1 && Prefs.AppearanceSettings.showsLandscapeTabBar
        setTabBarVisible(showsTabBar)
    }
    
    private var visibleTabCount: Int {
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
            position: browserLayout.chromePosition,
            mode: browserLayout.chromeMode,
            presentation: isShowingFullscreenMedia
            ? .fullscreenMedia
            : (tabOverview.isPresented ? .tabOverview : .browsing),
            search: isShowingFullscreenMedia ? .inactive : searchOverlayCoordinator.chromeState,
            topInset: browserTopInset(),
            interfaceIdiom: browserLayout.interfaceIdiom,
            sidebarButtonVisible: sidebarCoordinator.showChromeSidebarButton
        ))
    }
    
    private func resolveBrowserLayout() -> BrowserLayout {
        let interfaceIdiom = traitCollection.userInterfaceIdiom
        let orientation = currentViewportOrientation()
        
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
    
    private func currentViewportOrientation() -> BrowserLayout.ViewportOrientation {
        if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
           interfaceOrientation != .unknown {
            return interfaceOrientation.isLandscape ? .landscape : .portrait
        }
        
        return view.bounds.width > view.bounds.height ? .landscape : .portrait
    }
    
    private func resolvePhoneLayout() -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: .phone,
            orientation: .portrait,
            chromeMode: .phone,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: .bottom,
            overlayHost: .embedded
        )
    }
    
    private func resolveCompactLayout(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: BrowserLayout.ViewportOrientation
    ) -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            chromeMode: .compact,
            chromePosition: interfaceIdiom == .phone ? .top : .bottom,
            tabOverviewToolbarPosition: interfaceIdiom == .phone ? .bottom : .top,
            overlayHost: .embedded
        )
    }
    
    private func resolvePadLayout(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: BrowserLayout.ViewportOrientation
    ) -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            chromeMode: .pad,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: .top,
            overlayHost: .detached
        )
    }
    
    private func browserTopInset() -> CGFloat {
        return sidebarCoordinator.topInset(fallback: UX.fallbackTopInset)
    }
    
    // MARK: - Sidebar
    
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
        
        let shouldDockChrome = browserLayout.chromeMode == .phone
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
        browserChrome.setMenuButtonIndicatesUpdate(BrowserUpdates.shared.hasUpdate)
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
    
    func applyFullscreenState(_ fullScreen: Bool, for session: GeckoSession?) {
        if fullScreen {
            fullscreenSession = session
        } else if fullscreenSession === session || session == nil {
            fullscreenSession = nil
        }
        
        guard isShowingFullscreenMedia != fullScreen else {
            return
        }
        
        if fullScreen {
            if tabOverview.isPresented {
                tabOverview.setPresented(false, animated: false)
            }
            searchOverlayCoordinator.setFocused(false, animated: false)
            view.endEditing(true)
        }
        
        sidebarCoordinator.setFullscreen(fullScreen)
        isShowingFullscreenMedia = fullScreen
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
                preFullscreenOrientation = currentOrientation
            } else if preFullscreenOrientation == nil {
                preFullscreenOrientation = .portrait
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
            let targetOrientation = preFullscreenOrientation ?? .portrait
            forceInterfaceOrientation(targetOrientation)
            preFullscreenOrientation = nil
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
