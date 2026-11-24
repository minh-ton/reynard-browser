//
//  AppearancePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class AppearancePreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable, Equatable {
        case appAppearance
        case addressBar
        case toolbar
        case gestures
        case tabs
        
        var text: SettingsSectionText {
            switch self {
            case .appAppearance:
                return SettingsSectionText()
            case .addressBar:
                return SettingsSectionText(headerTitle: NSLocalizedString("Address Bar", comment: ""))
            case .toolbar:
                return SettingsSectionText(headerTitle: NSLocalizedString("Toolbar", comment: ""))
            case .gestures:
                return SettingsSectionText(headerTitle: NSLocalizedString("Gestures", comment: ""))
            case .tabs:
                return SettingsSectionText(headerTitle: NSLocalizedString("Tabs", comment: ""))
            }
        }
    }
    
    private enum Row: Equatable {
        case appAppearance
        case BrowserChromePosition
        case showFullWebsiteAddress
        case customizeToolbar
        case pullToRefresh
        case scrollToHideToolbar
        case swipeAddressBarSideways
        case swipeAddressBarUp
        case landscapeTabBar
    }
    
    private let showFullWebsiteAddressSwitch = UISwitch()
    private let pullToRefreshSwitch = UISwitch()
    private let scrollToHideToolbarSwitch = UISwitch()
    private let swipeAddressBarSidewaysSwitch = UISwitch()
    private let swipeAddressBarUpSwitch = UISwitch()
    private let landscapeTabBarSwitch = UISwitch()
    private var displayedAddressBarPosition = Prefs.AppearanceSettings.addressBarPosition
    
    private var displayedSections: [Section] {
        return Section.allCases.filter { section in
            !rows(for: section).isEmpty
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBarPositionDidChange),
            name: .addressBarPositionDidChange,
            object: nil
        )
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        displayedAddressBarPosition = Prefs.AppearanceSettings.addressBarPosition
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
        return rows(for: displayedSections[section]).count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section),
              rows(for: displayedSections[indexPath.section]).indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch rows(for: displayedSections[indexPath.section])[indexPath.row] {
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
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Show Full Website Address", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = showFullWebsiteAddressSwitch
            return cell
        case .customizeToolbar:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Customize Toolbar", comment: ""))
        case .pullToRefresh:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Pull to Refresh", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = pullToRefreshSwitch
            return cell
        case .scrollToHideToolbar:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Scroll to Hide Toolbar", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = scrollToHideToolbarSwitch
            return cell
        case .swipeAddressBarSideways:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Swipe Address Bar Sideways to Switch Tabs", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = swipeAddressBarSidewaysSwitch
            return cell
        case .swipeAddressBarUp:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Swipe Address Bar Up to See Open Tabs", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = swipeAddressBarUpSwitch
            return cell
        case .landscapeTabBar:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Show Tab Bar in Landscape", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = landscapeTabBarSwitch
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section),
              rows(for: displayedSections[indexPath.section]).indices.contains(indexPath.row) else {
            return
        }
        
        if rows(for: displayedSections[indexPath.section])[indexPath.row] == .customizeToolbar {
            navigationController?.pushViewController(ToolbarPreferencesViewController(), animated: true)
        }
    }
    
    private func configureSwitch() {
        showFullWebsiteAddressSwitch.addTarget(self, action: #selector(showFullWebsiteAddressSwitchDidChange), for: .valueChanged)
        pullToRefreshSwitch.addTarget(self, action: #selector(pullToRefreshSwitchDidChange), for: .valueChanged)
        scrollToHideToolbarSwitch.addTarget(self, action: #selector(scrollToHideToolbarSwitchDidChange), for: .valueChanged)
        swipeAddressBarSidewaysSwitch.addTarget(self, action: #selector(swipeAddressBarSidewaysSwitchDidChange), for: .valueChanged)
        swipeAddressBarUpSwitch.addTarget(self, action: #selector(swipeAddressBarUpSwitchDidChange), for: .valueChanged)
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchDidChange), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        showFullWebsiteAddressSwitch.isOn = Prefs.AppearanceSettings.showsFullWebsiteAddress
        pullToRefreshSwitch.isOn = Prefs.AppearanceSettings.pullToRefreshEnabled
        scrollToHideToolbarSwitch.isOn = Prefs.AppearanceSettings.scrollToHideToolbarEnabled
        swipeAddressBarSidewaysSwitch.isOn = Prefs.AppearanceSettings.swipeAddressBarSidewaysEnabled
        swipeAddressBarUpSwitch.isOn = Prefs.AppearanceSettings.swipeAddressBarUpEnabled
        landscapeTabBarSwitch.isOn = Prefs.AppearanceSettings.showsLandscapeTabBar
    }
    
    @objc private func showFullWebsiteAddressSwitchDidChange() {
        Prefs.AppearanceSettings.showsFullWebsiteAddress = showFullWebsiteAddressSwitch.isOn
    }
    
    @objc private func pullToRefreshSwitchDidChange() {
        Prefs.AppearanceSettings.pullToRefreshEnabled = pullToRefreshSwitch.isOn
    }
    
    @objc private func scrollToHideToolbarSwitchDidChange() {
        Prefs.AppearanceSettings.scrollToHideToolbarEnabled = scrollToHideToolbarSwitch.isOn
        BrowserWindowManager.shared.browsers.forEach { $0.toolbarController.reset(animated: true) }
    }
    
    @objc private func swipeAddressBarSidewaysSwitchDidChange() {
        Prefs.AppearanceSettings.swipeAddressBarSidewaysEnabled = swipeAddressBarSidewaysSwitch.isOn
    }
    
    @objc private func swipeAddressBarUpSwitchDidChange() {
        Prefs.AppearanceSettings.swipeAddressBarUpEnabled = swipeAddressBarUpSwitch.isOn
    }
    
    @objc private func landscapeTabBarSwitchDidChange() {
        Prefs.AppearanceSettings.showsLandscapeTabBar = landscapeTabBarSwitch.isOn
    }
    
    @objc private func addressBarPositionDidChange() {
        let previousRows = rows(for: .gestures)
        let updatedPosition = Prefs.AppearanceSettings.addressBarPosition
        let updatedRows = rows(for: .gestures, addressBarPosition: updatedPosition)
        guard previousRows != updatedRows,
              let section = displayedSections.firstIndex(of: .gestures) else {
            displayedAddressBarPosition = updatedPosition
            return
        }
        
        let deletedIndexPaths = previousRows.enumerated().compactMap { index, row in
            updatedRows.contains(row) ? nil : IndexPath(row: index, section: section)
        }
        let insertedIndexPaths = updatedRows.enumerated().compactMap { index, row in
            previousRows.contains(row) ? nil : IndexPath(row: index, section: section)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.tableView.performBatchUpdates {
                self.displayedAddressBarPosition = updatedPosition
                self.tableView.deleteRows(at: deletedIndexPaths, with: .automatic)
                self.tableView.insertRows(at: insertedIndexPaths, with: .automatic)
            }
        }
    }
    
    private func rows(
        for section: Section,
        addressBarPosition: BrowserChromePosition? = nil
    ) -> [Row] {
        let position = addressBarPosition ?? displayedAddressBarPosition
        switch section {
        case .appAppearance:
            return [.appAppearance]
        case .addressBar:
            if UIDevice.current.userInterfaceIdiom == .pad {
                return [.showFullWebsiteAddress]
            }
            return [.BrowserChromePosition, .showFullWebsiteAddress]
        case .toolbar:
            return [.customizeToolbar]
        case .gestures:
            var rows: [Row] = [.pullToRefresh, .scrollToHideToolbar]
            guard position == .bottom,
                  UIDevice.current.userInterfaceIdiom == .phone else {
                return rows
            }
            rows.append(.swipeAddressBarSideways)
            rows.append(.swipeAddressBarUp)
            return rows
        case .tabs:
            if UIDevice.current.userInterfaceIdiom == .pad {
                return []
            }
            return [.landscapeTabBar]
        }
    }
}
