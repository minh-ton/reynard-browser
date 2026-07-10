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
                return SettingsSectionText(headerTitle: "Address Bar")
            case .tabs:
                return SettingsSectionText(headerTitle: "Tabs")
            case .pageZoom:
                return SettingsSectionText(headerTitle: "Websites")
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
        title = "Appearance"
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
            cell.textLabel?.text = "Show Full Website Address"
            cell.selectionStyle = .none
            cell.accessoryView = showFullWebsiteAddressSwitch
            return cell
        case .landscapeTabBar:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Show Tab Bar in Landscape"
            cell.selectionStyle = .none
            cell.accessoryView = landscapeTabBarSwitch
            return cell
        case .pageZoom:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Page Zoom"
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
        
        if displayedSections[indexPath.section].rows[indexPath.row] == .pageZoom {
            navigationController?.pushViewController(PageZoomPreferencesViewController(), animated: true)
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
