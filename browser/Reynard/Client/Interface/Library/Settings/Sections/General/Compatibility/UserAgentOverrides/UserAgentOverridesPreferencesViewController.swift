//
//  UserAgentOverridesPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class UserAgentOverridesPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case overrides
        
        var text: SettingsSectionText {
            return SettingsSectionText(
                footerTitle: "Navigations to these websites will use the browser's compatibility user agent. Depending on your Request Desktop Website setting, these websites may identify your device as either an Android device or a desktop Linux device."
            )
        }
    }
    
    private enum Row {
        case domain(String)
        case addWebsite
    }
    
    private var overrideDomains: [String] = []
    
    private var displayedRows: [Row] {
        return overrideDomains.map(Row.domain) + [.addWebsite]
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "User Agent Overrides"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideDomains = Prefs.CompatibilitySettings.androidUserAgentDomains
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        return displayedRows.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              displayedRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch displayedRows[indexPath.row] {
        case .domain(let domain):
            cell.textLabel?.text = domain
            cell.selectionStyle = .default
        case .addWebsite:
            cell.textLabel?.text = "Add Website..."
            cell.textLabel?.textColor = tableView.tintColor
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard displayedRows.indices.contains(indexPath.row) else {
            return false
        }
        if case .domain = displayedRows[indexPath.row] {
            return true
        }
        return false
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              displayedRows.indices.contains(indexPath.row),
              case .domain = displayedRows[indexPath.row] else { return }
        overrideDomains.remove(at: indexPath.row)
        Prefs.CompatibilitySettings.androidUserAgentDomains = overrideDomains
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard displayedRows.indices.contains(indexPath.row) else {
            return
        }
        if case .addWebsite = displayedRows[indexPath.row] {
            promptForOverrideDomain()
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
    
    private func promptForOverrideDomain() {
        let alert = UIAlertController(title: "Add Website", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. youtube.com"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.keyboardType = .URL
            field.clearButtonMode = .whileEditing
        }
        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text else { return }
            self?.addOverrideDomain(text)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(addAction)
        present(alert, animated: true)
    }
    
    private func addOverrideDomain(_ domain: String) {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !overrideDomains.contains(normalized) else { return }
        overrideDomains.append(normalized)
        overrideDomains.sort()
        Prefs.CompatibilitySettings.androidUserAgentDomains = overrideDomains
        tableView.reloadData()
    }
}
