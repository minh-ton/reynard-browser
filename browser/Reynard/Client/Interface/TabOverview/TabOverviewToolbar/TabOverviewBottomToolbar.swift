//
//  TabOverviewBottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewBottomToolbar: UIView {
    private enum UX {
        static let toolbarContentHorizontalInset: CGFloat = 32
        static let actionControlsBottomOffset: CGFloat = 54
        static let modeControlToActionControlsSpacing: CGFloat = 18
        static let tabModeControlHeight: CGFloat = 32
    }
    
    var onClearTabs: (() -> Void)?
    var onClearTabsOlderThan: ((TabOverviewClearTabsMenu.Age) -> Void)?
    var onAddTab: (() -> Void)?
    var onDone: (() -> Void)?
    var onTabModeChange: ((TabOverview.Mode) -> Void)?
    
    private let clearTabsButton = TabOverviewToolbarButton(action: .clear)
    private let addTabButton = TabOverviewToolbarButton(action: .add)
    private let doneButton = TabOverviewToolbarButton(action: .done)
    private lazy var actionButtonStackView = UIStackView(arrangedSubviews: [clearTabsButton, addTabButton, doneButton])
    private lazy var liquidGlassActionToolbar = makeLiquidGlassActionToolbar()
    private let tabModeControl = UISegmentedControl(items: [NSLocalizedString("Private", comment: ""), NSLocalizedString("0 Tabs", comment: "")])
    private var actionControlsTopConstraint: NSLayoutConstraint!
    private var modeControlAloneConstraint: NSLayoutConstraint!
    
    /// Hides the action buttons while the system vertical bar shows them (a
    /// folded foldable iPhone); the mode control then takes their place,
    /// level with the bottom of the vertical bar, as in Safari.
    func setActionControlsHidden(_ hidden: Bool) {
        let actionControlsView: UIView
        if #available(iOS 26.0, *) {
            actionControlsView = liquidGlassActionToolbar
        } else {
            actionControlsView = actionButtonStackView
        }
        actionControlsView.isHidden = hidden
        actionControlsTopConstraint.isActive = !hidden
        modeControlAloneConstraint.isActive = hidden
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setMode(_ mode: TabOverview.Mode) {
        tabModeControl.selectedSegmentIndex = mode.rawValue
    }
    
    func apply(tabCount: Int, visibleTabCount: Int, hasVisibleTab: Bool) {
        tabModeControl.setTitle(
            String.localizedStringWithFormat(NSLocalizedString("%d Tabs", comment: "Tab count"), tabCount),
            forSegmentAt: TabOverview.Mode.regularTabs.rawValue
        )
        let clearTabsMenu = TabOverviewClearTabsMenu.make(
            tabCount: visibleTabCount,
            onClearTabs: { [weak self] in self?.onClearTabs?() },
            onClearTabsOlderThan: { [weak self] age in self?.onClearTabsOlderThan?(age) }
        )
        clearTabsButton.installMenu(clearTabsMenu)
        doneButton.setActionEnabled(hasVisibleTab)
        if #available(iOS 26.0, *) {
            liquidGlassActionToolbar.items?.first?.menu = clearTabsMenu
            liquidGlassActionToolbar.items?.last?.isEnabled = hasVisibleTab
        }
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        actionButtonStackView.translatesAutoresizingMaskIntoConstraints = false
        actionButtonStackView.axis = .horizontal
        actionButtonStackView.alignment = .center
        actionButtonStackView.distribution = .equalSpacing
        tabModeControl.translatesAutoresizingMaskIntoConstraints = false
        tabModeControl.selectedSegmentIndex = TabOverview.Mode.regularTabs.rawValue
    }
    
    private func configureHierarchy() {
        if #available(iOS 26.0, *) {
            addSubview(liquidGlassActionToolbar)
        } else {
            addSubview(actionButtonStackView)
        }
        addSubview(tabModeControl)
    }
    
    private func configureConstraints() {
        let actionControlsView: UIView
        if #available(iOS 26.0, *) {
            actionControlsView = liquidGlassActionToolbar
        } else {
            actionControlsView = actionButtonStackView
        }
        actionControlsTopConstraint = tabModeControl.bottomAnchor.constraint(equalTo: actionControlsView.topAnchor, constant: -UX.modeControlToActionControlsSpacing)
        modeControlAloneConstraint = tabModeControl.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -UX.actionControlsBottomOffset)
        NSLayoutConstraint.activate([
            actionControlsView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.toolbarContentHorizontalInset),
            actionControlsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.toolbarContentHorizontalInset),
            actionControlsView.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -UX.actionControlsBottomOffset),
            tabModeControl.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: UX.toolbarContentHorizontalInset),
            tabModeControl.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -UX.toolbarContentHorizontalInset),
            tabModeControl.heightAnchor.constraint(equalToConstant: UX.tabModeControlHeight),
            actionControlsTopConstraint,
        ])
    }
    
    private func configureActions() {
        addTabButton.addTarget(self, action: #selector(addTabButtonTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        tabModeControl.addTarget(self, action: #selector(tabModeControlChanged), for: .valueChanged)
    }
    
    private func makeLiquidGlassActionToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let clearTabsItem = UIBarButtonItem(barButtonSystemItem: .trash, target: nil, action: nil)
        let addTabItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTabButtonTapped))
        let doneItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        clearTabsItem.tintColor = .label
        addTabItem.tintColor = .label
        doneItem.tintColor = .label
        toolbar.items = [
            clearTabsItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            addTabItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            doneItem,
        ]
        return toolbar
    }
    
    @objc private func addTabButtonTapped() { onAddTab?() }
    @objc private func doneTapped() { onDone?() }
    @objc private func tabModeControlChanged() {
        onTabModeChange?(TabOverview.Mode(rawValue: tabModeControl.selectedSegmentIndex) ?? .regularTabs)
    }
}
