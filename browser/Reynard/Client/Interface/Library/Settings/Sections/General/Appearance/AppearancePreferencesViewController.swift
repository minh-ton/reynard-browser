//
//  AppearancePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class AppearancePreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case appAppearance
        case addressBar
        case tabs
        case pageZoom
        
        var text: SettingsSectionText {
            switch self {
            case .appAppearance:
                return SettingsSectionText()
            case .addressBar:
                return SettingsSectionText(headerTitle: NSLocalizedString("Address Bar", comment: ""))
            case .tabs:
                return SettingsSectionText(headerTitle: NSLocalizedString("Tabs", comment: ""))
            case .pageZoom:
                return SettingsSectionText(headerTitle: NSLocalizedString("Websites", comment: ""))
            }
        }
        
        var rows: [Row] {
            switch self {
            case .appAppearance:
                return [.appAppearance]
            case .addressBar:
                if UIDevice.current.userInterfaceIdiom == .pad {
                    return [.showFullWebsiteAddress]
                }
                return [.BrowserChromePosition, .showFullWebsiteAddress]
            case .tabs:
                if UIDevice.current.userInterfaceIdiom == .pad {
                    return []
                }
                return [.landscapeTabBar]
            case .pageZoom:
                return [.pageZoom]
            }
        }
    }
    
    private enum Row {
        case appAppearance
        case BrowserChromePosition
        case showFullWebsiteAddress
        case landscapeTabBar
        case pageZoom
    }
    
    private let showFullWebsiteAddressSwitch = UISwitch()
    private let landscapeTabBarSwitch = UISwitch()
    
    private var displayedSections: [Section] {
        return Section.allCases.filter { section in
            !section.rows.isEmpty
        }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Appearance", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitch()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        return displayedSections[section].rows.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section].rows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section].rows[indexPath.row] {
        case .appAppearance:
            let cell = AppAppearancePickerCell(style: .default, reuseIdentifier: nil)
            cell.display(selectedAppearance: Prefs.AppearanceSettings.appAppearance)
            cell.onAppearanceChanged = { appearance in
                Prefs.AppearanceSettings.appAppearance = appearance
                AppAppearanceController.apply(appearance)
            }
            return cell
        case .BrowserChromePosition:
            let cell = AddressBarPositionPickerCell(style: .default, reuseIdentifier: nil)
            cell.display(selectedPosition: Prefs.AppearanceSettings.addressBarPosition)
            cell.onPositionChanged = { position in
                Prefs.AppearanceSettings.addressBarPosition = position
            }
            return cell
        case .showFullWebsiteAddress:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Show Full Website Address", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = showFullWebsiteAddressSwitch
            return cell
        case .landscapeTabBar:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Show Tab Bar in Landscape", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = landscapeTabBarSwitch
            return cell
        case .pageZoom:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Page Zoom", comment: "")
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section].rows.indices.contains(indexPath.row) else {
            return
        }
        
        switch displayedSections[indexPath.section].rows[indexPath.row] {
        case .pageZoom:
            navigationController?.pushViewController(PageZoomPreferencesViewController(), animated: true)
        default:
            break
        }
    }
    
    private func configureSwitch() {
        showFullWebsiteAddressSwitch.addTarget(self, action: #selector(showFullWebsiteAddressSwitchDidChange), for: .valueChanged)
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchDidChange), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        showFullWebsiteAddressSwitch.isOn = Prefs.AppearanceSettings.showsFullWebsiteAddress
        landscapeTabBarSwitch.isOn = Prefs.AppearanceSettings.showsLandscapeTabBar
    }
    
    @objc private func showFullWebsiteAddressSwitchDidChange() {
        Prefs.AppearanceSettings.showsFullWebsiteAddress = showFullWebsiteAddressSwitch.isOn
    }
    
    @objc private func landscapeTabBarSwitchDidChange() {
        Prefs.AppearanceSettings.showsLandscapeTabBar = landscapeTabBarSwitch.isOn
    }
}

final class BottomToolbarPreferencesViewController: UITableViewController {
    private enum UX {
        static let previewHeaderHeight: CGFloat = 64
        static let previewVerticalInset: CGFloat = 8
    }

    private enum Section: Int, CaseIterable {
        case reset
        case included
        case available
        case feedback
        case shortcuts
    }

    private var includedActions = Prefs.AppearanceSettings.bottomToolbarActions
    private let closeTabShortcutSwitch = UISwitch()
    private let newTabShortcutSwitch = UISwitch()
    private let toolbarHapticsSwitch = UISwitch()
    private let toolbarPreview = BottomToolbarPreviewView()
    private var previewHeaderView: UIView?

    private var availableActions: [BottomToolbarAction] {
        BottomToolbarAction.allCases.filter { !includedActions.contains($0) }
    }

    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Customize Toolbar", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureToolbarPreview()
        closeTabShortcutSwitch.isOn = Prefs.AppearanceSettings.closeTabLongPressOpensNewTab
        newTabShortcutSwitch.isOn = Prefs.AppearanceSettings.newTabLongPressClosesTab
        toolbarHapticsSwitch.isOn = Prefs.AppearanceSettings.toolbarButtonHapticsEnabled
        closeTabShortcutSwitch.addTarget(self, action: #selector(closeTabShortcutChanged), for: .valueChanged)
        newTabShortcutSwitch.addTarget(self, action: #selector(newTabShortcutChanged), for: .valueChanged)
        toolbarHapticsSwitch.addTarget(self, action: #selector(toolbarHapticsChanged), for: .valueChanged)
        tableView.allowsSelectionDuringEditing = true
        setEditing(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let previewHeaderView,
              previewHeaderView.frame.width != tableView.bounds.width else {
            return
        }
        previewHeaderView.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = previewHeaderView
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .reset:
            return 1
        case .included:
            return includedActions.count
        case .available:
            return availableActions.count
        case .feedback:
            return 1
        case .shortcuts:
            return 2
        case nil:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .reset:
            return nil
        case .included:
            return NSLocalizedString("Enabled Items", comment: "")
        case .available:
            return NSLocalizedString("Available Items", comment: "")
        case .feedback:
            return NSLocalizedString("Feedback", comment: "")
        case .shortcuts:
            return NSLocalizedString("Button Shortcuts", comment: "")
        case nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .reset:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Reset to Original", comment: "")
            cell.textLabel?.textColor = view.tintColor
            cell.textLabel?.textAlignment = .center
            return cell
        case .included:
            guard let action = includedActions[safe: indexPath.row] else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = action.title
            cell.imageView?.image = UIImage(named: action.imageName)
            cell.selectionStyle = .none
            return cell
        case .available:
            guard let action = availableActions[safe: indexPath.row] else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = action.title
            cell.imageView?.image = UIImage(named: action.imageName)
            cell.selectionStyle = .none
            let canAdd = includedActions.count < BottomToolbarAction.maximumVisibleActions
            cell.textLabel?.textColor = canAdd ? .label : .secondaryLabel
            cell.imageView?.tintColor = canAdd ? view.tintColor : .secondaryLabel
            return cell
        case .feedback:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Toolbar Button Haptics", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = toolbarHapticsSwitch
            cell.editingAccessoryView = toolbarHapticsSwitch
            toolbarHapticsSwitch.accessibilityLabel = NSLocalizedString("Toolbar Button Haptics", comment: "")
            return cell
        case .shortcuts:
            return makeShortcutCell(row: indexPath.row)
        }
    }

    private func makeShortcutCell(row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.detailTextLabel?.textColor = .secondaryLabel
        if row == 0 {
            cell.textLabel?.text = NSLocalizedString("Close Tab", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Hold to open a new tab", comment: "")
            cell.accessoryView = closeTabShortcutSwitch
            cell.editingAccessoryView = closeTabShortcutSwitch
        } else {
            cell.textLabel?.text = NSLocalizedString("New Tab", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Hold to close the current tab", comment: "")
            cell.accessoryView = newTabShortcutSwitch
            cell.editingAccessoryView = newTabShortcutSwitch
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let section = Section(rawValue: indexPath.section) else {
            return
        }
        switch section {
        case .reset:
            resetToolbar()
        case .shortcuts:
            UISelectionFeedbackGenerator().selectionChanged()
            if indexPath.row == 0 {
                closeTabShortcutSwitch.setOn(!closeTabShortcutSwitch.isOn, animated: true)
                closeTabShortcutChanged()
            } else {
                newTabShortcutSwitch.setOn(!newTabShortcutSwitch.isOn, animated: true)
                newTabShortcutChanged()
            }
        default:
            return
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        switch Section(rawValue: indexPath.section) {
        case .included:
            return .delete
        case .available:
            return includedActions.count < BottomToolbarAction.maximumVisibleActions ? .insert : .none
        default:
            return .none
        }
    }

    override func tableView(
        _ tableView: UITableView,
        shouldIndentWhileEditingRowAt indexPath: IndexPath
    ) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .included, .available:
            return true
        default:
            return false
        }
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch editingStyle {
        case .delete:
            guard includedActions.indices.contains(indexPath.row) else {
                return
            }
            includedActions.remove(at: indexPath.row)
        case .insert:
            guard includedActions.count < BottomToolbarAction.maximumVisibleActions,
                  let action = availableActions[safe: indexPath.row] else {
                return
            }
            includedActions.append(action)
        default:
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        persistAndReload()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.included.rawValue
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedDestinationIndexPath.section == Section.included.rawValue else {
            return IndexPath(row: max(includedActions.count - 1, 0), section: Section.included.rawValue)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard includedActions.indices.contains(sourceIndexPath.row) else {
            return
        }
        let action = includedActions.remove(at: sourceIndexPath.row)
        includedActions.insert(action, at: min(destinationIndexPath.row, includedActions.count))
        Prefs.AppearanceSettings.bottomToolbarActions = includedActions
        toolbarPreview.apply(actions: includedActions)
    }

    private func persistAndReload() {
        Prefs.AppearanceSettings.bottomToolbarActions = includedActions
        toolbarPreview.apply(actions: includedActions)
        UIView.performWithoutAnimation {
            tableView.reloadData()
            setEditing(true, animated: false)
        }
    }

    @objc private func closeTabShortcutChanged() {
        Prefs.AppearanceSettings.closeTabLongPressOpensNewTab = closeTabShortcutSwitch.isOn
        updateShortcutRow(0)
    }

    @objc private func newTabShortcutChanged() {
        Prefs.AppearanceSettings.newTabLongPressClosesTab = newTabShortcutSwitch.isOn
        updateShortcutRow(1)
    }

    @objc private func toolbarHapticsChanged() {
        Prefs.AppearanceSettings.toolbarButtonHapticsEnabled = toolbarHapticsSwitch.isOn
    }

    private func updateShortcutRow(_ row: Int) {
        let indexPath = IndexPath(row: row, section: Section.shortcuts.rawValue)
        guard let cell = tableView.cellForRow(at: indexPath) else {
            return
        }
        if row == 0 {
            cell.detailTextLabel?.text = NSLocalizedString("Hold to open a new tab", comment: "")
            closeTabShortcutSwitch.accessibilityValue = closeTabShortcutSwitch.isOn
                ? NSLocalizedString("On", comment: "")
                : NSLocalizedString("Off", comment: "")
        } else {
            cell.detailTextLabel?.text = NSLocalizedString("Hold to close the current tab", comment: "")
            newTabShortcutSwitch.accessibilityValue = newTabShortcutSwitch.isOn
                ? NSLocalizedString("On", comment: "")
                : NSLocalizedString("Off", comment: "")
        }
    }

    @objc private func resetToolbar() {
        includedActions = BottomToolbarAction.defaultActions
        toolbarHapticsSwitch.setOn(true, animated: true)
        closeTabShortcutSwitch.setOn(true, animated: true)
        newTabShortcutSwitch.setOn(false, animated: true)
        Prefs.AppearanceSettings.toolbarButtonHapticsEnabled = true
        Prefs.AppearanceSettings.closeTabLongPressOpensNewTab = true
        Prefs.AppearanceSettings.newTabLongPressClosesTab = false
        UISelectionFeedbackGenerator().selectionChanged()
        persistAndReload()
    }

    private func configureToolbarPreview() {
        let header = UIView(frame: CGRect(
            x: 0,
            y: 0,
            width: tableView.bounds.width,
            height: UX.previewHeaderHeight
        ))
        toolbarPreview.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(toolbarPreview)
        NSLayoutConstraint.activate([
            toolbarPreview.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            toolbarPreview.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            toolbarPreview.topAnchor.constraint(equalTo: header.topAnchor, constant: UX.previewVerticalInset),
            toolbarPreview.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -UX.previewVerticalInset),
        ])
        toolbarPreview.apply(actions: includedActions)
        previewHeaderView = header
        tableView.tableHeaderView = header
    }
}

private final class BottomToolbarPreviewView: UIView {
    private enum UX {
        static let horizontalInset: CGFloat = 24
        static let buttonSpacing: CGFloat = 4
        static let symbolPointSize: CGFloat = 18
        static let separatorHeight = 1 / UIScreen.main.scale
    }

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = UX.buttonSpacing
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGray6
        addSubview(buttonStack)

        let topSeparator = makeSeparator()
        let bottomSeparator = makeSeparator()
        addSubview(topSeparator)
        addSubview(bottomSeparator)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.horizontalInset),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.horizontalInset),
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: UX.separatorHeight),

            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: UX.separatorHeight),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(actions: [BottomToolbarAction]) {
        buttonStack.arrangedSubviews.forEach { button in
            buttonStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }

        let configuration = UIImage.SymbolConfiguration(pointSize: UX.symbolPointSize, weight: .regular)
        for action in actions {
            let button = UIButton(type: .system)
            button.isUserInteractionEnabled = false
            button.tintColor = .label
            button.setImage(UIImage(named: action.imageName, in: .main, with: configuration), for: .normal)
            button.accessibilityLabel = action.title
            buttonStack.addArrangedSubview(button)
        }
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        return separator
    }
}
