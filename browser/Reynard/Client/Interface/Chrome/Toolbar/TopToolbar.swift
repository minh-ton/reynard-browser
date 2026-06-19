//
//  TopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TopToolbar: UIView {
    private enum UX {
        static let topToolbarContentHeight: CGFloat = 52
        static let topToolbarButtonStackHeight: CGFloat = 30
        static let topToolbarStandardButtonStackWidth: CGFloat = 126
        static let topToolbarHorizontalInset: CGFloat = 12
        static let topToolbarButtonSpacing: CGFloat = 10
        static let topToolbarAddressBarSpacing: CGFloat = 12
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
    
    private var heightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var leadingWidthConstraint: NSLayoutConstraint!
    private var trailingWidthConstraint: NSLayoutConstraint!
    private var standardAddressBarConstraints: [NSLayoutConstraint] = []
    private var compactAddressBarConstraints: [NSLayoutConstraint] = []
    
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
                addressBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ]
            compactAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: UX.topToolbarHorizontalInset),
                addressBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -UX.topToolbarHorizontalInset),
                addressBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ]
        }
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + compactAddressBarConstraints)
    }
    
    func apply(
        state: LayoutState,
        topInset: CGFloat,
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool
    ) {
        UIView.performWithoutAnimation {
            contentTopConstraint.constant = topInset
            heightConstraint.constant = topInset + UX.topToolbarContentHeight
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
            libraryButton.isHidden = interfaceIdiom == .pad
            downloadButton.isHidden = isCompact || !downloadButton.isShowingDownloads
            
            NSLayoutConstraint.deactivate(standardAddressBarConstraints + compactAddressBarConstraints)
            NSLayoutConstraint.activate(isCompact ? compactAddressBarConstraints : standardAddressBarConstraints)
            layoutIfNeeded()
        }
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        shareButton.isEnabled = canShare
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
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
        backgroundColor = .systemGray6
    }
    
    private func configureHierarchy() {
        addSubview(contentView)
        contentView.addSubview(leadingButtons)
        contentView.addSubview(trailingButtons)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight)
        contentTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        leadingWidthConstraint = leadingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        trailingWidthConstraint = trailingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        
        NSLayoutConstraint.activate([
            heightConstraint,
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight),
            
            leadingButtons.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: UX.topToolbarHorizontalInset),
            leadingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leadingWidthConstraint,
            leadingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
            
            trailingButtons.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -UX.topToolbarHorizontalInset),
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
        let visibleButtonCount = (sidebarButtonVisible ? 3 : 2) + (showsDownloads ? 1 : 0)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarButtonSpacing)
    }
}
