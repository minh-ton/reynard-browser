//
//  SearchPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SearchPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case searchEngine
        case searchSuggestions
        
        var text: SettingsSectionText {
            switch self {
            case .searchEngine:
                return SettingsSectionText(headerTitle: NSLocalizedString("Search Engine", comment: ""))
            case .searchSuggestions:
                return SettingsSectionText(headerTitle: NSLocalizedString("Search Suggestions", comment: ""))
            }
        }
    }
    
    private enum SearchSuggestionsRow: CaseIterable {
        case showSearchSuggestions
        case showInPrivateBrowsing
        case searchBrowsingHistory
        case searchBookmarks
        case searchOpenedTabs
        case searchSuggestionProvider
    }
    
    private let showSearchSuggestionsSwitch = UISwitch()
    private let showInPrivateBrowsingSwitch = UISwitch()
    private let searchBrowsingHistorySwitch = UISwitch()
    private let searchBookmarksSwitch = UISwitch()
    private let searchOpenedTabsSwitch = UISwitch()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Search", comment: "")
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
        case .searchEngine:
            return 1
        case .searchSuggestions:
            return SearchSuggestionsRow.allCases.count
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
        case .searchEngine:
            guard indexPath.row == 0 else {
                return UITableViewCell()
            }
            
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Search Engine", comment: "")
            cell.detailTextLabel?.text = Prefs.SearchSettings.searchEngine.displayName
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        case .searchSuggestions:
            guard SearchSuggestionsRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            switch SearchSuggestionsRow.allCases[indexPath.row] {
            case .showSearchSuggestions:
                return switchCell(title: NSLocalizedString("Show Search Suggestions", comment: ""), accessoryView: showSearchSuggestionsSwitch)
            case .showInPrivateBrowsing:
                return switchCell(title: NSLocalizedString("Show in Private Browsing", comment: ""), accessoryView: showInPrivateBrowsingSwitch)
            case .searchBrowsingHistory:
                return switchCell(title: NSLocalizedString("Search Browsing History", comment: ""), accessoryView: searchBrowsingHistorySwitch)
            case .searchBookmarks:
                return switchCell(title: NSLocalizedString("Search Bookmarks", comment: ""), accessoryView: searchBookmarksSwitch)
            case .searchOpenedTabs:
                return switchCell(title: NSLocalizedString("Search Opened Tabs", comment: ""), accessoryView: searchOpenedTabsSwitch)
            case .searchSuggestionProvider:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = NSLocalizedString("Search Suggestion Provider", comment: "")
                cell.detailTextLabel?.text = Prefs.SearchSettings.searchSuggestionProvider.name
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .searchEngine:
            guard indexPath.row == 0 else {
                return
            }
            navigationController?.pushViewController(SearchEnginePreferencesViewController(), animated: true)
        case .searchSuggestions:
            guard SearchSuggestionsRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            switch SearchSuggestionsRow.allCases[indexPath.row] {
            case .showSearchSuggestions, .showInPrivateBrowsing, .searchBrowsingHistory, .searchBookmarks, .searchOpenedTabs:
                return
            case .searchSuggestionProvider:
                navigationController?.pushViewController(SearchSuggestionProviderPreferencesViewController(), animated: true)
            }
        }
    }
    
    private func configureSwitches() {
        showSearchSuggestionsSwitch.addTarget(self, action: #selector(showSearchSuggestionsSwitchDidChange(_:)), for: .valueChanged)
        showInPrivateBrowsingSwitch.addTarget(self, action: #selector(showInPrivateBrowsingSwitchDidChange(_:)), for: .valueChanged)
        searchBrowsingHistorySwitch.addTarget(self, action: #selector(searchBrowsingHistorySwitchDidChange(_:)), for: .valueChanged)
        searchBookmarksSwitch.addTarget(self, action: #selector(searchBookmarksSwitchDidChange(_:)), for: .valueChanged)
        searchOpenedTabsSwitch.addTarget(self, action: #selector(searchOpenedTabsSwitchDidChange(_:)), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        showSearchSuggestionsSwitch.isOn = Prefs.SearchSettings.showSearchSuggestions
        showInPrivateBrowsingSwitch.isOn = Prefs.SearchSettings.showSearchSuggestionsInPrivateBrowsing
        searchBrowsingHistorySwitch.isOn = Prefs.SearchSettings.searchBrowsingHistory
        searchBookmarksSwitch.isOn = Prefs.SearchSettings.searchBookmarks
        searchOpenedTabsSwitch.isOn = Prefs.SearchSettings.searchOpenedTabs
    }
    
    @objc private func showSearchSuggestionsSwitchDidChange(_ sender: UISwitch) {
        Prefs.SearchSettings.showSearchSuggestions = sender.isOn
    }
    
    @objc private func showInPrivateBrowsingSwitchDidChange(_ sender: UISwitch) {
        Prefs.SearchSettings.showSearchSuggestionsInPrivateBrowsing = sender.isOn
    }
    
    @objc private func searchBrowsingHistorySwitchDidChange(_ sender: UISwitch) {
        Prefs.SearchSettings.searchBrowsingHistory = sender.isOn
    }
    
    @objc private func searchBookmarksSwitchDidChange(_ sender: UISwitch) {
        Prefs.SearchSettings.searchBookmarks = sender.isOn
    }
    
    @objc private func searchOpenedTabsSwitchDidChange(_ sender: UISwitch) {
        Prefs.SearchSettings.searchOpenedTabs = sender.isOn
    }
    
    private func switchCell(title: String, accessoryView: UISwitch) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        cell.accessoryView = accessoryView
        return cell
    }
}
