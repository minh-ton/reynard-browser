//
//  AppearancePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class AppearancePreferencesViewController: SettingsTableViewController {
    // MARK: - Sections

    private enum Section: CaseIterable {
        case tabs

        var text: SettingsSectionText {
            switch self {
            case .tabs:
                return SettingsSectionText(headerTitle: "Tabs")
            }
        }
    }

    private enum Row: CaseIterable {
        case browserChromePosition
        case landscapeTabBar
    }

    // MARK: - State

    private let landscapeTabBarSwitch = UISwitch()
    
    private var displayedSections: [Section] {
        UIDevice.current.userInterfaceIdiom == .pad ? [] : Section.allCases
    }

    // MARK: - Lifecycle
    
    init() {
        super.init(style: .insetGrouped)
        configureViewController()
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

    // MARK: - Table Structure
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        return Row.allCases.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }

    // MARK: - Cells

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section),
              Row.allCases.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        switch Row.allCases[indexPath.row] {
        case .browserChromePosition:
            let cell = BrowserChromePositionPickerCell(style: .default, reuseIdentifier: nil)
            cell.display(selectedPosition: Prefs.AppearanceSettings.addressBarPosition)
            cell.onPositionChanged = { position in
                Prefs.AppearanceSettings.addressBarPosition = position
            }
            return cell
        case .landscapeTabBar:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Landscape Tab Bar"
            cell.selectionStyle = .none
            cell.accessoryView = landscapeTabBarSwitch
            return cell
        }
    }

    // MARK: - View Setup
    
    private func configureViewController() {
        title = "Appearance"
    }
    
    private func configureSwitch() {
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchDidChange), for: .valueChanged)
    }

    // MARK: - Display
    
    private func refreshDisplayedState() {
        landscapeTabBarSwitch.isOn = Prefs.AppearanceSettings.showsLandscapeTabBar
    }

    // MARK: - Actions
    
    @objc private func landscapeTabBarSwitchDidChange() {
        Prefs.AppearanceSettings.showsLandscapeTabBar = landscapeTabBarSwitch.isOn
    }
}
