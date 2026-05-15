//
//  Compatibility.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit

final class CompatibilityPreferencesViewController: SettingsTableViewController {
    private enum Row: CaseIterable {
        case useAndroidUserAgent
        case userAgentOverrides
    }
    
    private let androidUASwitch = UISwitch()
    
    private var rows: [Row] {
        Prefs.CompatibilitySettings.useAndroidUserAgent ? [.useAndroidUserAgent] : Row.allCases
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Compatibility"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        androidUASwitch.addTarget(self, action: #selector(androidUASwitchChanged), for: .valueChanged)
        refreshControls()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshControls()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard rows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = rows[indexPath.row]
        switch row {
        case .useAndroidUserAgent:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Use Android User Agent"
            cell.selectionStyle = .none
            cell.accessoryView = androidUASwitch
            return cell
        case .userAgentOverrides:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "User Agent Overrides"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard rows.indices.contains(indexPath.row) else {
            return
        }
        if rows[indexPath.row] == .userAgentOverrides {
            navigationController?.pushViewController(UserAgentOverridesPreferencesViewController(), animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if Prefs.CompatibilitySettings.useAndroidUserAgent {
            return Prefs.BrowsingSettings.requestDesktopWebsite
            ? "The browser will use a desktop Firefox user agent for navigating the web."
            : "To maximize compatibility, the browser will use the Firefox for Android user agent for navigating the web. As a result, websites may identify your device as an Android device."
        }
        
        return "If you encounter issues such as sign-in failures, human verification challenges, or other incorrect site behavior, adding the site's URL to this user agent override list may help resolve the problem."
    }
    
    private func refreshControls() {
        androidUASwitch.isOn = Prefs.CompatibilitySettings.useAndroidUserAgent
    }
    
    @objc private func androidUASwitchChanged() {
        let nowOn = androidUASwitch.isOn
        Prefs.CompatibilitySettings.useAndroidUserAgent = nowOn
        
        let overrideRowIndexPath = IndexPath(row: 1, section: 0)
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            if nowOn {
                tableView.deleteRows(at: [overrideRowIndexPath], with: .none)
            } else {
                tableView.insertRows(at: [overrideRowIndexPath], with: .none)
            }
            tableView.endUpdates()
        }
        
        if let footer = tableView.footerView(forSection: 0) {
            footer.textLabel?.text = tableView(tableView, titleForFooterInSection: 0)
            footer.sizeToFit()
        }
    }
}

final class UserAgentOverridesPreferencesViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case userList
    }
    
    private var domains: [String] = []
    
    init() {
        super.init(style: .insetGrouped)
        title = "User Agent Overrides"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        domains = Prefs.CompatibilitySettings.androidUserAgentDomains
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .userList: return domains.count + 1
        case nil: return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .userList:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            if indexPath.row < domains.count {
                cell.textLabel?.text = domains[indexPath.row]
                cell.selectionStyle = .default
            } else {
                cell.textLabel?.text = "Add Website..."
                cell.textLabel?.textColor = tableView.tintColor
            }
            return cell
        case nil:
            return UITableViewCell()
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.userList.rawValue && indexPath.row < domains.count
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              indexPath.section == Section.userList.rawValue,
              indexPath.row < domains.count else { return }
        domains.remove(at: indexPath.row)
        Prefs.CompatibilitySettings.androidUserAgentDomains = domains
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .userList, indexPath.row == domains.count {
            showAddDomainAlert()
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .userList else {
            return nil
        }
        
        return "Navigations to these websites will use the browser's compatibility user agent. Depending on your Request Desktop Website setting, these websites may identify your device as either an Android device or a desktop Linux device."
    }
    
    private func showAddDomainAlert() {
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
            self?.insertDomain(text)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(addAction)
        present(alert, animated: true)
    }
    
    private func insertDomain(_ domain: String) {
        let normalised = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty, !domains.contains(normalised) else { return }
        domains.append(normalised)
        domains.sort()
        Prefs.CompatibilitySettings.androidUserAgentDomains = domains
        tableView.reloadData()
    }
}
