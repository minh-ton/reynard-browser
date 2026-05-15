//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController, AddressBarDelegate, PhoneToolbarDelegate {
    lazy var tabManager: TabManager = TabManagerImplementation(delegate: self)
    private(set) var isInFullscreenMedia = false
    private var orientationBeforeFullscreen: UIInterfaceOrientation?
    
    init(isSidebarContainerHost: Bool = true) {
        super.init(nibName: nil, bundle: nil)
        self.isSidebarContainerHost = isSidebarContainerHost
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
            selector: #selector(changeWebsiteModeRequested),
            name: AddressBarMenu.changeWebsiteModeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presentAddonSettingsRequested(_:)),
            name: AddressBarMenu.presentAddonSettingsNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyUpdateMenuButtonBadge),
            name: AppUpdates.updateAvailableNotification,
            object: nil
        )
        
        observeDownloadState()
        syncDownloadButtonState()
        browserUI.configureLayout()
        browserUI.observeKeyboard()
        addressBarGestures.configureGestures()
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        
        if AppUpdates.shared.hasUpdate {
            applyUpdateMenuButtonBadge()
        }
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            await self.addonsController.start()
            self.tabManager.createInitialTab()
            self.tabManager.selectedTab?.session.setAddonTabActive(true)
            self.refreshAddressBar()
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
        syncPadSidebarButtonItem()
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
        syncPadSidebarButtonItem()
        refreshAddressBar()
        browserUI.applyChromeLayout(animated: false)
        browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        browserUI.tabBar.collectionView.collectionViewLayout.invalidateLayout()
        tabOverviewPresentation.refreshForCurrentOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !shouldEmbedSidebarContainer else {
            return
        }
        
        coordinator.animate { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
            self.browserUI.tabBar.collectionView.collectionViewLayout.invalidateLayout()
        } completion: { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.geckoView.transform = .identity
            self.addressBarGestures.resetHorizontalTransition()
            self.tabOverviewPresentation.refreshForCurrentOrientation()
            DispatchQueue.main.async {
                guard self.isViewLoaded, self.view.window != nil else {
                    return
                }
                self.browserUI.applyChromeLayout(animated: false)
            }
        }
    }
    
    @discardableResult
    func createTab(selecting: Bool, windowId: String? = nil, at index: Int? = nil) -> Int {
        let createdIndex = tabManager.addTab(selecting: selecting, windowId: windowId, at: index)
        pendingExpandedTabBarIndex = selecting ? createdIndex : nil
        return createdIndex
    }
    
    func selectTab(at index: Int, animated: Bool) {
        pendingSelectionAnimation = animated
        tabManager.selectTab(at: index)
    }
    
    func closeTab(at index: Int) {
        pendingExpandedTabBarIndex = nil
        tabManager.removeTab(at: index)
    }
    
    func clearAllTabs() {
        pendingExpandedTabBarIndex = nil
        tabManager.removeAllTabs()
    }
    
    func usesExpandedTabBarWidth(at index: Int) -> Bool {
        index == tabManager.selectedTabIndex || index == pendingExpandedTabBarIndex
    }
    
    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        tabOverviewPresentation.setVisible(visible, animated: animated)
    }
    
    func browse(to term: String) {
        tabManager.browse(to: term)
    }
    
    func openExternalURL(_ url: URL) {
        let targetController = activeContentController
        targetController.loadViewIfNeeded()
        targetController.prepareTabForExternalLoad()
        targetController.browse(to: url.absoluteString)
    }
    
    private var activeContentController: BrowserViewController {
        embeddedSplitController?.contentBrowserViewController ?? self
    }
    
    private func prepareTabForExternalLoad() {
        guard !tabManager.tabs.isEmpty else {
            tabManager.createInitialTab()
            return
        }
        
        if tabManager.tabs.count == 1 && tabManager.tabs[0].url == nil {
            return
        }
        
        _ = createTab(selecting: true, at: tabManager.tabs.count)
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
            if tabOverviewPresentation.isVisible {
                tabOverviewPresentation.setVisible(false, animated: false)
            }
            setSearchFocused(false, animated: false)
            view.endEditing(true)
        }
        
        isInFullscreenMedia = fullScreen
        browserUI.applyChromeLayout(animated: true)
        updateFullscreenOrientation(fullScreen)
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
