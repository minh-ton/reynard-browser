//
//  BottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
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
        static let menuRestoreDelay: TimeInterval = 1
        static let menuSwapDuration: TimeInterval = 0.3
    }
    
    enum LayoutState {
        case hidden
        case collapsed // visually hidden but still takes up space
        case standard
        case compact
    }
    
    var onItem: ((ToolbarItem) -> Void)?
    
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
    
    private var itemButtons: [ToolbarItem: ToolbarButton] = [:]
    private var arrangedItems: [ToolbarItem] = []
    private var downloadSummary: DownloadStoreSummary?
    private var pendingMenuRestore: DispatchWorkItem?
    private let buttonMenus = ToolbarButtonMenus()
    
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
    private var standardButtonsBottomConstraint: NSLayoutConstraint!
    private var compactButtonsTopConstraint: NSLayoutConstraint!
    private var addressBarConstraints: [NSLayoutConstraint] = []
    private var addressBarTopConstraint: NSLayoutConstraint?
    private weak var addressBar: AddressBar?
    
    private var addressBarDockOffset: CGFloat = 0
    
    private func addressBarTopConstant(for dockOffset: CGFloat) -> CGFloat {
        let dockedAdjustment = dockOffset == 0 ? 0 : UX.addressBarDockedVerticalAdjustment
        return UX.addressBarTopInset + dockOffset + dockedAdjustment
    }
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureObservers()
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
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(addressBarConstraints)
        addressBar = nil
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
        return button(for: .share)
    }
    
    func apply(state: LayoutState, hidesButtons: Bool) {
        let contentHeight: CGFloat
        switch state {
        case .hidden, .standard:
            contentHeight = UX.bottomToolbarStandardContentHeight
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
        button(for: .back).isEnabled = canGoBack
        button(for: .forward).isEnabled = canGoForward
        button(for: .share).isEnabled = canShare
    }
    
    func updatePageActions(canUsePageTools: Bool, canShowReader: Bool, isBookmarked: Bool) {
        button(for: .findInPage).isEnabled = canUsePageTools
        button(for: .pageZoom).isEnabled = canUsePageTools
        button(for: .reader).isEnabled = canShowReader
        
        button(for: .addBookmark).isEnabled = canUsePageTools
        button(for: .addBookmark).setImage(
            isBookmarked ? UIImage(named: "reynard.bookmark.fill") : UIImage(named: "reynard.bookmark"),
            for: .normal
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadSummary = summary
        button(for: .downloads).applyDownloadSummary(summary)
        arrangeButtons()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        button(for: .library).setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
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
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [GeckoSessionHistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        buttonMenus.installNavigationMenus(
            on: button(for: .back),
            forwardButton: button(for: .forward),
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        buttonMenus.installRecentlyClosedTabsMenu(
            on: button(for: .newTab),
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(on: [button(for: .library)], onSelect: onSelect)
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        buttonMenus.installTabOverviewMenus(
            on: [button(for: .tabOverview)],
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
    }
    
    // MARK: - Action Wiring
    
    @objc private func itemTapped(_ sender: ToolbarButton) {
        guard case .item(let item) = sender.toolbarButtonType else {
            return
        }
        
        onItem?(item)
    }
    
    @objc private func toolbarItemsDidChange() {
        arrangeButtons()
    }
    
    // MARK: - Buttons
    
    private func button(for item: ToolbarItem) -> ToolbarButton {
        if let button = itemButtons[item] {
            return button
        }
        
        let button = ToolbarButton(buttonType: .item(item), target: self, action: #selector(itemTapped(_:)))
        itemButtons[item] = button
        return button
    }
    
    private var displayedItems: [ToolbarItem] {
        var items = ToolbarPlacement.bottomToolbar.items
        if !items.contains(.downloads),
           let downloadSummary,
           let menuIndex = items.firstIndex(of: .library) {
            if items.count < ToolbarPlacement.bottomToolbar.maximumItemCount {
                if downloadSummary.showsToolbarButton {
                    items.insert(.downloads, at: menuIndex)
                }
            } else if downloadSummary.activeCount > 0 {
                items[menuIndex] = .downloads
            }
        }
        
        return items
    }
    
    private func arrangeButtons() {
        let items = displayedItems
        guard items != arrangedItems else {
            pendingMenuRestore?.cancel()
            pendingMenuRestore = nil
            return
        }
        
        let isRestoringMenu = !arrangedItems.isEmpty
        && !arrangedItems.contains(.library)
        && items.contains(.library)
        guard isRestoringMenu else {
            pendingMenuRestore?.cancel()
            pendingMenuRestore = nil
            applyArrangement(items)
            return
        }
        
        guard pendingMenuRestore == nil else {
            return
        }
        
        let menuRestore = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            
            self.pendingMenuRestore = nil
            self.applyArrangement(self.displayedItems)
        }
        pendingMenuRestore = menuRestore
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.menuRestoreDelay, execute: menuRestore)
    }
    
    private func applyArrangement(_ items: [ToolbarItem]) {
        let isSwappingMenu = !arrangedItems.isEmpty
        && arrangedItems.contains(.library) != items.contains(.library)
        arrangedItems = items
        
        let rearrange = {
            self.buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
            items.forEach { self.buttons.addArrangedSubview(self.button(for: $0)) }
            self.buttons.layoutIfNeeded()
        }
        guard isSwappingMenu else {
            rearrange()
            return
        }
        
        UIView.transition(
            with: buttons,
            duration: UX.menuSwapDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            UIView.performWithoutAnimation(rearrange)
        }
    }
    
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
        
        NSLayoutConstraint.activate([
            keyboardDockedBlurView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            keyboardDockedBlurView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
            keyboardDockedBlurView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: UX.addressBarDockedVerticalAdjustment - UX.keyboardDockedBlurTopExtension
            ),
            keyboardDockedBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarItemsDidChange),
            name: .toolbarItemsDidChange,
            object: nil
        )
    }
    
    private func configureInitialState() {
        button(for: .share).isEnabled = false
        arrangeButtons()
    }
    
}
