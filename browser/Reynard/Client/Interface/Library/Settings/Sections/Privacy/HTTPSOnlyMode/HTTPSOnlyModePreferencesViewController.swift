//
//  HTTPSOnlyModePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/7/26.
//

import UIKit

final class HTTPSOnlyModePreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let optionIndentationLevel = 1
    }
    
    private enum Row: CaseIterable {
        case enabled
        case allTabs
        case privateTabs
    }
    
    private let httpsOnlyModeSwitch = UISwitch()
    private var displayedRows: [Row] {
        return Prefs.HTTPSOnlyModePreferences.enabled ? Row.allCases : [.enabled]
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("HTTPS-Only Mode", tableName: "SettingsLocalizable", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        httpsOnlyModeSwitch.isOn = Prefs.HTTPSOnlyModePreferences.enabled
        httpsOnlyModeSwitch.addTarget(self, action: #selector(httpsOnlyModeSwitchDidChange), for: .valueChanged)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedRows.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        return SettingsSectionText(
            footerTitle: NSLocalizedString("Automatically attempts to connect to websites using HTTPS encryption protocol for increased security.", tableName: "SettingsLocalizable", comment: "")
        )
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch displayedRows[indexPath.row] {
        case .enabled:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("HTTPS-Only Mode", tableName: "SettingsLocalizable", comment: "")
            cell.accessoryView = httpsOnlyModeSwitch
            cell.selectionStyle = .none
            return cell
        case .allTabs:
            return scopeCell(
                title: NSLocalizedString("Enable in All Tabs", tableName: "SettingsLocalizable", comment: ""),
                scope: .allTabs
            )
        case .privateTabs:
            return scopeCell(
                title: NSLocalizedString("Enable Only in Private Tabs", tableName: "SettingsLocalizable", comment: ""),
                scope: .privateTabs
            )
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedRows.indices.contains(indexPath.row) else {
            return
        }
        
        switch displayedRows[indexPath.row] {
        case .enabled:
            return
        case .allTabs:
            selectScope(.allTabs)
        case .privateTabs:
            selectScope(.privateTabs)
        }
    }
    
    private func scopeCell(title: String, scope: HTTPSOnlyModeScope) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.indentationLevel = UX.optionIndentationLevel
        cell.accessoryType = Prefs.HTTPSOnlyModePreferences.scope == scope ? .checkmark : .none
        return cell
    }
    
    private func selectScope(_ scope: HTTPSOnlyModeScope) {
        guard Prefs.HTTPSOnlyModePreferences.scope != scope else {
            return
        }
        Prefs.HTTPSOnlyModePreferences.scope = scope
        HTTPSOnlyModePolicyController.applyHTTPSOnlyMode()
        tableView.reloadData()
    }
    
    @objc private func httpsOnlyModeSwitchDidChange(_ sender: UISwitch) {
        let optionIndexPaths = [
            IndexPath(row: 1, section: 0),
            IndexPath(row: 2, section: 0),
        ]
        Prefs.HTTPSOnlyModePreferences.enabled = sender.isOn
        HTTPSOnlyModePolicyController.applyHTTPSOnlyMode()
        tableView.performBatchUpdates {
            if sender.isOn {
                tableView.insertRows(at: optionIndexPaths, with: .automatic)
            } else {
                tableView.deleteRows(at: optionIndexPaths, with: .automatic)
            }
        }
    }
}
