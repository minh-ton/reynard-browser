//
//  BrowserChrome.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BrowserChrome: UIView {
    private enum UX {
        static let overlayMinimumAddressBarPadding: CGFloat = 32
        static let overlayMinimumWidthRatio: CGFloat = 3.0 / 5.0
        static let overlayTopSpacing: CGFloat = 12
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
    }
    
    struct State {
        let position: BrowserChromePosition
        let mode: BrowserChromeMode
        let presentation: PresentationState
        let search: SearchState
        let topInset: CGFloat
        let interfaceIdiom: UIUserInterfaceIdiom
        let sidebarButtonVisible: Bool
    }
    
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?
    
    private let addressBar: AddressBar = {
        let view = AddressBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let topToolbar: TopToolbar
    private let bottomToolbar: BottomToolbar
    private let overlayContentView = ChromeOverlayContentView()
    
    private var bottomConstraint: NSLayoutConstraint!
    private var overlayWidthConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayTopConstraint: NSLayoutConstraint?
    private var overlayCenterXConstraint: NSLayoutConstraint?
    
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
        overlayWidthConstraint.constant = max(
            addressBar.bounds.width + UX.overlayMinimumAddressBarPadding,
            bounds.width * UX.overlayMinimumWidthRatio
        )
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
        configureOverlayPositioningIfNeeded()
        
        let topState: TopToolbar.LayoutState
        let bottomState: BottomToolbar.LayoutState
        if state.presentation != .browsing {
            topState = .hidden
            bottomState = .hidden
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
            state.search == .focused && state.presentation == .browsing,
            animated: false
        )
    }
    
    func dockAddressBar(offset: CGFloat) {
        bottomConstraint.constant = offset
        bottomToolbar.setVerticalOffset(offset)
    }
    
    // MARK: - Overlay Content
    
    func setOverlayPresentation(
        _ presentation: ChromeOverlayContentView.PresentationState,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        overlayContentView.setPresentation(presentation, animated: animated, completion: completion)
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
    
    func resetHorizontalTransition() { addressBar.resetHorizontalTransition() }
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
    }
    
    // MARK: - Transitions
    
    func bottomToolbarSnapshot() -> UIView? {
        return bottomToolbar.snapshotView(afterScreenUpdates: false)
    }
    
    func bottomToolbarFrame(in view: UIView) -> CGRect {
        return bottomToolbar.convert(bottomToolbar.bounds, to: view)
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
        addSubview(overlayContentView)
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
            
            overlayWidthConstraint,
            overlayHeightConstraint,
        ])
        bottomToolbar.configureTopAnchor(to: safeAreaLayoutGuide.bottomAnchor)
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
