//
//  TopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TopToolbar: UIView {
    private enum UX {
        static let topToolbarContentHeight: CGFloat = 60
        static let topToolbarButtonStackHeight: CGFloat = 30
        static let topToolbarStandardButtonStackWidth: CGFloat = 126
        static let topToolbarHorizontalInset: CGFloat = 12
        static let topToolbarButtonSpacing: CGFloat = 10
        static let topToolbarAddressBarSpacing: CGFloat = 12
        static let topToolbarAddressBarVerticalSpacing: CGFloat = 8
        static let topToolbarAddressBarWidthLimit: CGFloat = 650
        static let backgroundViewHorizontalExtension: CGFloat = 16
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutState {
        case hidden
        case standard
        case compact
    }
    
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onShare: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let backgroundView: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect.nonAdaptive(style: .regular)
        } else {
            effect = UIBlurEffect(style: .systemChromeMaterial)
        }
        let view = UIVisualEffectView(effect: effect)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let backgroundBottomBorderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.2)
        if #available(iOS 26.0, *) {
            view.isHidden = true
        }
        return view
    }()
    
    private lazy var sidebarButton = ToolbarButton(
        buttonType: .sidebar,
        target: self,
        action: #selector(sidebarTapped)
    )
    private lazy var backButton = ToolbarButton(
        buttonType: .back,
        target: self,
        action: #selector(backTapped)
    )
    private lazy var forwardButton = ToolbarButton(
        buttonType: .forward,
        target: self,
        action: #selector(forwardTapped)
    )
    private lazy var libraryButton = ToolbarButton(
        buttonType: .library,
        target: self,
        action: #selector(libraryTapped)
    )
    private lazy var downloadButton = ToolbarButton(
        buttonType: .download,
        target: self,
        action: #selector(downloadsTapped)
    )
    private lazy var shareButton = ToolbarButton(
        buttonType: .share,
        target: self,
        action: #selector(shareTapped)
    )
    private lazy var newTabButton = ToolbarButton(
        buttonType: .newTab,
        target: self,
        action: #selector(newTabTapped)
    )
    private lazy var tabOverviewButton = ToolbarButton(
        buttonType: .tabOverview,
        target: self,
        action: #selector(tabOverviewTapped)
    )
    private let buttonMenus = ToolbarButtonMenus()
    
    private lazy var leadingButtons: UIStackView = {
        downloadButton.isHidden = true
        let stack = UIStackView(arrangedSubviews: [sidebarButton, downloadButton, backButton, forwardButton, libraryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var trailingButtons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [shareButton, newTabButton, tabOverviewButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var contentLayoutGuide: UILayoutGuide = {
        if #available(iOS 26.0, *) {
            return layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaLayoutGuide
    }()
    
    private var compactAddressBarHorizontalInset: CGFloat {
        if #available(iOS 26.0, *) {
            return 0
        }
        
        return UX.topToolbarHorizontalInset
    }
    
    private var heightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var backgroundBottomConstraint: NSLayoutConstraint!
    private var leadingButtonsLeadingConstraint: NSLayoutConstraint!
    private var trailingButtonsTrailingConstraint: NSLayoutConstraint!
    private var requestedTopInset: CGFloat = 0
    private var leadingWidthConstraint: NSLayoutConstraint!
    private var trailingWidthConstraint: NSLayoutConstraint!
    private var standardAddressBarConstraints: [NSLayoutConstraint] = []
    private var compactAddressBarConstraints: [NSLayoutConstraint] = []
    private var widthLimitedStandardAddressBarConstraints: [NSLayoutConstraint] = []
    
    private var layoutState: LayoutState = .hidden
    private var layoutInterfaceIdiom: UIUserInterfaceIdiom = .unspecified
    private var layoutSidebarButtonVisible = false
    private var layoutShowsLibraryButton = false
    private var isUsingStandardAddressBarWidthLimit = false
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        updateRowPlacement()
        super.layoutSubviews()
        updateStandardAddressBarLayout()
    }
    
    /// Where the system places a bar along the top edge when the status bar
    /// shares the top band with it, as on the inner display of a foldable
    /// iPhone (iOS 27.2): beside the status bar and centred on it, like Safari's
    /// toolbar row. `nil` when the bar goes below the status bar as usual.
    /// Reading layout regions here lays the toolbar out again when they change.
    private var systemTopBarFrame: CGRect? {
        // Read from the browser chrome this toolbar is pinned to (same origin
        // and width): the toolbar itself slides up while it collapses on
        // scroll, and its own insets would move with it.
        guard #available(iOS 27.2, *), let container = superview, container.bounds.width > 0 else {
            return nil
        }
        let insets = container.edgeInsets(for: .bar(onEdge: UIRectEdge.top))
        guard insets.top < container.safeAreaInsets.top else {
            return nil
        }
        return container.bounds.inset(by: insets)
    }
    
    private func updateRowPlacement() {
        var contentTop = requestedTopInset
        var height = requestedTopInset + UX.topToolbarContentHeight
        var leadingClearance: CGFloat = 0
        var trailingClearance: CGFloat = 0
        
        if layoutState == .standard, let bar = systemTopBarFrame, bar.height > 0 {
            contentTop = max(0, bar.midY - UX.topToolbarContentHeight / 2)
            height = contentTop + UX.topToolbarContentHeight
            // The system bar region already includes the standard margins.
            leadingClearance = max(0, bar.minX - safeAreaInsets.left - UX.topToolbarHorizontalInset)
            trailingClearance = max(0, bounds.maxX - safeAreaInsets.right - bar.maxX - UX.topToolbarHorizontalInset)
        }
        
        if contentTopConstraint.constant != contentTop {
            contentTopConstraint.constant = contentTop
        }
        if heightConstraint.constant != height {
            heightConstraint.constant = height
        }
        let leadingConstant = UX.topToolbarHorizontalInset + leadingClearance
        if leadingButtonsLeadingConstraint.constant != leadingConstant {
            leadingButtonsLeadingConstraint.constant = leadingConstant
        }
        let trailingConstant = -(UX.topToolbarHorizontalInset + trailingClearance)
        if trailingButtonsTrailingConstraint.constant != trailingConstant {
            trailingButtonsTrailingConstraint.constant = trailingConstant
        }
    }
    
    // MARK: - Layout
    
    func attachAddressBar(_ addressBar: AddressBar) {
        if addressBar.superview !== contentView {
            addressBar.removeFromSuperview()
            contentView.addSubview(addressBar)
        }
        if standardAddressBarConstraints.isEmpty {
            standardAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(equalTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            widthLimitedStandardAddressBarConstraints = [
                addressBar.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
                addressBar.widthAnchor.constraint(equalToConstant: UX.topToolbarAddressBarWidthLimit),
                addressBar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            compactAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(
                    equalTo: contentLayoutGuide.leadingAnchor,
                    constant: compactAddressBarHorizontalInset
                ),
                addressBar.trailingAnchor.constraint(
                    equalTo: contentLayoutGuide.trailingAnchor,
                    constant: -compactAddressBarHorizontalInset
                ),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
        }
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints + compactAddressBarConstraints)
        isUsingStandardAddressBarWidthLimit = false
    }
    
    func libraryPopoverSourceView() -> UIView {
        return libraryButton
    }
    
    func sharePopoverSourceView() -> UIView {
        return shareButton
    }
    
    func extendBackground(to bottomAnchor: NSLayoutYAxisAnchor) {
        backgroundBottomConstraint.isActive = false
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        backgroundBottomConstraint.isActive = true
    }
    
    func setBackgroundCollapseOffset(_ offset: CGFloat) {
        backgroundBottomConstraint.constant = -offset
    }
    
    func apply(
        state: LayoutState,
        topInset: CGFloat,
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool,
        showsLibraryButton: Bool = false
    ) {
        layoutState = state
        layoutInterfaceIdiom = interfaceIdiom
        layoutSidebarButtonVisible = sidebarButtonVisible
        layoutShowsLibraryButton = showsLibraryButton
        
        requestedTopInset = topInset
        UIView.performWithoutAnimation {
            updateRowPlacement()
            isHidden = state == .hidden
            guard state != .hidden else { return }
            
            let isCompact = state == .compact
            leadingButtons.isHidden = isCompact
            trailingButtons.isHidden = isCompact
            leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
                interfaceIdiom: interfaceIdiom,
                sidebarButtonVisible: sidebarButtonVisible,
                showsDownloads: downloadButton.isShowingDownloads
            )
            trailingWidthConstraint.constant = isCompact ? 0 : UX.topToolbarStandardButtonStackWidth
            
            sidebarButton.isHidden = interfaceIdiom != .pad || !sidebarButtonVisible
            libraryButton.isHidden = interfaceIdiom == .pad && !showsLibraryButton
            downloadButton.isHidden = isCompact || !downloadButton.isShowingDownloads
            
            NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints + compactAddressBarConstraints)
            isUsingStandardAddressBarWidthLimit = false
            if isCompact {
                NSLayoutConstraint.activate(compactAddressBarConstraints)
            } else {
                setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
            }
            layoutIfNeeded()
        }
    }
    
    func setContentAlpha(_ alpha: CGFloat) {
        contentView.alpha = alpha
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        shareButton.isEnabled = canShare
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        buttonMenus.installNavigationMenus(
            on: backButton,
            forwardButton: forwardButton,
            itemsProvider: itemsProvider,
            onSelect: onSelect,
            isReversed: false
        )
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        buttonMenus.installRecentlyClosedTabsMenu(
            on: newTabButton,
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(
            on: [sidebarButton, libraryButton],
            onSelect: onSelect
        )
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        buttonMenus.installTabOverviewMenus(
            on: [tabOverviewButton],
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
        updateDownloadButtonVisibility()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryButton.setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
        )
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        sidebarButton.setImage(splitViewController?.displayModeButtonItem.image ?? UIImage(named: "reynard.sidebar.left"), for: .normal)
        sidebarButton.accessibilityLabel = splitViewController?.displayModeButtonItem.accessibilityLabel
    }
    
    func sidebarButtonFrame(in view: UIView) -> CGRect {
        return sidebarButton.convert(sidebarButton.bounds, to: view)
    }
    
    func setSidebarButtonTransition(alpha: CGFloat, hidden: Bool) {
        sidebarButton.alpha = alpha
        sidebarButton.isHidden = hidden
    }
    
    // MARK: - Action Wiring
    
    @objc private func sidebarTapped() { onSidebar?() }
    @objc private func backTapped() { onBack?() }
    @objc private func forwardTapped() { onForward?() }
    @objc private func libraryTapped() { onLibrary?() }
    @objc private func downloadsTapped() { onDownloads?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func newTabTapped() { onNewTab?() }
    @objc private func tabOverviewTapped() { onTabOverview?() }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        addSubview(backgroundBottomBorderView)
        addSubview(contentView)
        contentView.addSubview(leadingButtons)
        contentView.addSubview(trailingButtons)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight)
        contentTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        leadingWidthConstraint = leadingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        trailingWidthConstraint = trailingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        leadingButtonsLeadingConstraint = leadingButtons.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: UX.topToolbarHorizontalInset)
        trailingButtonsTrailingConstraint = trailingButtons.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -UX.topToolbarHorizontalInset)
        
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundBottomConstraint,
            
            backgroundBottomBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            backgroundBottomBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundBottomBorderView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            backgroundBottomBorderView.heightAnchor.constraint(equalToConstant: UX.borderWidth),
            
            heightConstraint,
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight),
            
            leadingButtonsLeadingConstraint,
            leadingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leadingWidthConstraint,
            leadingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
            
            trailingButtonsTrailingConstraint,
            trailingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingWidthConstraint,
            trailingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
        ])
    }
    
    private func leadingWidth(
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool,
        showsDownloads: Bool
    ) -> CGFloat {
        guard interfaceIdiom == .pad else { return UX.topToolbarStandardButtonStackWidth }
        let visibleButtonCount = 2
        + (sidebarButtonVisible ? 1 : 0)
        + (layoutShowsLibraryButton ? 1 : 0)
        + (showsDownloads ? 1 : 0)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarButtonSpacing)
    }
    
    private var shouldLimitStandardAddressBarWidth: Bool {
        let layoutInsets = contentLayoutInsets
        let safeWidth = bounds.width - layoutInsets.left - layoutInsets.right
        guard safeWidth > 0 else { return false }
        
        let leadingBoundary = leadingButtonsLeadingConstraint.constant
        + leadingWidthConstraint.constant
        + UX.topToolbarAddressBarSpacing
        let trailingBoundary = safeWidth
        + trailingButtonsTrailingConstraint.constant
        - trailingWidthConstraint.constant
        - UX.topToolbarAddressBarSpacing
        let centeredWidth = min(
            (safeWidth / 2) - leadingBoundary,
            trailingBoundary - (safeWidth / 2)
        ) * 2
        
        return centeredWidth > UX.topToolbarAddressBarWidthLimit
    }
    
    private var contentLayoutInsets: UIEdgeInsets {
        if #available(iOS 26.0, *) {
            return edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaInsets
    }
    
    private func updateStandardAddressBarLayout() {
        guard layoutState == .standard else {
            return
        }
        
        setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
    }
    
    private func setStandardAddressBarWidthLimitEnabled(_ isEnabled: Bool) {
        let activeConstraints = isEnabled ? widthLimitedStandardAddressBarConstraints : standardAddressBarConstraints
        guard activeConstraints.contains(where: { !$0.isActive }) || isUsingStandardAddressBarWidthLimit != isEnabled else {
            return
        }
        
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints)
        NSLayoutConstraint.activate(activeConstraints)
        isUsingStandardAddressBarWidthLimit = isEnabled
    }
    
    private func updateDownloadButtonVisibility() {
        let isCompact = layoutState == .compact
        downloadButton.isHidden = layoutState != .standard || !downloadButton.isShowingDownloads
        leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
            interfaceIdiom: layoutInterfaceIdiom,
            sidebarButtonVisible: layoutSidebarButtonVisible,
            showsDownloads: downloadButton.isShowingDownloads
        )
        updateStandardAddressBarLayout()
        layoutIfNeeded()
    }
}
