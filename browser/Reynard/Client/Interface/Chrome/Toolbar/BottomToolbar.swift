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
        static let bottomToolbarFocusedContentHeight: CGFloat = 58
        static let bottomToolbarCompactContentHeight: CGFloat = 44
        static let bottomToolbarButtonStackHeight: CGFloat = 30
        static let addressBarHorizontalInset: CGFloat = 12
        static let addressBarTopInset: CGFloat = 8
        static let bottomToolbarButtonStackHorizontalInset: CGFloat = 24
        static let bottomToolbarButtonStackTopSpacing: CGFloat = 7
        static let bottomToolbarButtonSpacing: CGFloat = 8
    }
    
    enum LayoutState {
        case hidden
        case standard
        case focused
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
    
    private lazy var backButton = ToolbarButton(buttonType: .back, target: self, action: #selector(backTapped))
    private lazy var forwardButton = ToolbarButton(buttonType: .forward, target: self, action: #selector(forwardTapped))
    private lazy var shareButton = ToolbarButton(buttonType: .share, target: self, action: #selector(shareTapped))
    private lazy var libraryButton = ToolbarButton(buttonType: .library, target: self, action: #selector(libraryTapped))
    private lazy var downloadButton = ToolbarButton(buttonType: .download, target: self, action: #selector(downloadsTapped))
    private lazy var tabOverviewButton = ToolbarButton(buttonType: .tabOverview, target: self, action: #selector(tabOverviewTapped))
    
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
    private var buttonsHeightConstraint: NSLayoutConstraint!
    private var standardButtonsTopConstraint: NSLayoutConstraint!
    private var compactButtonsTopConstraint: NSLayoutConstraint!
    private var addressBarConstraints: [NSLayoutConstraint] = []
    
    private var verticalOffset: CGFloat = 0
    
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
        if addressBar.superview !== contentView {
            addressBar.removeFromSuperview()
            contentView.addSubview(addressBar)
        }
        if addressBarConstraints.isEmpty {
            addressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.addressBarHorizontalInset),
                addressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.addressBarHorizontalInset),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.addressBarTopInset),
            ]
        }
        standardButtonsTopConstraint?.isActive = false
        standardButtonsTopConstraint = buttons.topAnchor.constraint(
            equalTo: addressBar.bottomAnchor,
            constant: UX.bottomToolbarButtonStackTopSpacing
        )
        NSLayoutConstraint.activate(addressBarConstraints)
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(addressBarConstraints)
        standardButtonsTopConstraint?.isActive = false
    }
    
    func apply(state: LayoutState, hidesButtons: Bool) {
        let contentHeight: CGFloat
        switch state {
        case .hidden:
            contentHeight = UX.bottomToolbarStandardContentHeight
        case .standard:
            contentHeight = UX.bottomToolbarStandardContentHeight
        case .focused:
            contentHeight = UX.bottomToolbarFocusedContentHeight
        case .compact:
            contentHeight = UX.bottomToolbarCompactContentHeight
        }
        
        UIView.performWithoutAnimation {
            topConstraint.constant = verticalOffset - contentHeight
            contentHeightConstraint.constant = contentHeight
            isHidden = state == .hidden
            backgroundColor = state == .focused ? .clear : .systemGray6
            
            let isCompact = state == .compact
            standardButtonsTopConstraint?.isActive = !isCompact
            compactButtonsTopConstraint.isActive = isCompact
            buttonsHeightConstraint.constant = state == .focused ? 0 : UX.bottomToolbarButtonStackHeight
            buttons.alpha = state == .focused || hidesButtons ? 0 : 1
            buttons.isUserInteractionEnabled = state != .focused && !hidesButtons
            layoutIfNeeded()
        }
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        shareButton.isEnabled = canShare
    }
    
    func setVerticalOffset(_ offset: CGFloat) {
        verticalOffset = offset
        topConstraint.constant = offset - contentHeightConstraint.constant
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
        backgroundColor = .systemGray6
    }
    
    private func configureHierarchy() {
        addSubview(contentView)
        contentView.addSubview(buttons)
    }
    
    private func configureConstraints() {
        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: UX.bottomToolbarStandardContentHeight)
        buttonsHeightConstraint = buttons.heightAnchor.constraint(equalToConstant: UX.bottomToolbarButtonStackHeight)
        compactButtonsTopConstraint = buttons.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.bottomToolbarButtonStackTopSpacing)
        
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentHeightConstraint,
            
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.bottomToolbarButtonStackHorizontalInset),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.bottomToolbarButtonStackHorizontalInset),
            buttonsHeightConstraint,
        ])
    }
    
    private func configureInitialState() {
        shareButton.isEnabled = false
        downloadButton.isHidden = true
    }
}
