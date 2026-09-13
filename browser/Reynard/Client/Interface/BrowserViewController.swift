//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController, GeckoScreenOrientationDelegate {
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
    private var lockedOrientations: UIInterfaceOrientationMask?
    private var pendingOrientationRequest: (
        id: UUID,
        orientations: UIInterfaceOrientationMask,
        completion: (GeckoOrientationLockResult) -> Void
    )?
    private var preFullscreenOrientation: UIInterfaceOrientation?
    weak var fullscreenSession: GeckoSession?
    private let allowsSidebarHosting: Bool
    private var shouldRestoreContentFocus = false
    private(set) var browserLayout = BrowserLayout.initial(
        interfaceIdiom: UIDevice.current.userInterfaceIdiom
    )
    
    // MARK: - Views And Coordinators
    
    let tabOverview = TabOverview()
    let contentView = ContentView()
    lazy var browserChrome = BrowserChrome()
    var tabBar: TabBar { return browserChrome.tabBar }
    
    private(set) lazy var toolbarController = ToolbarController(
        browserChrome: browserChrome,
        tabBar: tabBar,
        contentView: contentView,
        rootView: view
    )
    
    lazy var overlayCoordinator = OverlayCoordinator(host: self)
    lazy var homepageOverlayCoordinator = HomepageOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController
    )
    lazy var searchOverlayCoordinator = SearchOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController
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
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 26.0, *) {
            return .default
        }
        
        guard browserLayout.chromeMode == .phone,
              !tabOverview.isPresented else {
            return .default
        }
        
        switch contentView.state.overlayPresentation {
        case .visible(.homepage):
            let foregroundColor = HomepageWallpaper.foregroundColor(for: .embedded(layout: browserLayout))
            return foregroundColor.isLightColor(in: traitCollection) ? .lightContent : .darkContent
        case .visible(.search):
            return .default
        case .hidden:
            let backgroundColor = tabManager.selectedTab.map {
                sessionManager.pageBackgroundColor(for: $0.session)
            } ?? .systemBackground
            return backgroundColor.isLightColor(in: traitCollection) ? .darkContent : .lightContent
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return isShowingFullscreenMedia
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return sidebarCoordinator.statusBarController
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let lockedOrientations {
            return lockedOrientations
        }
        
        return browserLayout.interfaceIdiom == .pad ? .all : .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        let allowedOrientations = lockedOrientations ?? supportedInterfaceOrientations
        return preferredInterfaceOrientation(allowedBy: allowedOrientations) ?? .portrait
    }
    
    init(canHostSidebar: Bool = true) {
        self.allowsSidebarHosting = canHostSidebar
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopScreenOrientationHandling()
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
        
        RuntimePreferences.apply() // Gecko prefs
        
        configureBrowserInterface()
        observeNotifications()
        contextMenuCoordinator.configure()
        downloadsCoordinator.startObservingStore()
        downloadsCoordinator.syncToolbarButtonState()
        tabOverview.restoreMode(TabOverview.Mode(tabMode: TabManagementStore.shared.preferredRestoredMode()))
        syncBrowserNavigationChrome(animated: false)
        browserChrome.syncSidebarButton(splitViewController: splitViewController)
        applyUpdateMenuButtonBadge()
        
        tabManager.createInitialTab(openingScreen: Prefs.HomepageSettings.openingScreen)
        refreshAddressBar()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            await self.addonCoordinator.start()
            if let session = self.tabManager.selectedTab?.session {
                self.sessionManager.setAddonTabActive(true, for: session)
            }
        }
        
        updateBrowserLayout(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        toolbarController.unlock(for: .viewPresentation)
        performContentLifecycle {
            syncBrowserNavigationChrome(animated: animated)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        performContentLifecycle {
            toolbarController.lock(for: .viewPresentation)
            shouldRestoreContentFocus =
            tabManager.selectedTab?.session.engineView?.isFirstResponder == true
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
            if shouldRestoreContentFocus {
                shouldRestoreContentFocus = false
                requestContentKeyboardFocus()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        toolbarController.updateLayout(
            chromeMode: browserLayout.chromeMode,
            isToolbarEnabled: !isShowingFullscreenMedia,
            extendsContentBehindToolbar: tabManager.selectedTab.map(homepageOverlayCoordinator.needsHomepageThumbnail(for:)) ?? false
        )
        homepageOverlayCoordinator.updateVisibleContentInsets()
        invalidateNavigationThumbnailsIfNeeded()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isViewLoaded,
                  self.view.window != nil,
                  !self.sidebarCoordinator.refreshHostVisibility() else {
                return
            }
            self.syncBrowserNavigationChrome(animated: false)
            self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
            self.refreshAddressBar()
            self.updateBrowserLayout(animated: false)
            self.tabOverview.invalidateCollectionLayouts()
            self.tabBar.invalidateLayout()
            self.tabOverview.refreshForCurrentOrientation()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        performContentLifecycle {
            toolbarController.reset(animated: false)
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
        contentView.onAppearanceChanged = { [weak self] in
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        browserChrome.configureAddressBar(
            delegate: self,
            searchDelegate: self,
            gestureDelegate: self
        )
        configureBrowserChromeActions()
        tabBar.dataSource = self
        tabOverview.configure(dataSource: self, delegate: self, presentationContext: self)
        
        view.addSubview(contentView)
        view.addSubview(browserChrome)
        view.addSubview(tabOverview)
        contentView.configureLayout(
            topAnchor: view.topAnchor,
            bottomAnchor: view.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).withPriority(.defaultHigh),
            contentView.bottomAnchor.constraint(equalTo: browserChrome.bottomToolbarTopAnchor).withPriority(.defaultHigh),
            browserChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserChrome.topAnchor.constraint(equalTo: view.topAnchor),
            browserChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            tabOverview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabOverview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabOverview.topAnchor.constraint(equalTo: view.topAnchor),
            tabOverview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func configureBrowserChromeActions() {
        contentView.onBack = { [weak self] in
            self?.tabManager.goBack()
        }
        contentView.onForward = { [weak self] in
            self?.tabManager.goForward()
        }
        contentView.onHistorySwipeBegan = { [weak self] in
            self?.captureOutgoingHistoryThumbnail()
        }
        browserChrome.onSidebar = { [weak self] in
            self?.sidebarCoordinator.toggle(animated: true)
        }
        browserChrome.onBack = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.prepareThumbnailForNavigation()
            self?.tabManager.goBack()
        }
        browserChrome.onForward = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.prepareThumbnailForNavigation()
            self?.tabManager.goForward()
        }
        browserChrome.configureNavigationMenus(
            itemsProvider: { [weak self] direction in
                guard let self,
                      let tab = self.tabManager.selectedTab else {
                    return []
                }
                
                let snapshot = self.tabManager.navigationHistory(for: tab)
                switch direction {
                case .back:
                    return snapshot.backHistory
                case .forward:
                    return snapshot.forwardHistory
                }
            },
            onSelect: { [weak self] direction, index in
                guard let self else {
                    return
                }
                
                self.toolbarController.reset(preserveManualCollapse: true)
                self.prepareThumbnailForNavigation()
                switch direction {
                case .back:
                    self.tabManager.goBack(to: index)
                case .forward:
                    self.tabManager.goForward(to: index)
                }
            }
        )
        browserChrome.configureLibraryMenus { [weak self] section in
            self?.presentLibrary(initialSection: section)
        }
        browserChrome.configureRecentlyClosedTabsMenu(
            isAvailable: { [weak self] in
                guard let self else {
                    return false
                }
                return self.tabManager.selectedTabMode == .regular
            },
            itemsProvider: {
                TabManagementStore.shared.recentlyClosedTabs(
                    limit: Prefs.HomepageSettings.recentlyClosedTabLimit
                )
            },
            onSelect: { [weak self] id in
                guard let self,
                      self.tabManager.selectedTabMode == .regular else {
                    return
                }
                
                self.toolbarController.reset()
                self.dismissAddressBarEditingAndOverlays()
                _ = self.tabManager.restoreRecentlyClosedTab(id: id)
            }
        )
        browserChrome.configureTabOverviewMenus(
            tabCountProvider: { [weak self] in
                self?.tabManager.activeTabs.count ?? 0
            },
            onCloseAllTabs: { [weak self] in
                self?.closeAllTabs()
            },
            onCloseTab: { [weak self] in
                self?.closeTab()
            },
            onNewPrivateTab: { [weak self] in
                self?.createNewTabAnimated(mode: .private)
            },
            onNewTab: { [weak self] in
                self?.createNewTabAnimated(mode: .regular)
            }
        )
        browserChrome.onShare = { [weak self] in
            guard let self else {
                return
            }
            guard let tab = self.tabManager.selectedTab,
                  let url = self.tabManager.shareableURL(for: tab) else {
                return
            }
            let sourceView = self.browserChrome.sharePopoverSourceView()
            self.presentShareSheet(
                items: [url],
                sourceView: sourceView,
                sourceRect: sourceView.bounds
            )
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
        browserChrome.onOverlayDismiss = { [weak self] in
            self?.toolbarController.reset()
            self?.dismissAddressBarEditingAndChromeOverlay()
        }
        browserChrome.onPageZoomOut = { [weak self] in
            self?.setSelectedPageZoomToPreviousLevel()
        }
        browserChrome.onPageZoomIn = { [weak self] in
            self?.setSelectedPageZoomToNextLevel()
        }
        browserChrome.onPageZoomReset = { [weak self] in
            self?.setSelectedPageZoomLevel(Prefs.BrowsingSettings.defaultPageZoomLevel)
        }
        browserChrome.onFindInPage = { [weak self] query, backwards in
            guard let self,
                  let session = self.tabManager.selectedTab?.session else {
                return nil
            }
            
            if query != nil {
                session.setFindInPageMatchHighlighting(true)
            }
            let result = try? await session.findInPage(query, backwards: backwards)
            guard self.tabManager.selectedTab?.session === session else {
                return nil
            }
            guard let result else {
                return nil
            }
            return (result.current, result.total)
        }
        browserChrome.onClearFindInPage = { [weak self] in
            self?.tabManager.selectedTab?.session.clearFindInPageMatches()
        }
        browserChrome.onFindInPageVisibilityChanged = { [weak self] visible in
            if visible {
                self?.toolbarController.collapseBottomToolbar()
            } else {
                self?.toolbarController.restoreBottomToolbar()
            }
        }
        browserChrome.onKeyboardDismissal = { [weak self] in
            self?.tabManager.selectedTab?.session.engineView?.resignFirstResponder()
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
        
        let previousLayout = browserLayout
        browserLayout = resolveBrowserLayout()
        if browserLayout != previousLayout {
            dismissAddressBarEditingAndOverlays()
        }
        applyBrowserLayout(animated: animated)
        homepageOverlayCoordinator.updatePresentation(animated: false)
        searchOverlayCoordinator.updatePresentedLayout()
        
        let layoutBlock = {
            self.view.layoutIfNeeded()
            self.tabOverview.collection.applyPresentationTransforms()
        }
        
        animated
        ? UIView.animate(withDuration: duration, animations: layoutBlock)
        : layoutBlock()
    }
    
    func dismissAddressBarEditingAndOverlays() {
        homepageOverlayCoordinator.resetPresentationSession()
        searchOverlayCoordinator.resetPresentationSession()
        browserChrome.resetAddressBarEditing()
        overlayCoordinator.discardAll(animated: false)
        applyBrowserLayout(animated: false)
    }
    
    func dismissAddressBarEditingAndChromeOverlay() {
        homepageOverlayCoordinator.resetPresentationSession()
        searchOverlayCoordinator.resetPresentationSession()
        browserChrome.resetAddressBarEditing()
        overlayCoordinator.dismiss(.homepage, on: .detached, animated: false)
        overlayCoordinator.dismiss(.search, on: .detached, animated: false)
        applyBrowserLayout(animated: false)
        requestContentKeyboardFocus()
    }
    
    func updateBrowserLayoutIfNeeded(
        animated: Bool,
        duration: TimeInterval = UX.layoutAnimationDuration
    ) {
        guard browserLayout != resolveBrowserLayout() else {
            return
        }
        
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func applyBrowserLayout(animated: Bool = false) {
        if isShowingFullscreenMedia {
            applyFullscreenLayout()
        } else {
            switch browserLayout.chromeMode {
            case .phone:
                applyPhoneLayout()
            case .compact:
                applyCompactLayout()
            case .pad:
                applyPadLayout(animated: animated)
            }
        }
        
        applyTabOverviewLayout()
        applyBrowserChromeLayout(animated: animated)
        updateNavigationButtons()
        setNeedsStatusBarAppearanceUpdate()
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
        tabBar.setVisibility(.hidden, animated: false)
    }
    
    private func applyCompactLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: browserChrome.topToolbarBottomAnchor,
            bottomAnchor: browserChrome.bottomToolbarTopAnchor
        )
        tabBar.setVisibility(.hidden, animated: false)
    }
    
    private func applyPadLayout(animated: Bool) {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: browserChrome.tabBarBottomAnchor,
            bottomAnchor: view.bottomAnchor
        )
        tabBar.setVisibility(targetTabBarVisibility, animated: animated)
    }
    
    private var visibleTabCount: Int {
        let tabs = tabManager.selectedTabMode == .private
        ? tabManager.privateTabs
        : tabManager.regularTabs
        return tabs.count
    }
    
    var targetTabBarVisibility: TabBar.Visibility {
        guard browserLayout.chromeMode == .pad else {
            return .hidden
        }
        
        let showsTabBar = browserLayout.interfaceIdiom == .pad
        ? visibleTabCount > 1
        : visibleTabCount > 1 && Prefs.AppearanceSettings.showsLandscapeTabBar
        guard showsTabBar else {
            return .hidden
        }
        return tabOverview.isPresented ? .layoutReserved : .visible
    }
    
    private func applyTabOverviewLayout() {
        tabOverview.applyLayout(
            toolbarPosition: browserLayout.tabOverviewToolbarPosition,
            animated: false
        )
    }
    
    private func applyBrowserChromeLayout(animated: Bool) {
        let searchState = isShowingFullscreenMedia
        ? BrowserChrome.SearchState.inactive
        : (overlayCoordinator.chromeStateForAddressBarScrollDismissal(layout: browserLayout) ?? searchOverlayCoordinator.chromeState)
        browserChrome.apply(state: BrowserChrome.State(
            position: browserLayout.chromePosition,
            mode: browserLayout.chromeMode,
            presentation: isShowingFullscreenMedia
            ? .fullscreenMedia
            : (tabOverview.isPresented ? .tabOverview : .browsing),
            search: searchState,
            topInset: browserTopInset(),
            interfaceIdiom: browserLayout.interfaceIdiom,
            orientation: browserLayout.orientation,
            isTwoThirdSplitScreenOrSmaller: isSidebarOverlayLayout,
            sidebarButtonVisible: sidebarCoordinator.showChromeSidebarButton,
            animatesChromeStateChanges: animated
        ))
    }
    
    private func resolveBrowserLayout() -> BrowserLayout {
        let interfaceIdiom = traitCollection.userInterfaceIdiom
        let orientation = currentViewportOrientation()
        
        if interfaceIdiom == .pad {
            return isCompactPadLayout
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
    
    private func invalidateNavigationThumbnailsIfNeeded() {
        let didResizeWebContent = contentView.updateWebContentSize()
        guard didResizeWebContent else {
            return
        }
        
        tabManager.invalidateNavigationThumbnails()
        updateNavigationButtons()
    }
    
    var isCompactPadLayout: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isOneThirdSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isOneThirdSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    var isSidebarOverlayLayout: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isTwoThirdSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isTwoThirdSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    var isHalfSplitScreenOrSmaller: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isHalfSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isHalfSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    private func browserWindowWidth(fallback: CGFloat) -> CGFloat {
        guard let rootView = view.window?.rootViewController?.view,
              rootView.bounds.width > 0 else {
            return fallback
        }
        
        return rootView.bounds.width
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
            tabOverviewToolbarPosition: .bottom,
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
            tabOverviewToolbarPosition: isHalfSplitScreenOrSmaller ? .bottom : .top,
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
            selector: #selector(setNeedsStatusBarAppearanceUpdate),
            name: .homepageSettingsDidChange,
            object: nil
        )
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
            selector: #selector(appearanceGestureSettingsDidChange),
            name: .appearanceGestureSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyUpdateMenuButtonBadge),
            name: .appUpdateAvailable,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(newTabDisplayOptionDidChange),
            name: .newTabDisplayOptionDidChange,
            object: nil
        )
    }
    
    @objc private func newTabDisplayOptionDidChange() {
        homepageOverlayCoordinator.updatePresentation(animated: true)
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
    }
    
    @objc func addressBarPositionDidChange() {
        updateBrowserLayout(animated: true)
    }
    
    @objc func landscapeTabBarDidChange() {
        updateBrowserLayout(animated: true)
    }
    
    @objc private func appearanceGestureSettingsDidChange() {
        updateBrowserLayout(animated: false)
    }
    
    @objc func applyUpdateMenuButtonBadge() {
        browserChrome.setMenuButtonIndicatesUpdate(BrowserUpdates.shared.hasUpdate)
    }
    
    // MARK: - Keyboard
    
    func requestContentKeyboardFocus(for expectedSession: GeckoSession? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let presentedController = presentedControllerInHierarchy {
                guard let transitionCoordinator = presentedController.transitionCoordinator else {
                    return
                }
                transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.requestContentKeyboardFocus(for: expectedSession)
                }
                return
            }
            restoreContentKeyboardFocus(for: expectedSession)
        }
    }
    
    private func restoreContentKeyboardFocus(for expectedSession: GeckoSession? = nil) {
        guard !browserChrome.isAddressBarEditing,
              let selectedSession = tabManager.selectedTab?.session else {
            return
        }
        if let expectedSession, expectedSession !== selectedSession {
            return
        }
        guard contentView.isDisplaying(session: selectedSession),
              let engineView = selectedSession.engineView,
              let window = engineView.window,
              window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else {
            return
        }
        selectedSession.focusForHardwareKeyboard()
    }
    
    private func isEditingTextInWebView() -> Bool {
        guard let selectedSession = tabManager.selectedTab?.session,
              contentView.isDisplaying(session: selectedSession),
              let engineView = selectedSession.engineView,
              engineView.isFirstResponder,
              let textInput = engineView as? UITextInput else {
            return false
        }
        return textInput.selectedTextRange != nil
    }
    
    private var presentedControllerInHierarchy: UIViewController? {
        var controller: UIViewController? = self
        while let currentController = controller {
            if let presentedController = currentController.presentedViewController {
                return presentedController
            }
            controller = currentController.parent
        }
        return nil
    }
    
    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let keyboardInset = max(
            0,
            view.bounds.maxY - keyboardFrame.minY - view.safeAreaInsets.bottom
        )
        let keyboardOverlap = max(0, view.bounds.maxY - keyboardFrame.minY)
        let animation = keyboardAnimation(from: notification)
        let isInHardwareKeyboardMode = tabManager.selectedTab?.session.isInHardwareKeyboardMode() == true
        let shouldShowKeyboardDismissal = !tabOverview.isPresented
        && browserLayout.interfaceIdiom == .phone
        && keyboardInset > 0
        && !isInHardwareKeyboardMode
        && isEditingTextInWebView()
        if shouldShowKeyboardDismissal {
            if !browserChrome.isShowingKeyboardDismissal {
                browserChrome.showActionBar(.keyboardDismissal, animated: true)
            }
        } else if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: true)
        }
        let keyboardDismissalActionBarInset = browserChrome.isShowingKeyboardDismissal
        ? ActionBarStyle.compact.height
        : 0
        if !searchOverlayCoordinator.isFocused
            && !tabOverview.isPresented
            && keyboardInset > 0
            && !isInHardwareKeyboardMode {
            contentView.relocateFocusedInput(
                above: keyboardFrame,
                bottomInset: keyboardDismissalActionBarInset,
                animationDuration: animation.duration,
                animationOptions: animation.curve
            )
        } else {
            contentView.resetFocusedInputRelocation(
                animationDuration: animation.duration,
                animationOptions: animation.curve
            )
        }
        
        let shouldDockActionBar = !tabOverview.isPresented
        && keyboardInset > 0
        && !isInHardwareKeyboardMode
        && (browserChrome.isShowingFindInPage || browserChrome.isShowingKeyboardDismissal)
        let shouldDockAddressBar = !tabOverview.isPresented
        && keyboardInset > 0
        && !isInHardwareKeyboardMode
        && (
            browserLayout.chromeMode == .phone && searchOverlayCoordinator.isFocused
        )
        browserChrome.dockActionBar(offset: shouldDockActionBar ? -keyboardOverlap : 0)
        browserChrome.dockAddressBar(offset: shouldDockAddressBar ? -keyboardInset : 0)
        animateLayout(animation)
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        let animation = keyboardAnimation(from: notification)
        if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: true)
        }
        contentView.resetFocusedInputRelocation(
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
        browserChrome.dockActionBar(offset: 0)
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
            contentView.setHistoryNavigation(
                canGoBack: false,
                canGoForward: false,
                backPreviewImage: nil,
                forwardPreviewImage: nil,
                isSwipeEnabled: false
            )
            return
        }
        
        browserChrome.updateNavigation(
            canGoBack: tab.state.navigationState.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            canShare: tabManager.shareableURL(for: tab) != nil
        )
        
        let previewImages = tabManager.navigationPreviewImages(for: tab)
        contentView.setHistoryNavigation(
            canGoBack: tab.state.navigationState.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            backPreviewImage: previewImages.backImage,
            forwardPreviewImage: previewImages.forwardImage,
            isSwipeEnabled: true
        )
    }
    
    func applyFullscreenState(_ fullScreen: Bool, for session: GeckoSession?, mediaIsPlaying: Bool) {
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
        updateBrowserLayout(animated: false)
        UIApplication.shared.isIdleTimerDisabled = fullScreen && mediaIsPlaying
        updateFullscreenOrientation(fullScreen)
        requestContentKeyboardFocus(for: tabManager.selectedTab?.session)
    }
    
    func exitFullscreenIfNeeded() {
        guard isShowingFullscreenMedia,
              let session = fullscreenSession else {
            return
        }
        session.exitFullScreen()
        applyFullscreenState(false, for: session, mediaIsPlaying: false)
    }
    
    // MARK: - Orientation
    
    func lockScreenOrientation(
        to requestedOrientations: UIInterfaceOrientationMask,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    ) {
        guard !requestedOrientations.isEmpty else {
            completion(.notSupported)
            return
        }
        
        rejectPendingOrientationRequest()
        
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else {
                completion(.notSupported)
                return
            }
            
            lockedOrientations = requestedOrientations
            setNeedsUpdateOfSupportedInterfaceOrientations()
            if let currentOrientationMask = orientationMask(
                for: windowScene.interfaceOrientation
            ), requestedOrientations.contains(currentOrientationMask) {
                completion(.success)
                return
            }
            
            let requestID = UUID()
            pendingOrientationRequest = (requestID, requestedOrientations, completion)
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: requestedOrientations
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { [weak self] error in
                let geometryError = error as NSError
                let lockResult: GeckoOrientationLockResult =
                geometryError.domain == UISceneErrorDomain &&
                geometryError.code == UISceneError.Code.geometryRequestUnsupported.rawValue
                ? .notSupported
                : .rejected
                self?.completePendingOrientationRequest(id: requestID, with: lockResult)
            }
            return
        }
        
        guard let preferredOrientation = preferredInterfaceOrientation(
            allowedBy: requestedOrientations
        ) else {
            completion(.notSupported)
            return
        }
        
        lockedOrientations = requestedOrientations
        forceInterfaceOrientation(preferredOrientation)
        completion(.success)
    }
    
    func unlockScreenOrientation() {
        rejectPendingOrientationRequest()
        lockedOrientations = nil
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        updateFullscreenOrientation(false)
    }
    
    private func updateFullscreenOrientation(_ fullScreen: Bool) {
        guard browserLayout.interfaceIdiom == .phone else {
            return
        }
        
        if fullScreen {
            if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
               interfaceOrientation != .unknown {
                preFullscreenOrientation = interfaceOrientation
            } else {
                preFullscreenOrientation = .portrait
            }
            return
        }
        
        guard !isShowingFullscreenMedia,
              lockedOrientations == nil,
              let preFullscreenOrientation else {
            return
        }
        self.preFullscreenOrientation = nil
        forceInterfaceOrientation(preFullscreenOrientation)
    }
    
    private func completePendingOrientationRequestIfSatisfied() {
        guard let pendingOrientationRequest,
              let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
              let currentOrientationMask = orientationMask(for: interfaceOrientation),
              pendingOrientationRequest.orientations.contains(currentOrientationMask) else {
            return
        }
        
        completePendingOrientationRequest(id: pendingOrientationRequest.id, with: .success)
    }
    
    private func completePendingOrientationRequest(
        id: UUID,
        with result: GeckoOrientationLockResult
    ) {
        guard let pendingOrientationRequest,
              pendingOrientationRequest.id == id else {
            return
        }
        
        self.pendingOrientationRequest = nil
        if result != .success {
            lockedOrientations = nil
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        pendingOrientationRequest.completion(result)
    }
    
    private func rejectPendingOrientationRequest() {
        guard let pendingOrientationRequest else {
            return
        }
        
        self.pendingOrientationRequest = nil
        pendingOrientationRequest.completion(.rejected)
    }
    
    func startScreenOrientationHandling() {
        guard allowsSidebarHosting else {
            return
        }
        
        GeckoRuntime.orientationController.delegate = self
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        screenOrientationChanged(to: interfaceOrientation)
    }
    
    func stopScreenOrientationHandling() {
        guard let registeredDelegate = GeckoRuntime.orientationController.delegate,
              registeredDelegate === self else {
            return
        }
        
        rejectPendingOrientationRequest()
        GeckoRuntime.orientationController.delegate = nil
    }
    
    func screenOrientationChanged(to interfaceOrientation: UIInterfaceOrientation) {
        guard interfaceOrientation != .unknown else {
            return
        }
        
        tabManager.selectedTab?.session.notifyScreenOrientationChanged(to: interfaceOrientation)
        completePendingOrientationRequestIfSatisfied()
    }
    
    private func preferredInterfaceOrientation(
        allowedBy orientations: UIInterfaceOrientationMask
    ) -> UIInterfaceOrientation? {
        if let currentOrientation = view.window?.windowScene?.interfaceOrientation,
           currentOrientation != .unknown,
           let currentOrientationMask = orientationMask(for: currentOrientation),
           orientations.contains(currentOrientationMask) {
            return currentOrientation
        }
        
        if orientations.contains(.portrait) {
            return .portrait
        }
        if orientations.contains(.portraitUpsideDown) {
            return .portraitUpsideDown
        }
        if orientations.contains(.landscapeRight) {
            return .landscapeRight
        }
        if orientations.contains(.landscapeLeft) {
            return .landscapeLeft
        }
        return nil
    }
    
    private func orientationMask(
        for orientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
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
