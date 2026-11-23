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
        static let floatingKeyboardWidthRatio: CGFloat = 0.8
    }
    
    private struct KeyboardAnimation {
        let duration: TimeInterval
        let curve: UIView.AnimationOptions
    }
    
    // MARK: - State
    
    let sessionManager = SessionManager()
    private lazy var promptCoordinator = PromptCoordinator(
        presenter: PromptPresenter(),
        onPromptFinished: { [weak self] session in
            self?.requestContentKeyboardFocus(for: session)
        }
    )
    private lazy var permissionCoordinator = PermissionCoordinator(
        promptPresenter: PermissionPromptPresenter(),
        onPromptFinished: { [weak self] session in
            self?.requestContentKeyboardFocus(for: session)
        }
    )
    private lazy var pagePrintCoordinator = PagePrintCoordinator { [weak self] session in
        return self?.tabManager.tab(for: session)?.title
    }
    private lazy var selectionActionCoordinator = SelectionActionCoordinator(
        presenter: SelectionActionPresenter(
            onMenuDismissed: { [weak self] session in
                self?.requestContentKeyboardFocus(for: session)
            },
            onFindInPage: { [weak self] session, query in
                guard let self,
                      self.tabManager.selectedTab?.session === session else {
                    return
                }
                
                self.browserChrome.showActionBar(.findInPage(query: query), animated: true)
            }
        )
    )
    lazy var tabManager: TabManager = TabManager(
        delegate: self,
        sessionHandlerDelegate: self,
        sessionManager: sessionManager,
        promptCoordinator: promptCoordinator,
        permissionCoordinator: permissionCoordinator,
        pagePrintCoordinator: pagePrintCoordinator,
        selectionActionCoordinator: selectionActionCoordinator
    )
    
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
    
    lazy var overlayCoordinator = OverlayCoordinator(
        parentViewController: self,
        contentView: contentView,
        browserChrome: browserChrome
    )
    lazy var homepageOverlayCoordinator = HomepageOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController,
        browserChrome: browserChrome,
        contentView: contentView,
        tabManager: tabManager
    )
    lazy var searchOverlayCoordinator = SearchOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController,
        browserChrome: browserChrome,
        contentView: contentView,
        tabManager: tabManager
    )
    lazy var contextMenuCoordinator = ContextMenuCoordinator(
        host: self,
        sessionManager: sessionManager,
        contentView: contentView,
        tabManager: tabManager
    )
    lazy var downloadsCoordinator = DownloadsCoordinator(delegate: self)
    lazy var sidebarCoordinator = SidebarCoordinator(
        host: self,
        canHostSidebar: allowsSidebarHosting
    )
    lazy var addonCoordinator = AddonCoordinator(
        delegate: self,
        sessionManager: sessionManager,
        tabManager: tabManager
    )
    private(set) lazy var screenOrientationController = ScreenOrientationController(
        viewController: self,
        onOrientationChange: { [weak self] interfaceOrientation in
            self?.sidebarCoordinator.notifyScreenOrientationChanged(to: interfaceOrientation)
        }
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
        if let lockedOrientations = screenOrientationController.lockedOrientations {
            return lockedOrientations
        }
        
        return browserLayout.interfaceIdiom == .pad ? .all : .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return screenOrientationController.preferredInterfaceOrientation(
            allowedBy: supportedInterfaceOrientations
        ) ?? .portrait
    }
    
    init(canHostSidebar: Bool = true) {
        self.allowsSidebarHosting = canHostSidebar
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
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
        
        tabManager.createInitialTab()
        refreshAddressBar()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            await self.addonCoordinator.start()
            if let session = self.tabManager.selectedTab?.session {
                session.setAddonTabActive(true)
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
            
            requestHomepageAddressBarFocus()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let showsHomepage = tabManager.selectedTab.map(homepageOverlayCoordinator.isHomepageTab) ?? false
        toolbarController.updateLayout(
            chromeMode: browserLayout.chromeMode,
            isToolbarEnabled: !isShowingFullscreenMedia,
            extendsContentBehindToolbar: showsHomepage
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
        if let readerSettings = presentedViewController as? ReaderSettingsViewController {
            readerSettings.dismiss(animated: false)
        }
        
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
                self.browserChrome.addressBar.resetHorizontalTransition()
                self.tabOverview.refreshForCurrentOrientation()
                DispatchQueue.main.async {
                    guard self.isViewLoaded,
                          self.view.window != nil else {
                        return
                    }
                    
                    self.updateBrowserLayout(animated: false)
                }
            }
        }
    }
    
    // MARK: - Browser Layout
    
    private func configureBrowserInterface() {
        contentView.keyCommandDelegate = self
        contentView.onAppearanceChanged = { [weak self] in
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        
        browserChrome.addressBar.configure(
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
            self?.captureHistoryThumbnail(isPreparedForNavigation: true)
        }
        contentView.onErrorAction = { [weak self] action in
            self?.performErrorPageAction(action)
        }
        
        browserChrome.onSidebar = { [weak self] in
            self?.sidebarCoordinator.toggle(animated: true)
        }
        
        browserChrome.onBack = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.captureHistoryThumbnail(isPreparedForNavigation: true)
            self?.tabManager.goBack()
        }
        browserChrome.onForward = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.captureHistoryThumbnail(isPreparedForNavigation: true)
            self?.tabManager.goForward()
        }
        browserChrome.configureNavigationMenus(
            itemsProvider: { [weak self] direction in
                guard let tab = self?.tabManager.selectedTab,
                      let sessionState = tab.displayedSessionState else {
                    return []
                }
                
                switch direction {
                case .back:
                    return sessionState.backHistory
                case .forward:
                    return sessionState.forwardHistory
                }
            },
            onSelect: { [weak self] direction, index in
                guard let self else {
                    return
                }
                
                self.toolbarController.reset(preserveManualCollapse: true)
                self.captureHistoryThumbnail(isPreparedForNavigation: true)
                self.tabManager.goToHistory(offset: direction == .back ? -(index + 1) : index + 1)
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
            guard let self,
                  let tab = self.tabManager.selectedTab,
                  let url = tab.shareableURL else {
                return
            }
            
            let sourceView = self.browserChrome.sharePopoverSourceView()
            self.presentShareSheet(
                items: [url],
                sourceView: sourceView,
                sourceRect: sourceView.bounds,
                applicationActivities: [
                    BookmarkActivity(url: url),
                    AddToFavoritesActivity(url: url),
                    FindInPageActivity(url: url),
                    PagePrintActivity(session: tab.session, jobName: tab.title)
                ],
                onActivityPerformed: { [weak self] activityType in
                    guard let self else {
                        return
                    }
                    
                    if activityType == BookmarkActivity.identifier {
                        self.presentBookmarkEditor(addToFavorites: false)
                    } else if activityType == AddToFavoritesActivity.identifier {
                        self.presentBookmarkEditor(addToFavorites: true)
                    } else if activityType == FindInPageActivity.identifier {
                        self.browserChrome.showActionBar(.findInPage(), animated: true)
                    }
                }
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
                self?.requestContentKeyboardFocus()
            }
        }
        
        browserChrome.onKeyboardDismissal = { [weak self] in
            self?.tabManager.selectedTab?.session.dismissSoftwareKeyboard()
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
            if let readerSettings = presentedViewController as? ReaderSettingsViewController {
                readerSettings.dismiss(animated: false)
            }
            
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
    
    var targetTabBarVisibility: TabBar.Visibility {
        guard browserLayout.chromeMode == .pad else {
            return .hidden
        }
        
        let showsTabBar = browserLayout.interfaceIdiom == .pad
        ? tabManager.activeTabs.count > 1
        : tabManager.activeTabs.count > 1 && Prefs.AppearanceSettings.showsLandscapeTabBar
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
        let searchState: BrowserChrome.SearchState
        if isShowingFullscreenMedia {
            searchState = .inactive
        } else {
            searchState = overlayCoordinator.chromeStateForAddressBarScrollDismissal(layout: browserLayout)
            ?? searchOverlayCoordinator.chromeState
        }
        
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
        return BrowserLayout.resolve(
            interfaceIdiom: traitCollection.userInterfaceIdiom,
            orientation: currentViewportOrientation(),
            addressBarPosition: Prefs.AppearanceSettings.addressBarPosition,
            isCompactPadLayout: isCompactPadLayout,
            isHalfSplitScreenOrSmaller: isHalfSplitScreenOrSmaller
        )
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
        
        NavigationHistoryStore.shared.invalidateThumbnails()
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
            selector: #selector(selectionSystemUIDidDismiss(_:)),
            name: .selectionSystemUIDidDismiss,
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
        captureThumbnail(for: tabManager.selectedTab)
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
    
    func requestHomepageAddressBarFocus() {
        let expectedSession = tabManager.selectedTab?.session
        
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let tab = tabManager.selectedTab,
                  tab.session === expectedSession else {
                return
            }
            
            guard homepageOverlayCoordinator.isHomepageTab(tab),
                  tab.session.isInHardwareKeyboardMode() else {
                return
            }
            
            guard !tabOverview.isPresented,
                  !tabOverview.isTransitionRunning else {
                return
            }
            
            guard !browserChrome.addressBar.isEditingText,
                  presentedControllerInHierarchy == nil else {
                return
            }
            
            browserChrome.addressBar.focusForHardwareKeyboard()
        }
    }
    
    func requestContentKeyboardFocus(for expectedSession: GeckoSession? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            
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
        guard !browserChrome.addressBar.isEditingText,
              let selectedSession = tabManager.selectedTab?.session else {
            return
        }
        
        if let expectedSession,
           expectedSession !== selectedSession {
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
    
    @objc private func selectionSystemUIDidDismiss(_ notification: Notification) {
        guard let source = notification.object as? UIView,
              let session = tabManager.selectedTab?.session,
              let engineView = session.engineView,
              source.isDescendant(of: engineView) else {
            return
        }
        
        requestContentKeyboardFocus(for: session)
    }
    
    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        
        let isHardwareKeyboardMode = tabManager.selectedTab?.session.isInHardwareKeyboardMode() == true
        if !isHardwareKeyboardMode {
            browserChrome.addressBar.restoreEditingLayout()
        }
        
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let keyboardOverlap = max(0, view.bounds.maxY - keyboardFrame.minY)
        let keyboardInset = max(0, keyboardOverlap - view.safeAreaInsets.bottom)
        
        let spansWindow = view.bounds.width > 0
        && keyboardFrame.width >= view.bounds.width * UX.floatingKeyboardWidthRatio
        let sitsFlushWithBottom = keyboardFrame.maxY >= view.bounds.maxY - 8
        let isDockedKeyboard = spansWindow && sitsFlushWithBottom
        let isFloatingKeyboard = browserLayout.interfaceIdiom == .pad && !isDockedKeyboard
        
        let shouldAdjustForKeyboard = keyboardInset > 0
        && !isFloatingKeyboard
        && !tabOverview.isPresented
        && !isHardwareKeyboardMode
        
        let isPresentingOverContent = presentedControllerInHierarchy.map { !$0.isBeingDismissed } ?? false
        let shouldRelocateInput = shouldAdjustForKeyboard
        && !searchOverlayCoordinator.isFocused
        && !browserChrome.isShowingFindInPage
        && !isPresentingOverContent
        
        if shouldRelocateInput {
            toolbarController.lock(for: .inputRelocation)
        } else {
            toolbarController.unlock(for: .inputRelocation)
        }
        
        if shouldRelocateInput && browserLayout.interfaceIdiom == .phone {
            browserChrome.showActionBar(.keyboardDismissal, animated: false)
        } else if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: false)
        }
        
        let isShowingActionBar = browserChrome.isShowingFindInPage || browserChrome.isShowingKeyboardDismissal
        let shouldDockActionBar = shouldAdjustForKeyboard && isShowingActionBar
        let shouldDockAddressBar = shouldAdjustForKeyboard
        && browserLayout.chromeMode == .phone
        && searchOverlayCoordinator.isFocused
        
        let animation = keyboardAnimation(from: notification)
        browserChrome.dockActionBar(offset: shouldDockActionBar ? -keyboardOverlap : 0)
        browserChrome.dockAddressBar(offset: shouldDockAddressBar ? -keyboardInset : 0)
        animateLayout(animation)
        
        contentView.updateFocusedInputRelocation(
            above: shouldRelocateInput ? keyboardFrame : nil,
            bottomInset: browserChrome.isShowingKeyboardDismissal ? ActionBarStyle.compact.height : 0,
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        toolbarController.unlock(for: .inputRelocation)
        
        if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: false)
        }
        
        let animation = keyboardAnimation(from: notification)
        contentView.resetFocusedInputRelocation(
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
        browserChrome.dockActionBar(offset: 0)
        browserChrome.dockAddressBar(offset: 0)
        animateLayout(animation)
    }
    
    private func keyboardAnimation(from notification: Notification) -> KeyboardAnimation {
        let userInfo = notification.userInfo
        let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? UX.keyboardAnimationDuration
        let rawCurve = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UX.keyboardAnimationCurve
        
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
            canGoBack: tabManager.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            canShare: tab.shareableURL != nil
        )
        
        let previewImages = tab.navigationPreviewImages
        contentView.setHistoryNavigation(
            canGoBack: tabManager.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            backPreviewImage: tab.state.navigationState.canGoBack ? previewImages.backImage : nil,
            forwardPreviewImage: previewImages.forwardImage,
            isSwipeEnabled: true
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
        updateBrowserLayout(animated: false)
        screenOrientationController.setFullscreen(fullScreen)
        requestContentKeyboardFocus(for: tabManager.selectedTab?.session)
    }
    
    func exitFullscreenIfNeeded() {
        guard isShowingFullscreenMedia,
              let session = fullscreenSession else {
            return
        }
        
        session.exitFullScreen()
        applyFullscreenState(false, for: session)
    }
}
