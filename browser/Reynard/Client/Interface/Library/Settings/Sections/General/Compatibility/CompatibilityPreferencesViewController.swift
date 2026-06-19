//
//  CompatibilityPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class CompatibilityPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case userAgent
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private enum Row: CaseIterable {
        case useAndroidUserAgent
        case userAgentOverrides
    }
    
    private let androidUserAgentSwitch = UISwitch()
    
    private var displayedRows: [Row] {
        return Prefs.CompatibilitySettings.useAndroidUserAgent ? [.useAndroidUserAgent] : Row.allCases
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
        configureSwitch()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
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
        case .userAgent:
            return displayedRows.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              displayedRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = displayedRows[indexPath.row]
        switch row {
        case .useAndroidUserAgent:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Use Android User Agent"
            cell.selectionStyle = .none
            cell.accessoryView = androidUserAgentSwitch
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
        guard Section.allCases.indices.contains(indexPath.section),
              displayedRows.indices.contains(indexPath.row) else {
            return
        }
        if displayedRows[indexPath.row] == .userAgentOverrides {
            navigationController?.pushViewController(UserAgentOverridesPreferencesViewController(), animated: true)
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        let headerTitle = Section.allCases[section].text.headerTitle
        if Prefs.CompatibilitySettings.useAndroidUserAgent {
            let footerTitle = Prefs.BrowsingSettings.requestDesktopWebsite
            ? "The browser will use a desktop Firefox user agent for navigating the web."
            : "To maximize compatibility, the browser will use the Firefox for Android user agent for navigating the web. As a result, websites may identify your device as an Android device."
            return SettingsSectionText(headerTitle: headerTitle, footerTitle: footerTitle)
        }
        
        return SettingsSectionText(
            headerTitle: headerTitle,
            footerTitle: "If you encounter issues such as sign-in failures, human verification challenges, or other incorrect site behavior, adding the site's URL to this user agent override list may help resolve the problem."
        )
    }
    
    private func refreshDisplayedState() {
        androidUserAgentSwitch.isOn = Prefs.CompatibilitySettings.useAndroidUserAgent
    }
    
    private func configureSwitch() {
        androidUserAgentSwitch.addTarget(self, action: #selector(applyAndroidUserAgentPreference), for: .valueChanged)
    }
    
    @objc private func applyAndroidUserAgentPreference() {
        let nowOn = androidUserAgentSwitch.isOn
        Prefs.CompatibilitySettings.useAndroidUserAgent = nowOn
        
        guard let overrideRow = Row.allCases.firstIndex(of: .userAgentOverrides),
              let section = Section.allCases.firstIndex(of: .userAgent) else {
            return
        }
        let overrideRowIndexPath = IndexPath(row: overrideRow, section: section)
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            if nowOn {
                tableView.deleteRows(at: [overrideRowIndexPath], with: .none)
            } else {
                tableView.insertRows(at: [overrideRowIndexPath], with: .none)
            }
            tableView.endUpdates()
        }
        
        if let footer = tableView.footerView(forSection: section) {
            footer.textLabel?.text = sectionText(for: section).footerTitle
            footer.sizeToFit()
        }
    }
}
