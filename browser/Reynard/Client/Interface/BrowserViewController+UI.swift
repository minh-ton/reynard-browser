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
    static var browserUI = 0
}

extension BrowserViewController: AddressBarDelegate, AddressBarDataSource, AddressBarGesturesDelegate, BottomToolbarDelegate {
    var browserUI: BrowserUI {
        get {
            if let ui = objc_getAssociatedObject(self, &UIAssociatedKeys.browserUI) as? BrowserUI {
                return ui
            }

            let ui = BrowserUI(controller: self)
            objc_setAssociatedObject(self, &UIAssociatedKeys.browserUI, ui, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return ui
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.browserUI, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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

    var addressBarGestureController: BrowserViewController {
        self
    }

    @objc func applyUpdateMenuButtonBadge() {
        browserUI.browserChrome.setMenuButtonIndicatesUpdate(true)
    }

    func applyChromeLayout(animated: Bool) {
        browserUI.applyChromeLayout(animated: animated)
    }

    func updateNavigationButtons() {
        guard let tab = tabManager.selectedTab else {
            return
        }

        let shareEnabled = tabManager.shareableURL(for: tab) != nil
        browserUI.browserChrome.updateNavigation(
            canGoBack: tab.canNavigateBack,
            canGoForward: tab.canNavigateForward,
            canShare: shareEnabled
        )
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

    func tabPreviewAspectRatio() -> CGFloat {
        let bounds = browserUI.contentView.bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        return height / width
    }

    func captureThumbnail(for index: Int) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard !browserUI.contentView.isHidden,
              let tab = activeTabs[safe: index],
              browserUI.contentView.isDisplaying(session: tab.session) else {
            return
        }

        guard let image = browserUI.contentView.makeThumbnail() else {
            return
        }
        tabManager.updateThumbnail(image, forTabAt: index)
    }

    func dismissalContentFrame() -> CGRect {
        browserUI.contentView.frame
    }

    func syncAddressBarLoadingState(progress: Float, isLoading: Bool) {
        browserUI.browserChrome.setAddressBarLoadingProgress(progress, isLoading: isLoading)
    }

    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let pendingDisplayText = selectedTab?.pendingDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPendingDisplayText = !(pendingDisplayText?.isEmpty ?? true)
        let selectedURL = selectedTab?.url
        let displayedText = hasPendingDisplayText ? pendingDisplayText : selectedURL
        browserUI.browserChrome.setAddressBarText(
            displayedText,
            locationText: selectedURL,
            locationTitle: selectedTab?.title,
            showsBarMenu: !hasPendingDisplayText && selectedURL?.isEmpty == false
        )
        browserUI.browserChrome.setAddressBarLoadingProgress(selectedTab?.progress ?? 0, isLoading: selectedTab?.isLoading ?? false)
        addonController.prepareVisibleAddonIcons()
        browserUI.browserChrome.updateAddressBarMenu(selectedTab: selectedTab, url: selectedURL)
    }

    func addonItems(for addressBar: AddressBar) -> [AddressBarMenu.AddonItem] {
        addonController.visibleMenuItemsForCurrentSite().map { item in
            AddressBarMenu.AddonItem(menuItem: item, image: addonController.iconImage(for: item.addon))
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
    let contentView = ContentView()
    let browserChrome: BrowserChrome
    let overlayCoordinator: OverlayCoordinator
    let searchOverlayCoordinator: SearchOverlayCoordinator
    let tabBar: TabBar

    let tabOverview = TabOverview()

    private unowned let controller: BrowserViewController
    private var keyboardHeight: CGFloat = 0
    private var keyboardFrame: CGRect = .zero
    private var focusedInputBottomRatio: CGFloat?
    private var contentPhoneVerticalOffset: CGFloat = 0
    private var focusedInputMetricsTask: Task<Void, Never>?

    init(controller: BrowserViewController) {
        self.controller = controller
        browserChrome = BrowserChrome(controller: controller)
        overlayCoordinator = OverlayCoordinator(controller: controller)
        searchOverlayCoordinator = SearchOverlayCoordinator(
            controller: controller,
            overlayCoordinator: overlayCoordinator
        )
        tabBar = TabBar()
        browserChrome.configureAddressBarSearchDelegate(searchOverlayCoordinator)
        tabBar.dataSource = controller
        tabBar.delegate = controller
        tabOverview.dataSource = controller
        tabOverview.delegate = controller
    }

    deinit {
        focusedInputMetricsTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configureLayout() {
        let ui = controller.browserUI
        let view = controller.view!

        view.addSubview(ui.contentView)
        view.addSubview(ui.tabBar)
        view.addSubview(ui.browserChrome)
        view.addSubview(ui.tabOverview)

        NSLayoutConstraint.activate([
            ui.contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).withPriority(.defaultHigh),
            ui.contentView.bottomAnchor.constraint(equalTo: ui.browserChrome.bottomToolbarTopAnchor).withPriority(.defaultHigh),

            ui.browserChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.browserChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.browserChrome.topAnchor.constraint(equalTo: view.topAnchor),
            ui.browserChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            ui.tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.tabBar.topAnchor.constraint(equalTo: ui.browserChrome.topToolbarBottomAnchor),

            ui.tabOverview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui.tabOverview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ui.tabOverview.topAnchor.constraint(equalTo: view.topAnchor),
            ui.tabOverview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ].compactMap { $0 })
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

    func setTabOverviewPresented(_ presented: Bool, animated: Bool) {
        if presented {
            searchOverlayCoordinator.tabOverviewWillPresent()
        }
        tabOverview.setPresented(presented, animated: animated)
    }

    func applyChromeLayout(animated: Bool, duration: TimeInterval = 0.22) {
        updateChromeLayoutState()
        searchOverlayCoordinator.updateLayoutIfNeeded()

        let layoutBlock = {
            self.controller.view.layoutIfNeeded()
            self.controller.browserUI.tabOverview.collection.applyPresentationTransforms()
        }

        if animated {
            UIView.animate(withDuration: duration, animations: layoutBlock)
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

        let shouldShowContentBehindKeyboard = !pad
        && searchOverlayCoordinator.isFocused
        && keyboardHeight > 0
        && !controller.browserUI.tabOverview.isPresented
        let shouldPinSearchFocusedContentFrame = !pad
        && searchOverlayCoordinator.isFocused
        && !controller.browserUI.tabOverview.isPresented
        let contentPhoneOffset = resolvedContentPhoneVerticalOffset(
            shouldShowContentBehindKeyboard: shouldShowContentBehindKeyboard
        )
        let isLandscape: Bool
        if let orientation = controller.view.window?.windowScene?.interfaceOrientation {
            isLandscape = orientation.isLandscape
        } else {
            isLandscape = controller.view.bounds.width > controller.view.bounds.height
        }

        let contentLayoutMode: ContentView.LayoutState.Mode
        let contentTopAnchor: NSLayoutYAxisAnchor
        let contentBottomAnchor: NSLayoutYAxisAnchor
        if pad {
            contentLayoutMode = .standard
            contentTopAnchor = ui.tabBar.bottomAnchor
            contentBottomAnchor = compactPad ? ui.browserChrome.bottomToolbarTopAnchor : controller.view.bottomAnchor
        } else {
            contentLayoutMode = shouldPinSearchFocusedContentFrame ? .searchFocused : .standard
            contentTopAnchor = controller.view.safeAreaLayoutGuide.topAnchor
            contentBottomAnchor = shouldShowContentBehindKeyboard && !shouldPinSearchFocusedContentFrame
                ? controller.view.bottomAnchor
                : (shouldPinSearchFocusedContentFrame
                    ? controller.view.safeAreaLayoutGuide.bottomAnchor
                    : ui.browserChrome.bottomToolbarTopAnchor)
        }
        ui.contentView.applyLayout(
            ContentView.LayoutState(
                mode: contentLayoutMode,
                verticalOffset: contentPhoneOffset
            ),
            topAnchor: contentTopAnchor,
            bottomAnchor: contentBottomAnchor
        )

        let phoneOverview = controller.usesBottomPhoneOverview
        let activeTabs = controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        let supportsTabBar = pad && activeTabs.count > 1 && (!controller.isPad ? Prefs.AppearanceSettings.showsLandscapeTabBar && isLandscape : true)
        let tabBarVisibility: TabBar.Visibility
        if supportsTabBar {
            tabBarVisibility = controller.browserUI.tabOverview.isPresented ? .layoutReserved : .visible
        } else {
            tabBarVisibility = .hidden
        }
        ui.tabBar.setVisibility(tabBarVisibility, animated: false)

        ui.tabOverview.applyLayout(toolbarPosition: phoneOverview ? .bottom : .top, animated: false)
        ui.browserChrome.apply(state: BrowserChrome.State(
            position: controller.usesTopPhoneAddressBar ? .top : .bottom,
            mode: compactPad ? .compact : (pad ? .pad : .phone),
            presentation: controller.browserUI.tabOverview.isPresented ? .tabOverview : .browsing,
            search: searchOverlayCoordinator.chromeState,
            topInset: resolvedPadTopInset(),
            isPadLayout: controller.isPad,
            sidebarVisible: controller.isLibrarySidebarVisible
        ))

        controller.updateNavigationButtons()
    }

    private func applyMediaFullscreenLayoutState() {
        let ui = controller.browserUI
        let pad = controller.usesPadChrome

        ui.contentView.applyLayout(
            ContentView.LayoutState(
                mode: .fullscreen,
                verticalOffset: 0
            ),
            topAnchor: controller.view.topAnchor,
            bottomAnchor: controller.view.bottomAnchor
        )

        ui.tabBar.setVisibility(.hidden, animated: false)

        ui.tabOverview.applyLayout(toolbarPosition: controller.usesBottomPhoneOverview ? .bottom : .top, animated: false)
        ui.browserChrome.apply(state: BrowserChrome.State(
            position: controller.usesTopPhoneAddressBar ? .top : .bottom,
            mode: controller.usesCompactPadChrome ? .compact : (pad ? .pad : .phone),
            presentation: .fullscreenMedia,
            search: .inactive,
            topInset: resolvedPadTopInset(),
            isPadLayout: controller.isPad,
            sidebarVisible: controller.isLibrarySidebarVisible
        ))
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

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        updateKeyboardState(screenFrame: frameValue.cgRectValue)
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveRaw = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let curve = UIView.AnimationOptions(rawValue: curveRaw << 16)
        requestFocusedInputMetricsIfNeeded(duration: duration, curve: curve)

        let shouldDockChromeToKeyboard = !controller.usesPadChrome
        && searchOverlayCoordinator.isFocused
        && !controller.browserUI.tabOverview.isPresented
        && keyboardHeight > 0
        controller.browserUI.browserChrome.setBottomOffset(shouldDockChromeToKeyboard ? -keyboardHeight : 0)
        updateChromeLayoutState()

        UIView.animate(withDuration: duration, delay: 0, options: [curve]) {
            self.controller.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardHeight = 0
        keyboardFrame = .zero
        resetFocusedInputRelocation()
        controller.browserUI.browserChrome.setBottomOffset(0)
        updateChromeLayoutState()

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let curve = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: [curve]) {
            self.controller.view.layoutIfNeeded()
        }
    }

    private func updateKeyboardState(screenFrame: CGRect) {
        keyboardFrame = controller.view.convert(screenFrame, from: nil)
        let overlap = max(0, controller.view.bounds.maxY - keyboardFrame.minY)
        let safeBottom = controller.view.safeAreaInsets.bottom
        keyboardHeight = max(0, overlap - safeBottom)
    }

    private func requestFocusedInputMetricsIfNeeded(duration: TimeInterval, curve: UIView.AnimationOptions) {
        guard !searchOverlayCoordinator.isFocused,
              !controller.browserUI.tabOverview.isPresented,
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
        let nextOffset = resolvedContentPhoneVerticalOffset(
            shouldShowContentBehindKeyboard: false
        )
        guard abs(nextOffset - contentPhoneVerticalOffset) > 0.5 else {
            return
        }

        contentPhoneVerticalOffset = nextOffset
        updateChromeLayoutState()
        UIView.animate(withDuration: duration, delay: 0, options: [curve, .beginFromCurrentState, .allowUserInteraction]) {
            self.controller.view.layoutIfNeeded()
        }
    }

    func resetFocusedInputRelocation() {
        focusedInputMetricsTask?.cancel()
        focusedInputMetricsTask = nil
        focusedInputBottomRatio = nil
        contentPhoneVerticalOffset = 0
    }

    private func resolvedContentPhoneVerticalOffset(
        shouldShowContentBehindKeyboard: Bool
    ) -> CGFloat {
        guard !searchOverlayCoordinator.isFocused,
              !controller.browserUI.tabOverview.isPresented,
              !shouldShowContentBehindKeyboard,
              keyboardHeight > 0,
              let bottomRatio = focusedInputBottomRatio else {
            return 0
        }

        controller.view.layoutIfNeeded()
        let contentFrame = controller.browserUI.contentView.frame
        guard contentFrame.height > 1 else {
            return 0
        }

        let unshiftedContentMinY: CGFloat
        if controller.usesPadChrome {
            unshiftedContentMinY = controller.browserUI.tabBar.frame.maxY
        } else {
            unshiftedContentMinY = controller.view.safeAreaLayoutGuide.layoutFrame.minY
        }

        let currentContentShift = max(0, unshiftedContentMinY - contentFrame.minY)
        let unshiftedContentMaxY = contentFrame.maxY + currentContentShift
        let keyboardOverlap = max(0, unshiftedContentMaxY - keyboardFrame.minY)
        guard keyboardOverlap > 0 else {
            return 0
        }

        let focusBottom = contentFrame.height * bottomRatio
        let visibleBottom = max(0, contentFrame.height - keyboardOverlap - 12)
        return min(keyboardOverlap, max(0, focusBottom - visibleBottom))
    }
}

extension BrowserViewController {
    // MARK: - Tab Overview Forwarding

    func restoreTabOverviewMode() {
        let snapshot = TabManagementStore.shared.loadSnapshot()
        let restoredMode: TabMode
        if snapshot.selectedTabMode == .private, !snapshot.privateTabs.isEmpty {
            restoredMode = .private
        } else if snapshot.selectedTabMode == .regular, !snapshot.regularTabs.isEmpty {
            restoredMode = .regular
        } else if !snapshot.regularTabs.isEmpty {
            restoredMode = .regular
        } else if !snapshot.privateTabs.isEmpty {
            restoredMode = .private
        } else {
            restoredMode = .regular
        }
        browserUI.tabOverview.restoreMode(TabOverview.Mode(tabMode: restoredMode))
    }

    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        browserUI.setTabOverviewPresented(visible, animated: animated)
    }
}

extension BrowserViewController {
    func addressBar(_ addressBar: AddressBar, didSelectAddon item: AddonMenuItem) {
        addonController.presentCurrentSiteSettings(for: item)
    }

    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar) {
        changeWebsiteMode()
    }

    func addressBarDidRequestWebsiteSettings(_ addressBar: AddressBar) {
        presentWebsiteSettingsRequested()
    }

    func addressBar(_ addressBar: AddressBar, didRequestBookmarkInFavorites favorites: Bool) {
        presentBookmark(addToFavorites: favorites)
    }

}
