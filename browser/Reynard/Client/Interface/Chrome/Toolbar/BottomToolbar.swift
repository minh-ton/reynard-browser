//
//  BottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BottomToolbar: UIView {
    private enum UX {
        static let bottomToolbarStandardContentHeight: CGFloat = 94
        static let bottomToolbarCompactContentHeight: CGFloat = 44
        static let bottomToolbarButtonStackHeight: CGFloat = 30
        static let bottomToolbarButtonStackBottomInset: CGFloat = 5
        static let addressBarHorizontalInset: CGFloat = 12
        static let addressBarTopInset: CGFloat = 8
        static let bottomToolbarButtonStackHorizontalInset: CGFloat = 24
        static let bottomToolbarButtonStackTopSpacing: CGFloat = 7
        static let bottomToolbarButtonSpacing: CGFloat = 8
        static let backgroundViewHorizontalExtension: CGFloat = 16
        static let addressBarDockedVerticalAdjustment: CGFloat = 36
        static let keyboardDockedBlurTopExtension: CGFloat = 24
        static let borderWidth: CGFloat = 0.5
        /// Matches `AddressBar`'s own height; with no buttons below it, the
        /// floating address bar sits right on the bottom of the safe area.
        static let floatingAddressBarHeight: CGFloat = 44
    }
    
    enum LayoutState {
        case hidden
        case collapsed // visually hidden but still takes up space
        case standard
        case compact
    }
    
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
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
    
    private let backgroundTopBorderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.2)
        if #available(iOS 26.0, *) {
            view.isHidden = true
        }
        return view
    }()
    
    private let keyboardDockedBlurView: UIView = {
        let view = VariableBlurView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.direction = .up
        view.isHidden = true
        return view
    }()
    
    private lazy var backButton = ToolbarButton(buttonType: .back, target: self, action: #selector(backTapped))
    private lazy var forwardButton = ToolbarButton(buttonType: .forward, target: self, action: #selector(forwardTapped))
    private lazy var shareButton = ToolbarButton(buttonType: .share, target: self, action: #selector(shareTapped))
    private lazy var libraryButton = ToolbarButton(buttonType: .library, target: self, action: #selector(libraryTapped))
    private lazy var downloadButton = ToolbarButton(buttonType: .download, target: self, action: #selector(downloadsTapped))
    private lazy var tabOverviewButton = ToolbarButton(buttonType: .tabOverview, target: self, action: #selector(tabOverviewTapped))
    private let buttonMenus = ToolbarButtonMenus()
    
    private lazy var buttons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, shareButton, libraryButton, downloadButton, tabOverviewButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.spacing = UX.bottomToolbarButtonSpacing
        return stack
    }()
    
    private var topConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!
    private var standardButtonsBottomConstraint: NSLayoutConstraint!
    private var compactButtonsTopConstraint: NSLayoutConstraint!
    private var addressBarConstraints: [NSLayoutConstraint] = []
    private var addressBarTopConstraint: NSLayoutConstraint?
    private weak var addressBar: AddressBar?
    
    private var addressBarDockOffset: CGFloat = 0
    private var isFloating = false
    private var floatingAddressBarConstraints: [NSLayoutConstraint] = []
    
    /// Floating style used while the system vertical bar holds the buttons: no
    /// bar background or buttons, just the address bar over the page.
    func setFloating(_ floating: Bool) {
        guard floating != isFloating else {
            return
        }
        isFloating = floating
        setFloatingCollapseProgress(0)
        updateAddressBarHorizontalConstraints()
        addressBarTopConstraint?.constant = addressBarTopConstant(for: addressBarDockOffset)
        keyboardDockedBlurTopConstraint?.constant = keyboardDockedBlurTopConstant
    }
    
    private var keyboardDockedBlurTopConstant: CGFloat {
        return UX.addressBarDockedVerticalAdjustment - UX.keyboardDockedBlurTopExtension - floatingHeightReduction
    }
    
    private var keyboardDockedBlurTopConstraint: NSLayoutConstraint?
    
    /// While floating, the bar background stays hidden until the toolbar
    /// collapses on scroll, so the minimized address stays readable over the page.
    func setFloatingCollapseProgress(_ progress: CGFloat) {
        let alpha = isFloating ? min(max(progress, 0), 1) : 1
        backgroundView.alpha = alpha
        backgroundTopBorderView.alpha = alpha
    }
    
    private func updateAddressBarHorizontalConstraints() {
        guard let addressBar, !addressBarConstraints.isEmpty else {
            return
        }
        let edgeConstraints = addressBarConstraints.filter { $0 !== addressBarTopConstraint }
        if floatingAddressBarConstraints.isEmpty {
            // Across the page, beside the vertical bar rather than under it.
            floatingAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: UX.addressBarHorizontalInset),
                addressBar.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -UX.addressBarHorizontalInset),
            ]
        }
        if isFloating {
            NSLayoutConstraint.deactivate(edgeConstraints)
            NSLayoutConstraint.activate(floatingAddressBarConstraints)
        } else {
            NSLayoutConstraint.deactivate(floatingAddressBarConstraints)
            NSLayoutConstraint.activate(edgeConstraints)
        }
    }
    
    /// How much shorter the bar is while floating than the standard bar the
    /// keyboard docking offsets are measured against.
    private var floatingHeightReduction: CGFloat {
        return isFloating
        ? UX.bottomToolbarStandardContentHeight - (UX.addressBarTopInset + UX.floatingAddressBarHeight)
        : 0
    }
    
    private func addressBarTopConstant(for dockOffset: CGFloat) -> CGFloat {
        let dockedAdjustment = dockOffset == 0 ? 0 : UX.addressBarDockedVerticalAdjustment - floatingHeightReduction
        return UX.addressBarTopInset + dockOffset + dockedAdjustment
    }
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureInitialState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    func configureTopAnchor(to safeAreaBottomAnchor: NSLayoutYAxisAnchor) {
        topConstraint = topAnchor.constraint(equalTo: safeAreaBottomAnchor, constant: -UX.bottomToolbarStandardContentHeight)
        topConstraint.isActive = true
    }
    
    func attachAddressBar(_ addressBar: AddressBar) {
        self.addressBar = addressBar
        if addressBar.superview !== contentView {
            addressBar.removeFromSuperview()
            contentView.addSubview(addressBar)
        }
        if addressBarConstraints.isEmpty {
            let topConstraint = addressBar.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: addressBarTopConstant(for: addressBarDockOffset)
            )
            addressBarTopConstraint = topConstraint
            addressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.addressBarHorizontalInset),
                addressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.addressBarHorizontalInset),
                topConstraint,
            ]
        }
        addressBarTopConstraint?.constant = addressBarTopConstant(for: addressBarDockOffset)
        NSLayoutConstraint.activate(addressBarConstraints)
        updateAddressBarHorizontalConstraints()
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(addressBarConstraints)
        NSLayoutConstraint.deactivate(floatingAddressBarConstraints)
        addressBar = nil
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        guard isFloating else {
            return hitView
        }
        // Floating over the page: only the address bar itself takes touches.
        if let addressBar, let hitView, hitView.isDescendant(of: addressBar) {
            return hitView
        }
        return nil
    }
    
    func hitTestAddressBar(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden,
              isUserInteractionEnabled,
              alpha > 0.01,
              !contentView.isHidden,
              contentView.isUserInteractionEnabled,
              contentView.alpha > 0.01,
              let addressBar else {
            return nil
        }
        return addressBar.hitTest(addressBar.convert(point, from: self), with: event)
    }
    
    func sharePopoverSourceView() -> UIView {
        return shareButton
    }
    
    func apply(state: LayoutState, hidesButtons: Bool) {
        let contentHeight: CGFloat
        switch state {
        case .hidden, .standard:
            contentHeight = isFloating
            ? UX.addressBarTopInset + UX.floatingAddressBarHeight
            : UX.bottomToolbarStandardContentHeight
        case .collapsed, .compact:
            contentHeight = UX.bottomToolbarCompactContentHeight
        }
        
        UIView.performWithoutAnimation {
            topConstraint.constant = -contentHeight
            contentHeightConstraint.constant = contentHeight
            isHidden = state == .hidden || state == .collapsed
            
            let isCompact = state == .compact || state == .collapsed
            standardButtonsBottomConstraint?.isActive = !isCompact
            compactButtonsTopConstraint.isActive = isCompact
            buttons.alpha = hidesButtons ? 0 : 1
            buttons.isUserInteractionEnabled = !hidesButtons
            layoutIfNeeded()
        }
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
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(on: [libraryButton], onSelect: onSelect)
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
    
    func setAddressBarDockOffset(_ offset: CGFloat) {
        addressBarDockOffset = offset
        addressBarTopConstraint?.constant = addressBarTopConstant(for: offset)
        keyboardDockedBlurView.transform = CGAffineTransform(translationX: 0, y: offset)
        keyboardDockedBlurView.isHidden = offset == 0
    }
    
    func setContentAlpha(_ alpha: CGFloat) {
        contentView.alpha = alpha
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
        downloadButton.isHidden = !downloadButton.isShowingDownloads
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryButton.setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
        )
    }
    
    // MARK: - Action Wiring
    
    @objc private func backTapped() { onBack?() }
    @objc private func forwardTapped() { onForward?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func libraryTapped() { onLibrary?() }
    @objc private func downloadsTapped() { onDownloads?() }
    @objc private func tabOverviewTapped() { onTabOverview?() }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(keyboardDockedBlurView)
        addSubview(backgroundView)
        addSubview(backgroundTopBorderView)
        addSubview(contentView)
        contentView.addSubview(buttons)
    }
    
    private func configureConstraints() {
        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: UX.bottomToolbarStandardContentHeight)
        standardButtonsBottomConstraint = buttons.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor,
            constant: -UX.bottomToolbarButtonStackBottomInset
        )
        compactButtonsTopConstraint = buttons.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.bottomToolbarButtonStackTopSpacing)
        
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            backgroundTopBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            backgroundTopBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundTopBorderView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            backgroundTopBorderView.heightAnchor.constraint(equalToConstant: UX.borderWidth),
            
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentHeightConstraint,
            
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.bottomToolbarButtonStackHorizontalInset),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.bottomToolbarButtonStackHorizontalInset),
            buttons.heightAnchor.constraint(equalToConstant: UX.bottomToolbarButtonStackHeight),
        ])
        
        let keyboardDockedBlurTop = keyboardDockedBlurView.topAnchor.constraint(
            equalTo: contentView.topAnchor,
            constant: keyboardDockedBlurTopConstant
        )
        keyboardDockedBlurTopConstraint = keyboardDockedBlurTop
        NSLayoutConstraint.activate([
            keyboardDockedBlurView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            keyboardDockedBlurView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
            keyboardDockedBlurTop,
            keyboardDockedBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func configureInitialState() {
        shareButton.isEnabled = false
        downloadButton.isHidden = true
    }
    
}
