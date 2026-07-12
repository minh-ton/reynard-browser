//
//  BottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

enum BottomToolbarAction: String, CaseIterable {
    case back
    case forward
    case reload
    case share
    case pageZoom
    case bookmarks
    case history
    case downloads
    case settings
    case newTab
    case closeTab
    case tabOverview

    static let maximumVisibleActions = 10
    static let defaultActions: [BottomToolbarAction] = [
        .back, .forward, .share, .bookmarks, .downloads, .tabOverview,
    ]

    var title: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .share: return "Share"
        case .pageZoom: return "Page Zoom"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .downloads: return "Downloads"
        case .settings: return "Settings"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .tabOverview: return "Tabs"
        }
    }

    var imageName: String {
        switch self {
        case .back: return "reynard.chevron.backward"
        case .forward: return "reynard.chevron.forward"
        case .reload: return "reynard.arrow.clockwise"
        case .share: return "reynard.square.and.arrow.up"
        case .pageZoom: return "reynard.textformat.size"
        case .bookmarks: return "reynard.book"
        case .history: return "reynard.clock"
        case .downloads: return "reynard.arrow.down.circle"
        case .settings: return "reynard.gearshape"
        case .newTab: return "reynard.plus"
        case .closeTab: return "reynard.xmark"
        case .tabOverview: return "reynard.square.on.square"
        }
    }
}

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
        static let bottomToolbarButtonSpacing: CGFloat = 4
    }
    
    enum LayoutState {
        case hidden
        case collapsed // visually hidden but still takes up space
        case standard
        case focused
        case compact
    }
    
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onBookmarks: (() -> Void)?
    var onHistory: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onSettings: (() -> Void)?
    var onTabOverview: (() -> Void)?
    var onReload: (() -> Void)?
    var onPageZoom: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onCloseTab: (() -> Void)?
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var backButton = ToolbarButton(buttonType: .back, target: self, action: #selector(backTapped))
    private lazy var forwardButton = ToolbarButton(buttonType: .forward, target: self, action: #selector(forwardTapped))
    private lazy var shareButton = ToolbarButton(buttonType: .share, target: self, action: #selector(shareTapped))
    private lazy var bookmarksButton = ToolbarButton(buttonType: .bookmarks, target: self, action: #selector(bookmarksTapped))
    private lazy var historyButton = ToolbarButton(buttonType: .history, target: self, action: #selector(historyTapped))
    private lazy var downloadButton = ToolbarButton(buttonType: .download, target: self, action: #selector(downloadsTapped))
    private lazy var settingsButton = ToolbarButton(buttonType: .settings, target: self, action: #selector(settingsTapped))
    private lazy var tabOverviewButton = ToolbarButton(buttonType: .tabOverview, target: self, action: #selector(tabOverviewTapped))
    private lazy var reloadButton = ToolbarButton(buttonType: .reload, target: self, action: #selector(reloadTapped))
    private lazy var pageZoomButton = ToolbarButton(buttonType: .pageZoom, target: self, action: #selector(pageZoomTapped))
    private lazy var newTabButton: ToolbarButton = {
        let button = ToolbarButton(buttonType: .newTab, target: self, action: #selector(newTabTapped))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(newTabLongPressed(_:)))
        longPress.minimumPressDuration = 0.5
        button.addGestureRecognizer(longPress)
        return button
    }()
    private lazy var closeTabButton: ToolbarButton = {
        let button = ToolbarButton(buttonType: .closeTab, target: self, action: #selector(closeTabTapped))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(closeTabLongPressed(_:)))
        longPress.minimumPressDuration = 0.5
        button.addGestureRecognizer(longPress)
        return button
    }()

    private lazy var actionButtons: [BottomToolbarAction: ToolbarButton] = [
        .back: backButton,
        .forward: forwardButton,
        .reload: reloadButton,
        .share: shareButton,
        .pageZoom: pageZoomButton,
        .bookmarks: bookmarksButton,
        .history: historyButton,
        .downloads: downloadButton,
        .settings: settingsButton,
        .newTab: newTabButton,
        .closeTab: closeTabButton,
        .tabOverview: tabOverviewButton,
    ]
    
    private lazy var buttons: UIStackView = {
        let stack = UIStackView()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bottomToolbarActionsDidChange),
            name: .bottomToolbarActionsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bottomToolbarShortcutsDidChange),
            name: .bottomToolbarShortcutsDidChange,
            object: nil
        )
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
        case .collapsed:
            contentHeight = UX.bottomToolbarCompactContentHeight
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
            isHidden = state == .hidden || state == .collapsed
            backgroundColor = state == .focused ? .clear : .systemGray6
            
            let isCompact = state == .compact || state == .collapsed
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
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        _ = hasUpdate
    }
    
    // MARK: - Action Wiring
    
    @objc private func backTapped() { onBack?() }
    @objc private func forwardTapped() { onForward?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func bookmarksTapped() { onBookmarks?() }
    @objc private func historyTapped() { onHistory?() }
    @objc private func downloadsTapped() { onDownloads?() }
    @objc private func settingsTapped() { onSettings?() }
    @objc private func tabOverviewTapped() { onTabOverview?() }
    @objc private func reloadTapped() { onReload?() }
    @objc private func pageZoomTapped() { onPageZoom?() }
    @objc private func newTabTapped() { onNewTab?() }
    @objc private func closeTabTapped() { onCloseTab?() }

    @objc private func closeTabLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              Prefs.AppearanceSettings.closeTabLongPressOpensNewTab else {
            return
        }
        if Prefs.AppearanceSettings.toolbarButtonHapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        onNewTab?()
    }

    @objc private func newTabLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              Prefs.AppearanceSettings.newTabLongPressClosesTab else {
            return
        }
        if Prefs.AppearanceSettings.toolbarButtonHapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        onCloseTab?()
    }

    @objc private func bottomToolbarActionsDidChange() {
        applyConfiguredActions()
    }

    @objc private func bottomToolbarShortcutsDidChange() {
        updateShortcutAccessibility()
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGray6
    }
    
    private func configureHierarchy() {
        addSubview(contentView)
        contentView.addSubview(buttons)
        applyConfiguredActions()
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
        updateShortcutAccessibility()
    }

    private func applyConfiguredActions() {
        for button in buttons.arrangedSubviews {
            buttons.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        for action in Prefs.AppearanceSettings.bottomToolbarActions {
            if let button = actionButtons[action] {
                button.isHidden = false
                buttons.addArrangedSubview(button)
            }
        }
    }

    private func updateShortcutAccessibility() {
        closeTabButton.accessibilityHint = Prefs.AppearanceSettings.closeTabLongPressOpensNewTab
            ? "Touch and hold to open a new tab"
            : nil
        newTabButton.accessibilityHint = Prefs.AppearanceSettings.newTabLongPressClosesTab
            ? "Touch and hold to close the current tab"
            : nil
    }
}
