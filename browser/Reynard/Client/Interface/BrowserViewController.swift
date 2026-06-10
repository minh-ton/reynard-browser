//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController {
    lazy var tabManager: TabManager = TabManagerImplementation(delegate: self)
    private var orientationBeforeFullscreen: UIInterfaceOrientation?
    
    private(set) var isInFullscreenMedia = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return isInFullscreenMedia
    }
    
    override var childForStatusBarHidden: UIViewController? {
        shouldEmbedSidebarContainer ? embeddedSplitController : nil
    }
    
    init(isSidebarContainerHost: Bool = true) {
        super.init(nibName: nil, bundle: nil)
        self.isSidebarContainerHost = isSidebarContainerHost
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
        
        if shouldEmbedSidebarContainer {
            setupEmbeddedSidebarContainer()
            return
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBarPositionDidChange),
            name: Notification.Name("addressBarPositionChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(landscapeTabBarDidChange),
            name: Notification.Name("landscapeTabBarChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyUpdateMenuButtonBadge),
            name: AppUpdates.updateAvailableNotification,
            object: nil
        )
        
        configureContextMenu()
        observeDownloadState()
        syncDownloadButtonState()
        browserUI.configureLayout()
        browserUI.observeKeyboard()
        restoreTabOverviewMode()
        syncBrowserNavigationChrome(animated: false)
        syncSidebarButtonItem()
        
        if AppUpdates.shared.hasUpdate {
            applyUpdateMenuButtonBadge()
        }
        
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
        
        browserUI.applyChromeLayout(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !shouldEmbedSidebarContainer else {
            return
        }
        syncBrowserNavigationChrome(animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !shouldEmbedSidebarContainer else {
            return
        }
        view.endEditing(true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !shouldEmbedSidebarContainer else {
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncSidebarButtonItem()
        syncDownloadButtonState()
        browserUI.applyChromeLayout(animated: false)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard !shouldEmbedSidebarContainer else {
            embeddedSplitController?.refreshSidebarVisibility()
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncSidebarButtonItem()
        refreshAddressBar()
        browserUI.applyChromeLayout(animated: false)
        updateSuggestionsLayoutIfNeeded()
        browserUI.tabOverview.invalidateCollectionLayouts()
        browserUI.tabBar.invalidateLayout()
        browserUI.tabOverview.refreshForCurrentOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !shouldEmbedSidebarContainer else {
            return
        }
        
        coordinator.animate { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncSidebarButtonItem()
            self.browserUI.tabOverview.invalidateCollectionLayouts()
            self.browserUI.tabBar.invalidateLayout()
        } completion: { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncSidebarButtonItem()
            self.browserUI.geckoView.transform = .identity
            self.browserUI.browserChrome.resetHorizontalTransition()
            self.browserUI.tabOverview.refreshForCurrentOrientation()
            DispatchQueue.main.async {
                guard self.isViewLoaded, self.view.window != nil else {
                    return
                }
                self.browserUI.applyChromeLayout(animated: false)
                self.updateSuggestionsLayoutIfNeeded()
            }
        }
    }
    
    @discardableResult
    func createTab(selecting: Bool, windowId: String? = nil, at index: Int? = nil, isPrivate: Bool? = nil) -> Int {
        let shouldCreatePrivate = isPrivate ?? (tabManager.selectedTabMode == .private)
        let createdIndex = tabManager.addTab(selecting: selecting, windowId: windowId, at: index, isPrivate: shouldCreatePrivate)
        browserUI.tabBar.setPendingExpansion(at: selecting ? createdIndex : nil)
        return createdIndex
    }
    
    func selectTab(at index: Int, animated: Bool) {
        pendingSelectionAnimation = animated
        tabManager.selectTab(at: index, mode: nil)
    }
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        tabManager.moveTab(from: sourceIndex, to: destinationIndex, mode: nil)
    }
    
    func closeTab(at index: Int) {
        browserUI.tabBar.setPendingExpansion(at: nil)
        tabManager.removeTab(at: index, mode: nil)
    }
    
    func clearAllTabs() {
        browserUI.tabBar.setPendingExpansion(at: nil)
        tabManager.removeAllTabs(mode: nil)
    }
    
    func browse(to term: String) {
        tabManager.browse(to: term)
    }
    
    func openExternalURL(_ url: URL) {
        let targetController = activeContentController
        targetController.loadViewIfNeeded()
        let targetTab = targetController.prepareTabForExternalLoad()
        targetController.tabManager.browse(to: url.absoluteString, in: targetTab)
    }
    
    private var activeContentController: BrowserViewController {
        embeddedSplitController?.contentBrowserViewController ?? self
    }
    
    private func prepareTabForExternalLoad() -> Tab {
        let targetMode = tabManager.selectedTabMode
        let targetIsPrivate = targetMode == .private
        let activeTabs = targetIsPrivate ? tabManager.privateTabs : tabManager.regularTabs
        
        guard !activeTabs.isEmpty else {
            let createdIndex = createTab(selecting: true, at: 0, isPrivate: targetIsPrivate)
            let updatedTabs = targetIsPrivate ? tabManager.privateTabs : tabManager.regularTabs
            return updatedTabs[createdIndex]
        }
        
        if let selectedTab = tabManager.selectedTab,
           selectedTab.isPrivate == targetIsPrivate,
           isBlankTab(selectedTab) {
            return selectedTab
        }
        
        let createdIndex = createTab(selecting: true, at: activeTabs.count, isPrivate: targetIsPrivate)
        let updatedTabs = targetIsPrivate ? tabManager.privateTabs : tabManager.regularTabs
        return updatedTabs[createdIndex]
    }
    
    private func isBlankTab(_ tab: Tab) -> Bool {
        guard let url = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else {
            return true
        }
        
        return url.lowercased().hasPrefix("about:blank")
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if isInFullscreenMedia && !isPad {
            return .landscape
        }
        
        return isPad ? .all : .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if isInFullscreenMedia && !isPad {
            return .landscapeRight
        }
        
        return .portrait
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
            if browserUI.tabOverview.isPresented {
                browserUI.tabOverview.setPresented(false, animated: false)
            }
            setSearchFocused(false, animated: false)
            view.endEditing(true)
        }
        
        isInFullscreenMedia = fullScreen
        browserUI.applyChromeLayout(animated: true)
        updateFullscreenOrientation(fullScreen)
        UIApplication.shared.isIdleTimerDisabled = fullScreen
    }
    
    private func updateFullscreenOrientation(_ fullScreen: Bool) {
        guard !isPad else {
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
