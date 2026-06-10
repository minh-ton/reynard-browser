//
//  BottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

protocol BottomToolbarDelegate: AnyObject {
    func backButtonClicked()
    func forwardButtonClicked()
    func shareButtonClicked()
    func menuButtonClicked()
    func downloadsButtonClicked()
    func tabsButtonClicked()
}

final class BottomToolbar: UIView {
    // MARK: - UX

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

    // MARK: - Views

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private lazy var backButton = ToolBarButton(buttonType: .back, target: self, action: #selector(backButtonClicked))
    private lazy var forwardButton = ToolBarButton(buttonType: .forward, target: self, action: #selector(forwardButtonClicked))
    private lazy var shareButton = ToolBarButton(buttonType: .share, target: self, action: #selector(shareButtonClicked))
    private lazy var libraryButton = ToolBarButton(buttonType: .library, target: self, action: #selector(menuButtonClicked))
    private lazy var downloadButton = ToolBarButton(buttonType: .download, target: self, action: #selector(downloadsButtonClicked))
    private lazy var tabOverviewButton = ToolBarButton(buttonType: .tabOverview, target: self, action: #selector(tabsButtonClicked))

    private lazy var buttons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, shareButton, libraryButton, downloadButton, tabOverviewButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.spacing = UX.bottomToolbarButtonSpacing
        return stack
    }()

    // MARK: - Constraints

    private var topConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!
    private var buttonsHeightConstraint: NSLayoutConstraint!
    private var standardButtonsTopConstraint: NSLayoutConstraint!
    private var compactButtonsTopConstraint: NSLayoutConstraint!
    private var addressBarConstraints: [NSLayoutConstraint] = []

    // MARK: - State

    weak var delegate: BottomToolbarDelegate?
    private var verticalOffset: CGFloat = 0

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
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
        // The top tracks content height while the view's bottom remains pinned to the physical screen edge.
        topConstraint = topAnchor.constraint(equalTo: safeAreaBottomAnchor, constant: -UX.bottomToolbarStandardContentHeight)
        topConstraint.isActive = true
    }

    func attachAddressBar(_ addressBar: AddressBar) {
        // Standard phone layout places buttons below the AddressBar; compact layout bypasses this constraint.
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
            // Resolve stack visibility immediately to prevent arranged subviews flying during outer transitions.
            topConstraint.constant = verticalOffset - contentHeight
            contentHeightConstraint.constant = contentHeight
            isHidden = state == .hidden
            backgroundColor = state == .focused ? .clear : .systemGray6

            let isCompact = state == .compact
            standardButtonsTopConstraint.isActive = !isCompact
            compactButtonsTopConstraint.isActive = isCompact
            buttonsHeightConstraint.constant = state == .focused ? 0 : UX.bottomToolbarButtonStackHeight
            buttons.alpha = state == .focused ? 0 : 1
            buttons.isUserInteractionEnabled = state != .focused && !hidesButtons
            buttons.alpha = hidesButtons ? 0 : buttons.alpha
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
        // Keyboard docking translates both toolbar edges equally, preserving its total safe-area-filling height.
        verticalOffset = offset
        topConstraint.constant = offset - contentHeightConstraint.constant
    }

    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
        downloadButton.isHidden = !downloadButton.isShowingDownloads
    }

    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryButton.setImage(
            hasUpdate ? UIImage(named: "ellipsis.circle.badge") : UIImage(systemName: "ellipsis.circle"),
            for: .normal
        )
    }

    // MARK: - Actions

    @objc private func backButtonClicked() { delegate?.backButtonClicked() }
    @objc private func forwardButtonClicked() { delegate?.forwardButtonClicked() }
    @objc private func shareButtonClicked() { delegate?.shareButtonClicked() }
    @objc private func menuButtonClicked() { delegate?.menuButtonClicked() }
    @objc private func downloadsButtonClicked() { delegate?.downloadsButtonClicked() }
    @objc private func tabsButtonClicked() { delegate?.tabsButtonClicked() }

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
