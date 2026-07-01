//
//  BrowserChrome.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BrowserChrome: UIView {
    private enum UX {
        static let overlayTopSpacing: CGFloat = 12
        static let actionBarSpacing: CGFloat = 0
        static let actionBarAnimationDuration: TimeInterval = 0.12
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
    
    private let addressBar: AddressBar = {
        let view = AddressBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let topToolbar: TopToolbar
    private let bottomToolbar: BottomToolbar
    private let overlayDismissView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()
    private let overlayContentView = ChromeOverlayContentView()
    private let actionBar = ActionBar()
    
    private var bottomConstraint: NSLayoutConstraint!
    private var overlayWidthConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayTopConstraint: NSLayoutConstraint?
    private var overlayCenterXConstraint: NSLayoutConstraint?
    private var actionBarTopConstraint: NSLayoutConstraint?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    
    private var state: State?
    
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
    
    var bottomToolbarTopAnchor: NSLayoutYAxisAnchor {
        return bottomToolbar.topAnchor
    }
    
    var addressBarBottomAnchor: NSLayoutYAxisAnchor {
        return addressBar.bottomAnchor
    }
    
    func addressBarFrame(in view: UIView) -> CGRect {
        return addressBar.convert(addressBar.bounds, to: view)
    }
    
    func sharePopoverSourceView() -> UIView {
        guard let state else { return bottomToolbar }
        return state.mode == .phone ? bottomToolbar : topToolbar
    }
    
    // MARK: - Layout
    
    func apply(state: State) {
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
        bottomConstraint.constant = offset
        bottomToolbar.setVerticalOffset(offset)
    }
    
    // MARK: - Action Bar
    
    func showActionBar(_ item: ActionBar.Item, animated: Bool) {
        guard state?.presentation == .browsing,
              state?.search == .inactive else {
            return
        }
        
        actionBar.setItem(item)
        showActionBar(animated: animated)
    }
    
    func dismissActionBar(animated: Bool) {
        guard !actionBar.isHidden else { return }
        
        let finish = {
            self.actionBar.setItem(nil)
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
    
    func applyAddressBarAutocomplete(query: String, result: UserDataSearchResult?) {
        addressBar.applySearchAutocomplete(query: query, result: result)
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
    
    private func configureToolbarActions() {
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
        actionBar.onClose = { [weak self] in self?.dismissActionBar(animated: true) }
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
    
    func setChromeTransition(topAlpha: CGFloat, bottomAlpha: CGFloat, bottomTranslationY: CGFloat = 0) {
        topToolbar.alpha = topAlpha
        bottomToolbar.alpha = bottomAlpha
        bottomToolbar.transform = CGAffineTransform(translationX: 0, y: bottomTranslationY)
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
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(topToolbar)
        addSubview(bottomToolbar)
        addSubview(overlayDismissView)
        addSubview(overlayContentView)
        addSubview(actionBar)
    }
    
    private func configureConstraints() {
        bottomConstraint = bottomToolbar.bottomAnchor.constraint(equalTo: bottomAnchor)
        overlayWidthConstraint = overlayContentView.widthAnchor.constraint(equalToConstant: 0)
        overlayHeightConstraint = overlayContentView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            topToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topToolbar.topAnchor.constraint(equalTo: topAnchor),
            
            bottomToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomConstraint,
            
            overlayDismissView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            overlayDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayDismissView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            
            overlayWidthConstraint,
            overlayHeightConstraint,
            
            actionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
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
        NSLayoutConstraint.deactivate([actionBarTopConstraint, actionBarBottomConstraint].compactMap { $0 })
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
            case .inactive: return .standard
            case .focused: return .focused
            case .scrollingEmbeddedSuggestions: return .standard
            case .scrollingDetachedSuggestions: return .hidden
            }
        }
    }
}
