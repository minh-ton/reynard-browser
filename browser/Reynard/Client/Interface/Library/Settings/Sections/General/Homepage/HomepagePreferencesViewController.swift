//
//  HomepagePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 25/6/26.
//

import UIKit

final class HomepagePreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case openingScreen
        case includeOnHomepage
        case homepageBanners
        
        var text: SettingsSectionText {
            switch self {
            case .openingScreen:
                return SettingsSectionText(headerTitle: NSLocalizedString("On Startup", comment: ""))
            case .includeOnHomepage:
                return SettingsSectionText(headerTitle: NSLocalizedString("Homepage Sections", comment: ""))
            case .homepageBanners:
                return SettingsSectionText(headerTitle: NSLocalizedString("Homepage Banners", comment: ""))
            }
        }
    }
    
    private enum HomepageBannerRow: CaseIterable {
        case recommendations
        case newUpdates
    }
    
    private let recommendationsSwitch = UISwitch()
    private let newUpdatesSwitch = UISwitch()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Homepage", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitches()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .openingScreen:
            return HomepageOpeningScreen.allCases.count
        case .includeOnHomepage:
            return HomepageSectionPreferencesViewController.OverviewRow.allCases.count
        case .homepageBanners:
            return HomepageBannerRow.allCases.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch Section.allCases[indexPath.section] {
        case .openingScreen:
            guard HomepageOpeningScreen.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let openingScreen = HomepageOpeningScreen.allCases[indexPath.row]
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = openingScreen.title
            cell.accessoryType = Prefs.HomepageSettings.openingScreen == openingScreen ? .checkmark : .none
            return cell
        case .includeOnHomepage:
            guard HomepageSectionPreferencesViewController.OverviewRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let row = HomepageSectionPreferencesViewController.OverviewRow.allCases[indexPath.row]
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.isEnabled ? NSLocalizedString("On", comment: "Enabled state") : NSLocalizedString("Off", comment: "Disabled state")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .homepageBanners:
            guard HomepageBannerRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            switch HomepageBannerRow.allCases[indexPath.row] {
            case .recommendations:
                cell.textLabel?.text = NSLocalizedString("Recommendations", comment: "")
                cell.accessoryView = recommendationsSwitch
            case .newUpdates:
                cell.textLabel?.text = NSLocalizedString("New Updates", comment: "")
                cell.accessoryView = newUpdatesSwitch
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .openingScreen:
            guard HomepageOpeningScreen.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            Prefs.HomepageSettings.openingScreen = HomepageOpeningScreen.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .includeOnHomepage:
            guard HomepageSectionPreferencesViewController.OverviewRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            let viewController = HomepageSectionPreferencesViewController(
                preference: HomepageSectionPreferencesViewController.OverviewRow.allCases[indexPath.row].preference
            )
            navigationController?.pushViewController(viewController, animated: true)
        case .homepageBanners:
            return
        }
    }
    
    private func configureSwitches() {
        recommendationsSwitch.addTarget(self, action: #selector(recommendationsSwitchDidChange(_:)), for: .valueChanged)
        newUpdatesSwitch.addTarget(self, action: #selector(newUpdatesSwitchDidChange(_:)), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        recommendationsSwitch.isOn = Prefs.HomepageSettings.showsRecommendations
        newUpdatesSwitch.isOn = Prefs.HomepageSettings.showsNewUpdates
    }
    
    @objc private func recommendationsSwitchDidChange(_ sender: UISwitch) {
        Prefs.HomepageSettings.showsRecommendations = sender.isOn
    }
    
    @objc private func newUpdatesSwitchDidChange(_ sender: UISwitch) {
        Prefs.HomepageSettings.showsNewUpdates = sender.isOn
    }
}
