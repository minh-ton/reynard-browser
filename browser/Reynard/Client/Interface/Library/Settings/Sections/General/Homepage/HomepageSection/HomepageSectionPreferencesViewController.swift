//
//  HomepageSectionPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 25/6/26.
//

import UIKit

final class HomepageSectionPreferencesViewController: SettingsTableViewController {
    enum OverviewRow: CaseIterable {
        case favorites
        case frequentlyVisited
        case recentlyClosedTabs
        
        var title: String {
            return preference.title
        }
        
        var isEnabled: Bool {
            return preference.isEnabled
        }
        
        var preference: Preference {
            switch self {
            case .favorites:
                return .favorites
            case .frequentlyVisited:
                return .frequentlyVisited
            case .recentlyClosedTabs:
                return .recentlyClosedTabs
            }
        }
    }
    
    enum Preference: CaseIterable {
        case favorites
        case frequentlyVisited
        case recentlyClosedTabs
        
        var title: String {
            switch self {
            case .favorites:
                return "Favorites"
            case .frequentlyVisited:
                return "Frequently Visited"
            case .recentlyClosedTabs:
                return "Recently Closed Tabs"
            }
        }
        
        var switchTitle: String {
            switch self {
            case .favorites:
                return "Show Favorites"
            case .frequentlyVisited:
                return "Show Frequently Visited"
            case .recentlyClosedTabs:
                return "Show Recently Closed Tabs"
            }
        }
        
        var countTitle: String {
            switch self {
            case .favorites:
                return "Number of Rows"
            case .frequentlyVisited:
                return "Number of Websites"
            case .recentlyClosedTabs:
                return "Number of Tabs"
            }
        }
        
        var countValues: [Int] {
            switch self {
            case .favorites:
                return Array(1...5)
            case .frequentlyVisited:
                return Array(4...8)
            case .recentlyClosedTabs:
                return Array(3...10)
            }
        }
        
        var isEnabled: Bool {
            switch self {
            case .favorites:
                return Prefs.HomepageSettings.showsFavorites
            case .frequentlyVisited:
                return Prefs.HomepageSettings.showsFrequentlyVisited
            case .recentlyClosedTabs:
                return Prefs.HomepageSettings.showsRecentlyClosedTabs
            }
        }
        
        var isEnabledInPrivateBrowsing: Bool {
            switch self {
            case .favorites:
                return Prefs.HomepageSettings.showsFavoritesInPrivateBrowsing
            case .frequentlyVisited:
                return Prefs.HomepageSettings.showsFrequentlyVisitedInPrivateBrowsing
            case .recentlyClosedTabs:
                return false
            }
        }
        
        var selectedCount: Int {
            switch self {
            case .favorites:
                return Prefs.HomepageSettings.favoriteRowCount
            case .frequentlyVisited:
                return Prefs.HomepageSettings.frequentlyVisitedSiteCount
            case .recentlyClosedTabs:
                return Prefs.HomepageSettings.recentlyClosedTabLimit
            }
        }
        
        func setEnabled(_ isEnabled: Bool) {
            switch self {
            case .favorites:
                Prefs.HomepageSettings.showsFavorites = isEnabled
            case .frequentlyVisited:
                Prefs.HomepageSettings.showsFrequentlyVisited = isEnabled
            case .recentlyClosedTabs:
                Prefs.HomepageSettings.showsRecentlyClosedTabs = isEnabled
            }
        }
        
        func setEnabledInPrivateBrowsing(_ isEnabled: Bool) {
            switch self {
            case .favorites:
                Prefs.HomepageSettings.showsFavoritesInPrivateBrowsing = isEnabled
            case .frequentlyVisited:
                Prefs.HomepageSettings.showsFrequentlyVisitedInPrivateBrowsing = isEnabled
            case .recentlyClosedTabs:
                return
            }
        }
        
        func setSelectedCount(_ selectedCount: Int) {
            switch self {
            case .favorites:
                Prefs.HomepageSettings.favoriteRowCount = selectedCount
            case .frequentlyVisited:
                Prefs.HomepageSettings.frequentlyVisitedSiteCount = selectedCount
            case .recentlyClosedTabs:
                Prefs.HomepageSettings.recentlyClosedTabLimit = selectedCount
            }
        }
    }
    
    private enum Section: CaseIterable {
        case main
        case count
    }
    
    private enum Row: CaseIterable {
        case showSection
        case showInPrivateBrowsing
        case count
    }
    
    private let preference: Preference
    private let sectionSwitch = UISwitch()
    private let privateBrowsingSwitch = UISwitch()
    
    private func displayedRows(in section: Section) -> [Row] {
        switch section {
        case .main:
            switch preference {
            case .recentlyClosedTabs:
                return [.showSection]
            default:
                return [.showSection, .showInPrivateBrowsing]
            }
        case .count:
            return [.count]
        }
    }
    
    init(preference: Preference) {
        self.preference = preference
        super.init(style: .insetGrouped)
        title = preference.title
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
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        return displayedRows(in: Section.allCases[section]).count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        let rows = displayedRows(in: Section.allCases[indexPath.section])
        guard rows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch rows[indexPath.row] {
        case .showSection:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = preference.switchTitle
            cell.selectionStyle = .none
            cell.accessoryView = sectionSwitch
            return cell
        case .showInPrivateBrowsing:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Show in Private Browsing"
            cell.selectionStyle = .none
            cell.accessoryView = privateBrowsingSwitch
            return cell
        case .count:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = preference.countTitle
            configureCountPickerCell(cell)
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        let rows = displayedRows(in: Section.allCases[indexPath.section])
        guard rows.indices.contains(indexPath.row),
              rows[indexPath.row] == .count else {
            return
        }
        
        handleCountSelection(at: indexPath)
    }
    
    private func configureCountPickerCell(_ cell: UITableViewCell) {
        if #available(iOS 14.0, *) {
            cell.detailTextLabel?.text = nil
            cell.accessoryView = countMenuButton()
            cell.accessoryType = .none
        } else {
            cell.detailTextLabel?.text = "\(preference.selectedCount)"
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
    }
    
    private func handleCountSelection(at indexPath: IndexPath) {
        if #available(iOS 14.0, *) {
            if #available(iOS 17.4, *),
               let cell = tableView.cellForRow(at: indexPath),
               let button = cell.accessoryView as? UIButton {
                button.performPrimaryAction()
            }
            return
        }
        
        let viewController = HomepageSectionItemCountPreferencesViewController(
            title: preference.countTitle,
            values: preference.countValues,
            selectedValue: preference.selectedCount
        ) { [preference] value in
            preference.setSelectedCount(value)
        }
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func applyCount(_ count: Int) {
        preference.setSelectedCount(count)
        tableView.reloadData()
    }
    
    private func configureSwitch() {
        sectionSwitch.addTarget(self, action: #selector(sectionSwitchDidChange), for: .valueChanged)
        privateBrowsingSwitch.addTarget(self, action: #selector(privateBrowsingSwitchDidChange), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        sectionSwitch.isOn = preference.isEnabled
        privateBrowsingSwitch.isOn = preference.isEnabledInPrivateBrowsing
    }
    
    @objc private func sectionSwitchDidChange() {
        preference.setEnabled(sectionSwitch.isOn)
    }
    
    @objc private func privateBrowsingSwitchDidChange() {
        preference.setEnabledInPrivateBrowsing(privateBrowsingSwitch.isOn)
    }
    
    @available(iOS 14.0, *)
    private func countMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("\(preference.selectedCount)", for: .normal)
        button.setImage(UIImage(named: "reynard.chevron.up.chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        if #available(iOS 15.0, *) {
            button.changesSelectionAsPrimaryAction = true
        }
        button.menu = countMenu()
        button.sizeToFit()
        return button
    }
    
    @available(iOS 14.0, *)
    private func countMenu() -> UIMenu {
        let actions = preference.countValues.map { count in
            UIAction(title: "\(count)", state: count == preference.selectedCount ? .on : .off) { [weak self] _ in
                self?.applyCount(count)
            }
        }
        
        if #available(iOS 15.0, *) {
            return UIMenu(title: "", options: .singleSelection, children: actions)
        }
        return UIMenu(title: "", children: actions)
    }
}
