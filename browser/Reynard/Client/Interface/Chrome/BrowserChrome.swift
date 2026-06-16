//
//  BrowserChrome.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BrowserChrome: UIView {
    // MARK: - State

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
        // Position controls AddressBar presentation; mode controls which toolbar physically hosts it.
        let position: browserChromePosition
        let mode: browserChromeMode
        let presentation: PresentationState
        let search: SearchState
        let topInset: CGFloat
        let interfaceIdiom: UIUserInterfaceIdiom
        let sidebarVisible: Bool
    }

    // MARK: - Views

    private let addressBar: AddressBar = {
        let view = AddressBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let topToolbar: TopToolbar
    private let bottomToolbar: BottomToolbar
    private let overlayContentView = ChromeOverlayContentView()

    // MARK: - Constraints

    private var bottomConstraint: NSLayoutConstraint!
    private var overlayWidthConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayTopConstraint: NSLayoutConstraint?
    private var overlayCenterXConstraint: NSLayoutConstraint?

    // MARK: - State

    private var state: State?

    // MARK: - Lifecycle

    init(controller: BrowserViewController) {
        topToolbar = TopToolbar(controller: controller)
        bottomToolbar = BottomToolbar(controller: controller)
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        addressBar.configure(controller: controller)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // BrowserChrome spans the screen for edge-to-edge backgrounds, but its empty center must not block Gecko.
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayWidthConstraint.constant = max(addressBar.bounds.width + 32, bounds.width * (3.0 / 5.0))
    }

    // MARK: - Anchors And Frames

    var topToolbarBottomAnchor: NSLayoutYAxisAnchor {
        topToolbar.bottomAnchor
    }

    var bottomToolbarTopAnchor: NSLayoutYAxisAnchor {
        bottomToolbar.topAnchor
    }

    var addressBarBottomAnchor: NSLayoutYAxisAnchor {
        addressBar.bottomAnchor
    }

    func addressBarFrame(in view: UIView) -> CGRect {
        addressBar.convert(addressBar.bounds, to: view)
    }

    func sharePopoverSourceView() -> UIView {
        guard let state else { return bottomToolbar }
        return state.mode == .phone ? bottomToolbar : topToolbar
    }

    // MARK: - Layout

    func apply(state: State) {
        self.state = state
        addressBar.updateLayout(position: state.position, browserChromeMode: state.mode)
        attachAddressBar(for: state.mode)
        configureOverlayPositioningIfNeeded()

        // Presentation state has final authority over visibility; layout mode only selects visible geometry.
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
            sidebarVisible: state.sidebarVisible
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
        let topConstraint = overlayContentView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 12)
        let centerXConstraint = overlayContentView.centerXAnchor.constraint(equalTo: addressBar.centerXAnchor)
        NSLayoutConstraint.activate([topConstraint, centerXConstraint])
        overlayTopConstraint = topConstraint
        overlayCenterXConstraint = centerXConstraint
    }

    // MARK: - Address Bar

    func configureAddressBarSearchDelegate(_ delegate: AddressBarSearchDelegate) {
        addressBar.configureSearchDelegate(delegate)
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

    func updateAddressBarMenu(selectedTab: Tab?, url: String?) {
        addressBar.updateMenu(selectedTab: selectedTab, url: url)
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

    var isAddressBarEditing: Bool { addressBar.isEditingText }
    var isShowingAddressBarAutocomplete: Bool { addressBar.isShowingAutocomplete }

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

    // MARK: - Transitions

    func bottomToolbarSnapshot() -> UIView? {
        bottomToolbar.snapshotView(afterScreenUpdates: false)
    }

    func bottomToolbarFrame(in view: UIView) -> CGRect {
        bottomToolbar.convert(bottomToolbar.bounds, to: view)
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
        topToolbar.sidebarButtonFrame(in: view)
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
        // Each toolbar owns its safe-area extension. BrowserChrome only pins them to physical screen edges.
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

    private func attachAddressBar(for mode: browserChromeMode) {
        // Landscape phone uses pad-style top chrome even when the portrait preference is bottom.
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
