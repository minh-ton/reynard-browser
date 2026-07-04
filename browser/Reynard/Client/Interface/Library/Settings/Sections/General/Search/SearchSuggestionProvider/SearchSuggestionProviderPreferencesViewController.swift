//
//  SearchSuggestionProviderPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

import UIKit

final class SearchSuggestionProviderPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case providers
        
        var text: SettingsSectionText {
            switch self {
            case .providers:
                return SettingsSectionText(headerTitle: NSLocalizedString("Search Suggestion Provider", comment: ""))
            }
        }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Search Suggestion Provider", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        case .providers:
            return SearchCompletion.Provider.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              Section.allCases[indexPath.section] == .providers,
              SearchCompletion.Provider.allCases.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let provider = SearchCompletion.Provider.allCases[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = provider.name
        cell.accessoryType = Prefs.SearchSettings.searchSuggestionProvider == provider ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section),
              Section.allCases[indexPath.section] == .providers,
              SearchCompletion.Provider.allCases.indices.contains(indexPath.row) else {
            return
        }
        
        Prefs.SearchSettings.searchSuggestionProvider = SearchCompletion.Provider.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
}
