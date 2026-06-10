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
    static var searchController = 0
    static var searchViewController = 0
    static var isSearchFocused = 0
    static var searchScrollDismissal = 0
    static var preserveSuggestions = 0
    static var suggestionsTop = 0
    static var suggestionsBottom = 0
    static var suggestionsLeading = 0
    static var suggestionsTrailing = 0
    static var suggestionsCenterX = 0
    static var suggestionsWidth = 0
    static var suggestionsHeight = 0
    static var suggestionsContentHeight = 0
    static var searchScrollMode = 0
    static var autocompleteDeleteText = 0
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
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
    
    var usesDetachedSuggestions: Bool {
        if usesCompactPadChrome {
            return false
        }
        
        if isPad {
            return true
        }
        
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
    
    var autocompleteDeleteText: String? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.autocompleteDeleteText) as? String
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.autocompleteDeleteText, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
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
        
        let shareEnabled = tabManager.shareableURL(for: tab) != nil
        browserUI.browserChrome.updateNavigation(
            canGoBack: tab.canNavigateBack,
            canGoForward: tab.canNavigateForward,
            canShare: shareEnabled
        )
    }
    
    @objc func addressBarPositionDidChange() {
        browserUI.applyChromeLayout(animated: true)
        searchViewController.setUsesTopAddressBarMode(usesTopPhoneAddressBar)
        searchViewController.setUsesPadChromeMode(usesPadChrome)
        updateSuggestionsLayoutIfNeeded()
    }
    
    @objc func landscapeTabBarDidChange() {
        browserUI.applyChromeLayout(animated: true)
        searchViewController.setUsesTopAddressBarMode(usesTopPhoneAddressBar)
        searchViewController.setUsesPadChromeMode(usesPadChrome)
        updateSuggestionsLayoutIfNeeded()
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
        let shouldPreserveSearchComposingText = isSearchScrollMode && searchViewController.parent != nil
        if !browserUI.browserChrome.isAddressBarEditing && !shouldPreserveSearchComposingText {
            browserUI.browserChrome.setAddressBarText(
                displayedText,
                locationText: selectedURL,
                locationTitle: selectedTab?.title,
                showsBarMenu: !hasPendingDisplayText && selectedURL?.isEmpty == false
            )
        }
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
        tabBar = TabBar()
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
    
    func applyChromeLayout(animated: Bool) {
        updateChromeLayoutState()
        
        let layoutBlock = {
            self.controller.view.layoutIfNeeded()
            self.controller.browserUI.tabOverview.collection.applyPresentationTransforms()
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
        
        let shouldShowContentBehindKeyboard = !pad
        && controller.isSearchFocused
        && keyboardHeight > 0
        && !controller.browserUI.tabOverview.isPresented
        let shouldPinSearchFocusedContentFrame = !pad
        && controller.isSearchFocused
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
            search: resolvedChromeSearchState(),
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
    
    private func resolvedChromeSearchState() -> BrowserChrome.SearchState {
        guard controller.isSearchFocused else { return .inactive }
        guard controller.isSearchScrollMode,
              controller.searchViewController.parent != nil else {
            return .focused
        }
        return controller.usesDetachedSuggestions
            ? .scrollingDetachedSuggestions
            : .scrollingEmbeddedSuggestions
    }
    
    func setSearchFocused(_ focused: Bool, animated: Bool) {
        controller.isSearchFocused = focused
        if focused {
            resetFocusedInputRelocation()
        }
        updateChromeLayoutState()
        
        let animations = {
            self.controller.view.layoutIfNeeded()
        }
        
        if animated {
            UIView.animate(withDuration: 0.2, animations: animations)
        } else {
            animations()
        }
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
        && controller.isSearchFocused
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
        guard !controller.isSearchFocused,
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
    
    private func resetFocusedInputRelocation() {
        focusedInputMetricsTask?.cancel()
        focusedInputMetricsTask = nil
        focusedInputBottomRatio = nil
        contentPhoneVerticalOffset = 0
    }
    
    private func resolvedContentPhoneVerticalOffset(
        shouldShowContentBehindKeyboard: Bool
    ) -> CGFloat {
        guard !controller.isSearchFocused,
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
        if visible && usesDetachedSuggestions {
            hideSuggestionsNow()
        }
        browserUI.tabOverview.setPresented(visible, animated: animated)
    }
}

// Search Suggestions
extension BrowserViewController: SearchViewControllerDelegate {
    var searchController: SearchController {
        if let controller = objc_getAssociatedObject(self, &UIAssociatedKeys.searchController) as? SearchController {
            return controller
        }
        
        let controller = SearchController(controller: self)
        objc_setAssociatedObject(self, &UIAssociatedKeys.searchController, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }
    
    var searchViewController: SearchViewController {
        if let controller = objc_getAssociatedObject(self, &UIAssociatedKeys.searchViewController) as? SearchViewController {
            return controller
        }
        
        let controller = SearchViewController()
        controller.delegate = self
        controller.overlayContentHeightDidChange = { [weak self] contentHeight in
            self?.suggestionsContentHeight = contentHeight
            self?.updateDetachedSuggestionsHeight()
        }
        objc_setAssociatedObject(self, &UIAssociatedKeys.searchViewController, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }
    
    var isSuggestionScrollDismissal: Bool {
        get {
            (objc_getAssociatedObject(self, &UIAssociatedKeys.searchScrollDismissal) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.searchScrollDismissal, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var preserveSuggestionsOnFocus: Bool {
        get {
            (objc_getAssociatedObject(self, &UIAssociatedKeys.preserveSuggestions) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.preserveSuggestions, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsTop: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsTop) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsTop, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsBottom: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsBottom) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsBottom, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsLeading: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsLeading) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsLeading, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsTrailing: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsTrailing) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsTrailing, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsCenterX: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsCenterX) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsCenterX, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsWidth: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsWidth) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsWidth, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsHeight: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsHeight) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsHeight, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var suggestionsContentHeight: CGFloat {
        get {
            CGFloat((objc_getAssociatedObject(self, &UIAssociatedKeys.suggestionsContentHeight) as? NSNumber)?.doubleValue ?? 0)
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.suggestionsContentHeight, NSNumber(value: Double(newValue)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var isSearchScrollMode: Bool {
        get {
            (objc_getAssociatedObject(self, &UIAssociatedKeys.searchScrollMode) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(self, &UIAssociatedKeys.searchScrollMode, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    func addressBarDidSubmit(_ searchTerm: String) {
        browse(to: searchTerm)
        view.endEditing(true)
    }

    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        dismissKeyboard()
    }

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
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        refreshAddressBar()
        isSearchScrollMode = false
        updateSuggestionsLayoutIfNeeded()
        if preserveSuggestionsOnFocus {
            preserveSuggestionsOnFocus = false
            showSuggestionsIfNeeded()
        } else {
            searchController.clearSuggestions()
        }
        setSearchFocused(true, animated: true)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool) {
        autocompleteDeleteText = isDelete && previousText.count > text.count ? text : nil
        guard !text.isEmpty else {
            hideSuggestionsIfNeeded {
                self.searchController.clearSuggestions()
            }
            return
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            hideSuggestionsIfNeeded()
            searchController.fetchSuggestions(for: text)
            return
        }
        
        showSuggestionsIfNeeded()
        searchController.fetchSuggestions(for: text)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if isSuggestionScrollDismissal {
            isSuggestionScrollDismissal = false
            preserveSuggestionsOnFocus = true
            isSearchScrollMode = true
            browserUI.browserChrome.setAddressBarEditingState(.composing)
            browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(true)
            updateSuggestionsLayoutIfNeeded()
            browserUI.applyChromeLayout(animated: false)
            return
        }
        
        refreshAddressBar()
        hideSuggestionsIfNeeded {
            self.searchController.clearSuggestions()
        }
        if !browserUI.browserChrome.isAddressBarEditing {
            setSearchFocused(false, animated: true)
        }
    }
    
    func searchViewControllerDidStartScrolling(_ controller: SearchViewController) {
        guard browserUI.browserChrome.isAddressBarEditing else {
            return
        }
        
        isSuggestionScrollDismissal = true
        browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(browserUI.browserChrome.isShowingAddressBarAutocomplete)
        browserUI.browserChrome.resignAddressBarFirstResponder()
    }
    
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, match: SearchAuxiliaryMatch?) {
        if isSearchScrollMode {
            restoreSearchChrome(clearSuggestions: true)
        }
        
        view.endEditing(true)
        if let match,
           match.kind == .tab,
           let tabID = match.tabID {
            switchToSearchTab(id: tabID)
            return
        }
        
        browse(to: suggestion)
    }
    
    func updateAddressBarAutocomplete(for query: String, primaryMatch: SearchAuxiliaryMatch?) {
        guard browserUI.browserChrome.isAddressBarEditing else {
            browserUI.browserChrome.clearAddressBarAutocomplete()
            return
        }
        
        let currentText = browserUI.browserChrome.addressBarText() ?? ""
        guard !query.isEmpty,
              currentText == query,
              autocompleteDeleteText != query,
              let primaryMatch,
              let autocomplete = autocompletePresentation(for: primaryMatch, query: query) else {
            browserUI.browserChrome.clearAddressBarAutocomplete()
            return
        }
        
        browserUI.browserChrome.setAddressBarAutocomplete(
            displayText: autocomplete.displayText,
            committedText: autocomplete.committedText,
            submissionText: autocomplete.submissionText
        )
    }
    
    func restoreSearchChrome(clearSuggestions: Bool) {
        preserveSuggestionsOnFocus = false
        isSearchScrollMode = false
        browserUI.browserChrome.setAddressBarEditingState(.inactive)
        browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(false)
        hideSuggestionsIfNeeded {
            if clearSuggestions {
                self.searchController.clearSuggestions()
            }
        }
        if !browserUI.browserChrome.isAddressBarEditing {
            setSearchFocused(false, animated: true)
        }
        refreshAddressBar()
    }
    
    private func showSuggestionsIfNeeded() {
        let overlayController = searchViewController
        let text = browserUI.browserChrome.addressBarText() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              overlayController.parent == nil else {
            return
        }
        overlayController.setUsesTopAddressBarMode(usesTopPhoneAddressBar)
        overlayController.setUsesPadChromeMode(usesPadChrome)
        overlayController.setUsesDetachedOverlayAppearance(usesDetachedSuggestions)
        
        overlayController.view.translatesAutoresizingMaskIntoConstraints = false
        overlayController.view.alpha = 0
        addChild(overlayController)
        if usesDetachedSuggestions {
            view.addSubview(overlayController.view)
        } else {
            view.insertSubview(overlayController.view, aboveSubview: browserUI.contentView)
        }
        overlayController.didMove(toParent: self)
        updateSuggestionsLayoutIfNeeded()
        UIView.animate(withDuration: 0.12) {
            overlayController.view.alpha = 1
        }
    }
    
    private func hideSuggestionsIfNeeded(afterHide: (() -> Void)? = nil) {
        let overlayController = searchViewController
        guard overlayController.parent != nil else {
            afterHide?()
            return
        }
        
        overlayController.view.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.12, animations: {
            overlayController.view.alpha = 0
        }) { _ in
            self.removeSuggestions()
            afterHide?()
        }
    }
    
    func hideSuggestionsNow() {
        let overlayController = searchViewController
        guard overlayController.parent != nil else {
            return
        }
        
        overlayController.view.layer.removeAllAnimations()
        removeSuggestions()
    }
    
    func updateSuggestionsLayoutIfNeeded() {
        let overlayController = searchViewController
        guard overlayController.parent != nil else {
            return
        }
        overlayController.setUsesTopAddressBarMode(usesTopPhoneAddressBar)
        overlayController.setUsesPadChromeMode(usesPadChrome)
        overlayController.setUsesDetachedOverlayAppearance(usesDetachedSuggestions)
        
        clearSuggestionLayoutConstraints()
        if usesDetachedSuggestions {
            view.bringSubviewToFront(overlayController.view)
            overlayController.view.layer.cornerCurve = .continuous
            overlayController.view.clipsToBounds = false
            overlayController.view.backgroundColor = .clear
            let shadowColor: UIColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
            overlayController.view.layer.shadowColor = shadowColor.cgColor
            overlayController.view.layer.shadowOpacity = 0.16
            overlayController.view.layer.shadowOffset = CGSize(width: 0, height: 8)
            
            if #available(iOS 26.0, *) {
                overlayController.view.layer.cornerRadius = 36
                overlayController.view.layer.shadowRadius = 36
            } else {
                overlayController.view.layer.cornerRadius = 12
                overlayController.view.layer.shadowRadius = 12
            }
            
            view.layoutIfNeeded()
            let top = overlayController.view.topAnchor.constraint(equalTo: browserUI.browserChrome.addressBarBottomAnchor, constant: 12)
            let barFrame = browserUI.browserChrome.addressBarFrame(in: view)
            let centerX = overlayController.view.centerXAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: barFrame.midX
            )
            let maxWidth = max(barFrame.width + 32, view.bounds.width * (3.0 / 5.0))
            let width = overlayController.view.widthAnchor.constraint(equalToConstant: maxWidth)
            let height = overlayController.view.heightAnchor.constraint(equalToConstant: detachedSuggestionsHeight())
            
            suggestionsTop = top
            suggestionsCenterX = centerX
            suggestionsWidth = width
            suggestionsHeight = height
            NSLayoutConstraint.activate([
                top,
                centerX,
                width,
                height,
            ])
        } else {
            overlayController.view.layer.cornerRadius = 0
            overlayController.view.clipsToBounds = false
            overlayController.view.backgroundColor = .clear
            overlayController.view.layer.shadowOpacity = 0
            overlayController.view.layer.shadowRadius = 0
            overlayController.view.layer.shadowOffset = .zero
            overlayController.view.layer.shadowPath = nil
            
            let top = overlayController.view.topAnchor.constraint(equalTo: suggestionsTopAnchor())
            let bottom = overlayController.view.bottomAnchor.constraint(equalTo: suggestionsBottomAnchor())
            let leading = overlayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let trailing = overlayController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            
            suggestionsTop = top
            suggestionsBottom = bottom
            suggestionsLeading = leading
            suggestionsTrailing = trailing
            NSLayoutConstraint.activate([
                top,
                leading,
                trailing,
                bottom,
            ])
        }
        view.layoutIfNeeded()
        overlayController.view.layer.shadowPath = usesDetachedSuggestions ? UIBezierPath(roundedRect: overlayController.view.bounds, cornerRadius: 24).cgPath : nil
    }
    
    private func updateDetachedSuggestionsHeight() {
        guard usesDetachedSuggestions,
              searchViewController.parent != nil,
              let height = suggestionsHeight else {
            return
        }
        
        let newHeight = detachedSuggestionsHeight()
        guard abs(height.constant - newHeight) > 0.5 else {
            return
        }
        
        height.constant = newHeight
        view.layoutIfNeeded()
        searchViewController.view.layer.shadowPath = UIBezierPath(
            roundedRect: searchViewController.view.bounds,
            cornerRadius: 24
        ).cgPath
    }
    
    private func clearSuggestionLayoutConstraints() {
        suggestionsTop?.isActive = false
        suggestionsBottom?.isActive = false
        suggestionsLeading?.isActive = false
        suggestionsTrailing?.isActive = false
        suggestionsCenterX?.isActive = false
        suggestionsWidth?.isActive = false
        suggestionsHeight?.isActive = false
    }
    
    private func removeSuggestions() {
        let overlayController = searchViewController
        overlayController.willMove(toParent: nil)
        overlayController.view.removeFromSuperview()
        overlayController.removeFromParent()
        clearSuggestionLayoutConstraints()
        suggestionsTop = nil
        suggestionsBottom = nil
        suggestionsLeading = nil
        suggestionsTrailing = nil
        suggestionsCenterX = nil
        suggestionsWidth = nil
        suggestionsHeight = nil
        browserUI.browserChrome.setAddressBarEditingState(.inactive)
        browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(false)
        if isSearchScrollMode {
            isSearchScrollMode = false
            browserUI.applyChromeLayout(animated: false)
        }
    }
    
    private func switchToSearchTab(id: UUID) {
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard let index = activeTabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        selectTab(at: index, animated: true)
    }
    
    private func suggestionsTopAnchor() -> NSLayoutYAxisAnchor {
        usesTopPhoneAddressBar || usesCompactPadChrome ? browserUI.browserChrome.topToolbarBottomAnchor : view.topAnchor
    }
    
    private func suggestionsBottomAnchor() -> NSLayoutYAxisAnchor {
        if usesTopPhoneAddressBar || usesCompactPadChrome {
            return view.bottomAnchor
        }
        
        return isSearchScrollMode ? browserUI.browserChrome.bottomToolbarTopAnchor : view.bottomAnchor
    }
    
    private func detachedSuggestionsHeight() -> CGFloat {
        let maximumHeight = browserUI.contentView.bounds.height * (9.0 / 10.0)
        return min(suggestionsContentHeight, maximumHeight)
    }
    
    private func autocompletePresentation(
        for primaryMatch: SearchAuxiliaryMatch,
        query: String
    ) -> (displayText: NSAttributedString, committedText: String, submissionText: String)? {
        let title = primaryMatch.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedURL = strippedURLString(primaryMatch.url.absoluteString, trimsTrailingSlash: true)
        let firstPartAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label]
        let completionAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.systemGray4
        ]
        let suffixAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemBlue,
            .backgroundColor: UIColor.systemGray4
        ]
        
        if title.hasPrefix(query) {
            let attributed = NSMutableAttributedString(
                string: String(title.prefix(query.count)),
                attributes: firstPartAttributes
            )
            let completion = String(title.dropFirst(query.count))
            if !completion.isEmpty {
                attributed.append(NSAttributedString(string: completion, attributes: completionAttributes))
            }
            attributed.append(NSAttributedString(string: " — \(strippedURL)", attributes: suffixAttributes))
            return (attributed, strippedURL, primaryMatch.url.absoluteString)
        }
        
        let strippedQuery = strippedURLMatchString(query)
        let strippedURLMatchValue = strippedURLMatchString(primaryMatch.url.absoluteString)
        guard !strippedQuery.isEmpty else {
            return nil
        }
        
        let completedURL: String
        if strippedURLMatchValue.hasPrefix(strippedQuery) {
            completedURL = autocompleteURLString(for: query, url: primaryMatch.url) ?? strippedURL
        } else if let matchedDomain = domainCompletion(for: strippedQuery, url: primaryMatch.url) {
            completedURL = matchedDomain
        } else {
            return nil
        }
        
        let attributed = NSMutableAttributedString(
            string: String(query.prefix(query.count)),
            attributes: firstPartAttributes
        )
        let completion = String(completedURL.dropFirst(query.count))
        if !completion.isEmpty {
            attributed.append(NSAttributedString(string: completion, attributes: completionAttributes))
        }
        attributed.append(NSAttributedString(string: " — \(title)", attributes: suffixAttributes))
        return (attributed, completedURL, primaryMatch.url.absoluteString)
    }
    
    private func autocompleteURLString(for query: String, url: URL) -> String? {
        let loweredQuery = query.lowercased()
        for value in autocompleteURLVariants(for: url) {
            if value.lowercased().hasPrefix(loweredQuery) {
                return value
            }
        }
        
        return nil
    }
    
    private func autocompleteURLVariants(for url: URL) -> [String] {
        let fullURL = trimmedURLString(url.absoluteString)
        let schemeStrippedURL = strippedURLString(url.absoluteString, trimsWWW: false, trimsTrailingSlash: true)
        let normalizedURL = strippedURLString(url.absoluteString, trimsTrailingSlash: true)
        return [fullURL, schemeStrippedURL, normalizedURL]
    }
    
    private func strippedURLString(
        _ value: String,
        trimsWWW: Bool = true,
        trimsTrailingSlash: Bool = false
    ) -> String {
        let lowered = value.lowercased()
        var strippedValue: String
        if lowered.hasPrefix("https://") {
            strippedValue = String(value.dropFirst("https://".count))
        } else if lowered.hasPrefix("http://") {
            strippedValue = String(value.dropFirst("http://".count))
        } else if lowered.hasPrefix("ftp://") {
            strippedValue = String(value.dropFirst("ftp://".count))
        } else {
            strippedValue = value
        }
        
        if trimsWWW, strippedValue.lowercased().hasPrefix("www.") {
            strippedValue = String(strippedValue.dropFirst("www.".count))
        }
        
        return trimsTrailingSlash ? trimmedURLString(strippedValue) : strippedValue
    }
    
    private func trimmedURLString(_ value: String) -> String {
        if value.count > 1, value.hasSuffix("/") {
            return String(value.dropLast())
        }
        
        return value
    }
    
    private func strippedURLMatchString(_ value: String) -> String {
        let lowered = value.lowercased()
        if lowered.hasPrefix("https://") {
            return String(lowered.dropFirst("https://".count))
        }
        
        if lowered.hasPrefix("http://") {
            return String(lowered.dropFirst("http://".count))
        }
        
        if lowered.hasPrefix("ftp://") {
            return String(lowered.dropFirst("ftp://".count))
        }
        
        return lowered
    }
    
    private func domainCompletion(for query: String, url: URL) -> String? {
        let displayURL = strippedURLString(url.absoluteString, trimsTrailingSlash: true)
        var host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst("www.".count))
        }
        guard !host.isEmpty,
              displayURL.lowercased().hasPrefix(host.lowercased()) else {
            return nil
        }
        
        let hostWithDotPrefix = ".\(host)"
        guard let range = hostWithDotPrefix.range(of: ".\(query)", options: .caseInsensitive),
              let dotRange = hostWithDotPrefix[range.lowerBound...].firstIndex(of: ".") else {
            return nil
        }
        
        let matchedHost = String(hostWithDotPrefix[hostWithDotPrefix.index(after: dotRange)...])
        guard matchedHost.contains(".") else {
            return nil
        }
        
        let path = String(displayURL.dropFirst(host.count))
        return matchedHost + path
    }
}
