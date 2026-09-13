//
//  BrowserChrome.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BrowserChrome: UIView, UIGestureRecognizerDelegate {
    private enum UX {
        static let overlayTopSpacing: CGFloat = 12
        static let actionBarSpacing: CGFloat = 0
        static let actionBarAnimationDuration: TimeInterval = 0.12
        static let minimizedToolbarContentHeight: CGFloat = 24
        static let minimizedTextFontSize: CGFloat = 13
        static let textShrinkTravelFraction: CGFloat = 0.75
        static let toolbarContentFadeDuration: TimeInterval = 0.12
    }
    
    enum PresentationState {
        case browsing
        case tabOverview
        case fullscreenMedia
    }
    
    enum SearchState {
        case inactive
        case focused
        case scrollingEmbeddedSuggestions
        case scrollingDetachedSuggestions
        
        var showsAddressBarDismissButton: Bool {
            switch self {
            case .inactive:
                return false
            case .focused, .scrollingEmbeddedSuggestions, .scrollingDetachedSuggestions:
                return true
            }
        }
    }
    
    struct State {
        let position: BrowserChromePosition
        let mode: BrowserChromeMode
        let presentation: PresentationState
        let search: SearchState
        let topInset: CGFloat
        let interfaceIdiom: UIUserInterfaceIdiom
        let orientation: BrowserLayout.ViewportOrientation
        let isTwoThirdSplitScreenOrSmaller: Bool
        let sidebarButtonVisible: Bool
        let animatesChromeStateChanges: Bool
    }
    
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?
    var onOverlayDismiss: (() -> Void)?
    var onPageZoomOut: (() -> Void)?
    var onPageZoomIn: (() -> Void)?
    var onPageZoomReset: (() -> Void)?
    var onFindInPage: ((_ query: String?, _ backwards: Bool) async -> (current: Int, total: Int)?)?
    var onClearFindInPage: (() -> Void)?
    var onFindInPageVisibilityChanged: ((Bool) -> Void)?
    var onKeyboardDismissal: (() -> Void)?
    var onToolbarExpansionRequested: (() -> Void)?
    
    let addressBar: AddressBar = {
        let view = AddressBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let tabBar = TabBar()
    private let topToolbar: TopToolbar
    private let bottomToolbar: BottomToolbar
    
    private let toolbarTextLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        label.isHidden = true
        label.isAccessibilityElement = false
        return label
    }()
    
    private let overlayDismissView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()
    
    private let overlayContentView = ChromeOverlayContentView()
    private let actionBar = ActionBar()
    
    private var overlayWidthConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayTopConstraint: NSLayoutConstraint?
    private var overlayCenterXConstraint: NSLayoutConstraint?
    private var actionBarTopConstraint: NSLayoutConstraint?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    private var actionBarKeyboardBottomConstraint: NSLayoutConstraint?
    private var actionBarDockOffset: CGFloat = 0
    
    private var state: State?
    private var toolbarCollapseProgress: CGFloat = 0
    private var toolbarTextCenterProgress: CGFloat = 0
    private var isToolbarContentHidden = false
    private var toolbarContentAlphas: (top: CGFloat, bottom: CGFloat) = (1, 1)
    
    // MARK: - Lifecycle
    
    init() {
        topToolbar = TopToolbar()
        bottomToolbar = BottomToolbar()
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureToolbarActions()
        configureOverlayDismissGesture()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hitView = bottomToolbar.hitTestAddressBar(
            at: bottomToolbar.convert(point, from: self),
            with: event
        ) {
            return hitView
        }
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateOverlayWidth()
    }
    
    // MARK: - Anchors And Frames
    
    var topToolbarBottomAnchor: NSLayoutYAxisAnchor {
        return topToolbar.bottomAnchor
    }
    
    var tabBarBottomAnchor: NSLayoutYAxisAnchor {
        return tabBar.bottomAnchor
    }
    
    var bottomToolbarTopAnchor: NSLayoutYAxisAnchor {
        return bottomToolbar.topAnchor
    }
    
    var addressBarBottomAnchor: NSLayoutYAxisAnchor {
        return addressBar.bottomAnchor
    }
    
    func minimizedToolbarHeight(for mode: BrowserChromeMode) -> CGFloat {
        let inset = mode == .phone ? safeAreaInsets.bottom : (state?.topInset ?? safeAreaInsets.top)
        return inset + UX.minimizedToolbarContentHeight
    }
    
    func addressBarFrame(in view: UIView) -> CGRect {
        return addressBar.convert(addressBar.bounds, to: view)
    }
    
    func sharePopoverSourceView() -> UIView {
        guard let state else { return bottomToolbar.sharePopoverSourceView() }
        return state.mode == .phone
        ? bottomToolbar.sharePopoverSourceView()
        : topToolbar.sharePopoverSourceView()
    }
    
    var addressBarButton: AddressBarButton {
        return addressBar.addressBarButton
    }
    
    // MARK: - Layout
    
    func apply(state: State) {
        if self.state?.mode != state.mode {
            toolbarCollapseProgress = 0
            toolbarTextCenterProgress = 0
        }
        
        self.state = state
        addressBar.updateLayout(position: state.position, chromeMode: state.mode)
        attachAddressBar(for: state.mode)
        attachActionBar(for: state.mode)
        configureOverlayPositioningIfNeeded()
        overlayContentView.setLayoutMode(overlayLayoutMode(for: state))
        updateOverlayWidth()
        updateOverlayHeight()
        let canUseActionBar = state.presentation == .browsing && state.search == .inactive
        actionBar.isUserInteractionEnabled = canUseActionBar
        
        if !canUseActionBar {
            dismissActionBar(animated: false)
        }
        
        let topState: TopToolbar.LayoutState
        let bottomState: BottomToolbar.LayoutState
        if state.presentation != .browsing {
            topState = .hidden
            bottomState = state.mode == .compact ? .collapsed : .hidden
        } else {
            topState = resolvedTopState(for: state)
            bottomState = resolvedBottomState(for: state)
        }
        
        topToolbar.apply(
            state: topState,
            topInset: state.topInset,
            interfaceIdiom: state.interfaceIdiom,
            sidebarButtonVisible: state.sidebarButtonVisible
        )
        bottomToolbar.apply(
            state: bottomState,
            hidesButtons: state.search == .scrollingEmbeddedSuggestions
        )
        addressBar.setDismissButtonVisible(
            state.search.showsAddressBarDismissButton && state.presentation == .browsing,
            animated: state.animatesChromeStateChanges
        )
    }
    
    func dockAddressBar(offset: CGFloat) {
        bottomToolbar.setAddressBarDockOffset(offset)
    }
    
    func dockActionBar(offset: CGFloat) {
        actionBarDockOffset = offset
        if offset == 0 {
            actionBarKeyboardBottomConstraint?.isActive = false
            actionBarKeyboardBottomConstraint = nil
            actionBarBottomConstraint?.constant = -UX.actionBarSpacing
            actionBarBottomConstraint?.isActive = true
            actionBar.transform = CGAffineTransform(translationX: 0, y: bottomToolbar.transform.ty)
            return
        }
        
        actionBarBottomConstraint?.isActive = false
        if actionBarKeyboardBottomConstraint == nil {
            actionBarKeyboardBottomConstraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: offset
            )
        }
        actionBarKeyboardBottomConstraint?.constant = offset
        actionBarKeyboardBottomConstraint?.isActive = true
        actionBar.transform = .identity
    }
    
    var isShowingFindInPage: Bool {
        return actionBar.isShowingFindInPage
    }
    
    // MARK: - Action Bar
    
    var isShowingKeyboardDismissal: Bool {
        return actionBar.isShowingKeyboardDismissal
    }
    
    func showActionBar(_ item: ActionBar.Item, animated: Bool) {
        guard state?.presentation == .browsing,
              state?.search == .inactive else {
            return
        }
        
        let wasShowingFindInPage = actionBar.isShowingFindInPage
        actionBar.setItem(item)
        if wasShowingFindInPage != actionBar.isShowingFindInPage {
            onFindInPageVisibilityChanged?(actionBar.isShowingFindInPage)
        }
        showActionBar(animated: animated)
    }
    
    func dismissActionBar(animated: Bool) {
        guard !actionBar.isHidden else { return }
        
        dockActionBar(offset: 0)
        actionBar.prepareForDismissal()
        let wasShowingFindInPage = actionBar.isShowingFindInPage
        
        let finish = {
            self.actionBar.setItem(nil)
            if wasShowingFindInPage {
                self.onFindInPageVisibilityChanged?(false)
            }
        }
        
        guard animated else {
            actionBar.alpha = 0
            finish()
            return
        }
        
        UIView.animate(withDuration: UX.actionBarAnimationDuration, animations: {
            self.actionBar.alpha = 0
        }) { _ in
            finish()
        }
    }
    
    func setPageZoomLevel(_ level: Int) {
        actionBar.setPageZoomLevel(level)
    }
    
    func updatePageZoomLevel(_ level: Int) {
        guard !actionBar.isHidden,
              actionBar.item == .pageZoom else {
            return
        }
        
        actionBar.setPageZoomLevel(level)
    }
    
    func nextPageZoomLevel() -> Int {
        return actionBar.nextPageZoomLevel()
    }
    
    func previousPageZoomLevel() -> Int {
        return actionBar.previousPageZoomLevel()
    }
    
    // MARK: - Overlay Content
    
    func setOverlayPresentation(
        _ presentation: ChromeOverlayContentView.PresentationState,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        setOverlayDismissViewVisible(presentation != .hidden)
        overlayContentView.setPresentation(presentation, animated: animated) { [weak self] in
            self?.setOverlayDismissViewVisible(presentation != .hidden)
            completion?()
        }
    }
    
    func setOverlayHeightMode(_ heightMode: ChromeOverlayContentView.HeightMode) {
        overlayContentView.setHeightMode(heightMode)
        updateOverlayHeight()
    }
    
    func setOverlayContentHeight(_ contentHeight: CGFloat) {
        overlayContentView.setContentHeight(contentHeight)
        updateOverlayHeight()
    }
    
    func setOverlayAvailableContentHeight(_ availableContentHeight: CGFloat) {
        overlayContentView.setAvailableContentHeight(availableContentHeight)
        updateOverlayHeight()
    }
    
    func setOverlayController(
        _ viewController: UIViewController,
        for page: ChromeOverlayContentView.Page,
        in parentViewController: UIViewController
    ) {
        overlayContentView.setController(viewController, for: page, in: parentViewController)
    }
    
    func removeOverlayController(for page: ChromeOverlayContentView.Page) {
        overlayContentView.removeController(for: page)
    }
    
    private func updateOverlayHeight() {
        overlayHeightConstraint.constant = overlayContentView.resolvedHeight
    }
    
    private func updateOverlayWidth() {
        overlayWidthConstraint.constant = overlayContentView.layoutMode.resolvedWidth(addressBarWidth: addressBar.bounds.width)
    }
    
    private func overlayLayoutMode(for state: State) -> ChromeOverlayContentView.LayoutMode {
        switch (state.interfaceIdiom, state.orientation) {
        case (.pad, .portrait):
            return .padPortrait
        case (.pad, .landscape) where state.isTwoThirdSplitScreenOrSmaller:
            return .padConstrained
        case (.pad, .landscape):
            return .padLandscape
        default:
            return .phoneLandscape
        }
    }
    
    private func configureOverlayPositioningIfNeeded() {
        guard overlayTopConstraint?.isActive != true,
              overlayCenterXConstraint?.isActive != true else {
            return
        }
        
        NSLayoutConstraint.deactivate([overlayTopConstraint, overlayCenterXConstraint].compactMap { $0 })
        let topConstraint = overlayContentView.topAnchor.constraint(
            equalTo: addressBar.bottomAnchor,
            constant: UX.overlayTopSpacing
        )
        let centerXConstraint = overlayContentView.centerXAnchor.constraint(equalTo: addressBar.centerXAnchor)
        NSLayoutConstraint.activate([topConstraint, centerXConstraint])
        overlayTopConstraint = topConstraint
        overlayCenterXConstraint = centerXConstraint
    }
    
    // MARK: - Address Bar
    
    func configureAddressBar(
        delegate: AddressBarDelegate,
        searchDelegate: AddressBarSearchDelegate,
        gestureDelegate: AddressBarGestureDelegate
    ) {
        addressBar.configure(
            delegate: delegate,
            searchDelegate: searchDelegate,
            gestureDelegate: gestureDelegate
        )
    }
    
    func setAddressBarText(
        _ text: String?,
        locationText: String?,
        locationTitle: String?,
        showsBarMenu: Bool
    ) {
        addressBar.setText(
            text,
            locationText: locationText,
            locationTitle: locationTitle,
            showsBarMenu: showsBarMenu
        )
        _ = updateToolbarTextTransition(textCenterProgress: toolbarTextCenterProgress)
    }
    
    func updateAddressBarMenu(url: String?, usesDesktopWebsite: Bool?) {
        addressBar.updateMenu(url: url, usesDesktopWebsite: usesDesktopWebsite)
    }
    
    func setAddressBarLoadingProgress(_ progress: Float, isLoading: Bool) {
        addressBar.setLoadingProgress(progress, isLoading: isLoading)
    }
    
    func setAddressBarEditingState(_ state: AddressBar.EditingState) {
        addressBar.setEditingState(state)
    }
    
    func setPreservesAddressBarAutocompleteAfterResign(_ preserves: Bool) {
        addressBar.setPreservesAutocompleteAfterResign(preserves)
    }
    
    func clearAddressBarAutocomplete() {
        addressBar.clearAutocomplete()
    }
    
    func recordAddressBarEdit(previousText: String, currentText: String, isDelete: Bool) {
        addressBar.recordEditForAutocomplete(previousText: previousText, currentText: currentText, isDelete: isDelete)
    }
    
    func applyAddressBarAutocomplete(query: String, result: UserDataSearchResult?, topDomain: String?) {
        addressBar.applySearchAutocomplete(query: query, result: result, topDomain: topDomain)
    }
    
    func resetAddressBarEditing() {
        _ = addressBar.resignFirstResponder()
        addressBar.clearAutocomplete()
        addressBar.setPreservesAutocompleteAfterResign(false)
        addressBar.setEditingState(.inactive)
    }
    
    func resetHorizontalTransition() { addressBar.resetHorizontalTransition() }
    
    func performAfterTransition(_ completion: @escaping () -> Void) -> Bool {
        addressBar.performAfterTransition(completion)
    }
    
    func resignAddressBarFirstResponder() { _ = addressBar.resignFirstResponder() }
    
    func performAfterAddressBarMenuDismissal(_ action: @escaping () -> Void) {
        addressBar.performAfterMenuDismissal(action)
    }
    
    func animateAutomaticNewTabTransition(to tab: Tab, completion: @escaping () -> Void) {
        addressBar.animateAutomaticNewTabTransition(to: tab, completion: completion)
    }
    
    var isAddressBarEditing: Bool { return addressBar.isEditingText }
    var isShowingAddressBarAutocomplete: Bool { return addressBar.isShowingAutocomplete }
    
    // MARK: - Toolbar Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        topToolbar.updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward, canShare: canShare)
        bottomToolbar.updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward, canShare: canShare)
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        topToolbar.configureNavigationMenus(itemsProvider: itemsProvider, onSelect: onSelect)
        bottomToolbar.configureNavigationMenus(itemsProvider: itemsProvider, onSelect: onSelect)
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        topToolbar.configureRecentlyClosedTabsMenu(
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        topToolbar.configureLibraryMenus(onSelect: onSelect)
        bottomToolbar.configureLibraryMenus(onSelect: onSelect)
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        topToolbar.configureTabOverviewMenus(
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
        bottomToolbar.configureTabOverviewMenus(
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        bottomToolbar.updateDownload(summary)
        topToolbar.updateDownload(summary)
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        topToolbar.setMenuButtonIndicatesUpdate(hasUpdate)
        bottomToolbar.setMenuButtonIndicatesUpdate(hasUpdate)
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        topToolbar.syncSidebarButton(splitViewController: splitViewController)
    }
    
    // MARK: - Action Wiring
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return toolbarCollapseProgress == 1 && state?.presentation == .browsing && state?.search == .inactive
    }
    
    private func configureToolbarActions() {
        for toolbar in [topToolbar as UIView, bottomToolbar] {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(expandToolbar))
            tapGesture.delegate = self
            toolbar.addGestureRecognizer(tapGesture)
        }
        
        topToolbar.onSidebar = { [weak self] in self?.onSidebar?() }
        topToolbar.onBack = { [weak self] in self?.onBack?() }
        topToolbar.onForward = { [weak self] in self?.onForward?() }
        topToolbar.onShare = { [weak self] in self?.onShare?() }
        topToolbar.onLibrary = { [weak self] in self?.onLibrary?() }
        topToolbar.onDownloads = { [weak self] in self?.onDownloads?() }
        topToolbar.onNewTab = { [weak self] in self?.onNewTab?() }
        topToolbar.onTabOverview = { [weak self] in self?.onTabOverview?() }
        
        bottomToolbar.onBack = { [weak self] in self?.onBack?() }
        bottomToolbar.onForward = { [weak self] in self?.onForward?() }
        bottomToolbar.onShare = { [weak self] in self?.onShare?() }
        bottomToolbar.onLibrary = { [weak self] in self?.onLibrary?() }
        bottomToolbar.onDownloads = { [weak self] in self?.onDownloads?() }
        bottomToolbar.onTabOverview = { [weak self] in self?.onTabOverview?() }
        
        actionBar.onPageZoomOut = { [weak self] in self?.onPageZoomOut?() }
        actionBar.onPageZoomIn = { [weak self] in self?.onPageZoomIn?() }
        actionBar.onPageZoomReset = { [weak self] in self?.onPageZoomReset?() }
        actionBar.onFindInPage = { [weak self] query, backwards in
            return await self?.onFindInPage?(query, backwards)
        }
        actionBar.onClearFindInPage = { [weak self] in self?.onClearFindInPage?() }
        actionBar.onClose = { [weak self] in self?.dismissActionBar(animated: true) }
        actionBar.onKeyboardDismissal = { [weak self] in self?.onKeyboardDismissal?() }
    }
    
    @objc private func expandToolbar() {
        onToolbarExpansionRequested?()
    }
    
    // MARK: - Transitions
    
    func bottomToolbarTransitionView() -> UIView? {
        return bottomToolbar.snapshotView(afterScreenUpdates: false)
    }
    
    func bottomToolbarTransitionFrame(in view: UIView) -> CGRect {
        return bottomToolbar.convert(bottomToolbar.bounds, to: view)
    }
    
    func topToolbarTransitionView() -> UIView? {
        return topToolbar.snapshotView(afterScreenUpdates: false)
    }
    
    func topToolbarTransitionFrame(in view: UIView) -> CGRect {
        return topToolbar.convert(topToolbar.bounds, to: view)
    }
    
    func setToolbarTransition(
        topOffset: CGFloat,
        bottomOffset: CGFloat,
        tabBarCollapseOffset: CGFloat,
        collapseProgress: CGFloat,
        textCenterProgress: CGFloat,
        isBottomToolbarCollapsed: Bool,
        animatesContent: Bool
    ) {
        topToolbar.transform = CGAffineTransform(translationX: 0, y: topOffset)
        topToolbar.setBackgroundCollapseOffset(tabBarCollapseOffset)
        bottomToolbar.transform = CGAffineTransform(translationX: 0, y: bottomOffset)
        actionBar.transform = actionBarKeyboardBottomConstraint == nil
        ? CGAffineTransform(translationX: 0, y: bottomOffset)
        : .identity
        let previousProgress = toolbarCollapseProgress
        toolbarCollapseProgress = collapseProgress
        toolbarTextCenterProgress = textCenterProgress
        let isTextFullSize = updateToolbarTextTransition(textCenterProgress: textCenterProgress)
        if collapseProgress == 0 || (collapseProgress < previousProgress && isTextFullSize) {
            isToolbarContentHidden = false
        } else if collapseProgress > previousProgress {
            isToolbarContentHidden = true
        }
        
        let contentAlpha: CGFloat = isToolbarContentHidden ? 0 : 1
        let topAlpha: CGFloat = state?.mode == .phone ? 1 : contentAlpha
        let bottomAlpha: CGFloat = isBottomToolbarCollapsed ? 0 : (state?.mode == .pad ? 1 : contentAlpha)
        guard !animatesContent || toolbarContentAlphas != (topAlpha, bottomAlpha) else {
            return
        }
        toolbarContentAlphas = (topAlpha, bottomAlpha)
        UIView.animate(
            withDuration: animatesContent ? UX.toolbarContentFadeDuration : 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.topToolbar.setContentAlpha(topAlpha)
            self.bottomToolbar.setContentAlpha(bottomAlpha)
        }
    }
    
    func setChromeTransition(topAlpha: CGFloat, bottomAlpha: CGFloat, bottomTranslationY: CGFloat = 0) {
        topToolbar.alpha = topAlpha
        bottomToolbar.alpha = bottomAlpha
        bottomToolbar.transform = CGAffineTransform(translationX: 0, y: bottomTranslationY)
        actionBar.transform = actionBarKeyboardBottomConstraint == nil
        ? CGAffineTransform(translationX: 0, y: bottomTranslationY)
        : .identity
    }
    
    func setBottomToolbarHidden(_ hidden: Bool) {
        bottomToolbar.isHidden = hidden
    }
    
    func sidebarButtonFrame(in view: UIView) -> CGRect {
        return topToolbar.sidebarButtonFrame(in: view)
    }
    
    func setSidebarButtonTransition(alpha: CGFloat, hidden: Bool) {
        topToolbar.setSidebarButtonTransition(alpha: alpha, hidden: hidden)
    }
    
    private func updateToolbarTextTransition(textCenterProgress: CGFloat) -> Bool {
        guard toolbarCollapseProgress > 0,
              let state,
              state.presentation == .browsing,
              state.search == .inactive,
              let presentation = addressBar.toolbarTextPresentation(in: self) else {
            toolbarTextLabel.isHidden = true
            addressBar.setDisplayTextHidden(false)
            return true
        }
        addressBar.setDisplayTextHidden(true)
        let isBottom = state.mode == .phone
        let toolbar = isBottom ? bottomToolbar as UIView : topToolbar
        let offset = toolbar.transform.ty
        let totalTravel = abs(offset) / toolbarCollapseProgress
        let expandedFrame = presentation.frame.offsetBy(dx: 0, dy: -offset)
        let minimizedTextCenterY = isBottom
        ? bounds.maxY - safeAreaInsets.bottom - UX.minimizedToolbarContentHeight / 2
        : state.topInset + UX.minimizedToolbarContentHeight / 2
        let minimizedScale = UX.minimizedTextFontSize / presentation.font.pointSize
        let minimizedTextHeight = presentation.font.lineHeight * minimizedScale
        let targetEdge = minimizedTextCenterY + (isBottom ? minimizedTextHeight : -minimizedTextHeight) / 2
        let edgeTravel = max(0, isBottom ? targetEdge - expandedFrame.maxY : expandedFrame.minY - targetEdge)
        // Pin the outer text edge before scaling, leaving the last part of the travel for the toolbar.
        let shrinkTravel = max(1, (totalTravel - edgeTravel) * UX.textShrinkTravelFraction)
        let shrinkProgress = min(max((abs(offset) - edgeTravel) / shrinkTravel, 0), 1)
        let scale = 1 + (minimizedScale - 1) * shrinkProgress
        let textHeight = presentation.font.lineHeight * scale
        let textEdge = isBottom ? min(presentation.frame.maxY, targetEdge) : max(presentation.frame.minY, targetEdge)
        toolbarTextLabel.font = presentation.font
        toolbarTextLabel.attributedText = presentation.text
        toolbarTextLabel.bounds = CGRect(x: 0, y: 0, width: expandedFrame.width, height: presentation.font.lineHeight)
        toolbarTextLabel.center = CGPoint(
            x: expandedFrame.midX + (bounds.midX - expandedFrame.midX) * textCenterProgress,
            y: textEdge + (isBottom ? -textHeight : textHeight) / 2
        )
        toolbarTextLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        toolbarTextLabel.alpha = toolbar.alpha
        toolbarTextLabel.isHidden = toolbar.isHidden
        return shrinkProgress == 0
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(topToolbar)
        addSubview(tabBar)
        addSubview(bottomToolbar)
        addSubview(toolbarTextLabel)
        addSubview(overlayDismissView)
        addSubview(overlayContentView)
        addSubview(actionBar)
    }
    
    private func configureConstraints() {
        overlayWidthConstraint = overlayContentView.widthAnchor.constraint(equalToConstant: 0)
        overlayHeightConstraint = overlayContentView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            topToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topToolbar.topAnchor.constraint(equalTo: topAnchor),
            
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            
            bottomToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            overlayDismissView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            overlayDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayDismissView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            
            overlayWidthConstraint,
            overlayHeightConstraint,
            
            actionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        topToolbar.extendBackground(to: tabBar.bottomAnchor)
        bottomToolbar.configureTopAnchor(to: safeAreaLayoutGuide.bottomAnchor)
    }
    
    private func configureOverlayDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(overlayDismissViewTapped))
        overlayDismissView.addGestureRecognizer(tapGesture)
    }
    
    private func setOverlayDismissViewVisible(_ visible: Bool) {
        overlayDismissView.isHidden = !visible
    }
    
    @objc private func overlayDismissViewTapped() {
        onOverlayDismiss?()
    }
    
    // MARK: - State Resolution
    
    private func attachAddressBar(for mode: BrowserChromeMode) {
        topToolbar.detachAddressBar()
        bottomToolbar.detachAddressBar()
        switch mode {
        case .phone:
            bottomToolbar.attachAddressBar(addressBar)
        case .compact, .pad:
            topToolbar.attachAddressBar(addressBar)
        }
    }
    
    private func attachActionBar(for mode: BrowserChromeMode) {
        NSLayoutConstraint.deactivate([
            actionBarTopConstraint,
            actionBarBottomConstraint,
            actionBarKeyboardBottomConstraint,
        ].compactMap { $0 })
        actionBarKeyboardBottomConstraint = nil
        switch mode {
        case .pad:
            let constraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -UX.actionBarSpacing
            )
            constraint.isActive = true
            actionBarBottomConstraint = constraint
            actionBarTopConstraint = nil
        case .phone, .compact:
            let constraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomToolbar.topAnchor,
                constant: -UX.actionBarSpacing
            )
            constraint.isActive = true
            actionBarBottomConstraint = constraint
            actionBarTopConstraint = nil
        }
        
        if actionBarDockOffset != 0 {
            actionBarBottomConstraint?.isActive = false
            actionBarKeyboardBottomConstraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: actionBarDockOffset
            )
            actionBarKeyboardBottomConstraint?.isActive = true
        }
    }
    
    private func showActionBar(animated: Bool) {
        actionBar.isHidden = false
        let animations = {
            self.actionBar.alpha = 1
        }
        
        guard animated else {
            animations()
            return
        }
        
        UIView.animate(withDuration: UX.actionBarAnimationDuration, animations: animations)
    }
    
    private func resolvedTopState(for state: State) -> TopToolbar.LayoutState {
        switch state.mode {
        case .phone: return .hidden
        case .compact: return .compact
        case .pad: return .standard
        }
    }
    
    private func resolvedBottomState(for state: State) -> BottomToolbar.LayoutState {
        switch state.mode {
        case .pad:
            return .hidden
        case .compact:
            return .compact
        case .phone:
            switch state.search {
            case .inactive, .focused, .scrollingEmbeddedSuggestions: return .standard
            case .scrollingDetachedSuggestions: return .hidden
            }
        }
    }
}
