//
//  SearchPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SearchPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case search
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private enum Row: CaseIterable {
        case searchEngine
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Search"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .search:
            return Row.allCases.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              Row.allCases.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[indexPath.row] {
        case .searchEngine:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Search Engine"
            cell.detailTextLabel?.text = Prefs.SearchSettings.searchEngine.displayName
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section),
              Row.allCases.indices.contains(indexPath.row) else {
            return
        }
        
        switch Row.allCases[indexPath.row] {
        case .searchEngine:
            navigationController?.pushViewController(SearchEnginePreferencesViewController(), animated: true)
        }
    }
    
}
