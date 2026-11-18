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
    
    private enum Row {
        case useAndroidUserAgent
        case advancedOptions
        case userAgentOverrides
    }
    
    private let androidUserAgentSwitch = UISwitch()
    
    private var displayedRows: [Row] {
        return Prefs.CompatibilitySettings.useAndroidUserAgent
        ? [.useAndroidUserAgent, .advancedOptions]
        : [.useAndroidUserAgent, .userAgentOverrides]
    }
    
    private var compatibilityUserAgentName: String {
        if !Prefs.CompatibilitySettings.customUserAgent.isEmpty
            || !Prefs.CompatibilitySettings.customPlatform.isEmpty
            || !Prefs.CompatibilitySettings.customAppVersion.isEmpty
            || !Prefs.CompatibilitySettings.customOscpu.isEmpty
            || !Prefs.CompatibilitySettings.customBuildID.isEmpty {
            return NSLocalizedString("Custom", comment: "")
        }
        return Prefs.BrowsingSettings.effectiveRequestDesktopWebsite ? NSLocalizedString("Desktop Firefox", comment: "") : NSLocalizedString("Firefox for Android", comment: "")
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Compatibility", comment: "")
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
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Use Compatibility User Agent", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = androidUserAgentSwitch
            return cell
        case .advancedOptions:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Advanced Options", comment: "")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .userAgentOverrides:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("User Agent Overrides", comment: "")
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
        switch displayedRows[indexPath.row] {
        case .advancedOptions:
            navigationController?.pushViewController(AdvancedOptionsPreferencesViewController(), animated: true)
        case .userAgentOverrides:
            navigationController?.pushViewController(UserAgentOverridesPreferencesViewController(), animated: true)
        case .useAndroidUserAgent:
            break
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        let headerTitle = Section.allCases[section].text.headerTitle
        if Prefs.CompatibilitySettings.useAndroidUserAgent {
            let footerTitle = String(format: NSLocalizedString("Use the %@ user agent for all websites to improve compatibility.", comment: "User agent name placeholder"), compatibilityUserAgentName)
            return SettingsSectionText(headerTitle: headerTitle, footerTitle: footerTitle)
        }
        
        return SettingsSectionText(
            headerTitle: headerTitle,
            footerTitle: String(format: NSLocalizedString("Add websites with sign-in failures, human verification challenges, or other issues to use the %@ user agent.", comment: "User agent name placeholder"), compatibilityUserAgentName)
        )
    }
    
    private func refreshDisplayedState() {
        androidUserAgentSwitch.isOn = Prefs.CompatibilitySettings.useAndroidUserAgent
    }
    
    private func configureSwitch() {
        androidUserAgentSwitch.addTarget(self, action: #selector(applyAndroidUserAgentPreference), for: .valueChanged)
    }
    
    @objc private func applyAndroidUserAgentPreference() {
        Prefs.CompatibilitySettings.useAndroidUserAgent = androidUserAgentSwitch.isOn
        tableView.reloadData()
        
        guard let section = Section.allCases.firstIndex(of: .userAgent) else {
            return
        }
        if let footer = tableView.footerView(forSection: section) {
            footer.textLabel?.text = sectionText(for: section).footerTitle
            footer.sizeToFit()
        }
    }
}
