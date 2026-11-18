//
//  RequestDesktopWebsitePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 24/7/26.
//

import UIKit

final class RequestDesktopWebsitePreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case `default`
        case websites
        case reset
        
        var text: SettingsSectionText {
            switch self {
            case .default:
                return SettingsSectionText(
                    headerTitle: NSLocalizedString("Default Setting", comment: ""),
                    footerTitle: NSLocalizedString("When Match Window Size is on, desktop websites are requested while the window is large, such as on iPad or an unfolded iPhone, and mobile websites while it is compact.", comment: "")
                )
            case .websites:
                return SettingsSectionText(headerTitle: NSLocalizedString("Websites With Custom Settings", comment: ""))
            case .reset:
                return SettingsSectionText()
            }
        }
    }
    
    private let defaultSwitch = UISwitch()
    private let matchesWindowSwitch = UISwitch()
    private var websiteSettings: [SiteSettingsRecord] = []
    
    private var displayedSections: [Section] {
        return Section.allCases.filter { section in
            switch section {
            case .default:
                return true
            case .websites:
                return !websiteSettings.isEmpty
            case .reset:
                return Prefs.BrowsingSettings.requestDesktopWebsite != (UIDevice.current.userInterfaceIdiom == .pad)
                || !Prefs.BrowsingSettings.requestDesktopWebsiteMatchesWindow
                || !websiteSettings.isEmpty
            }
        }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Request Desktop Website", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        defaultSwitch.addTarget(self, action: #selector(defaultSwitchDidChange(_:)), for: .valueChanged)
        matchesWindowSwitch.addTarget(self, action: #selector(matchesWindowSwitchDidChange(_:)), for: .valueChanged)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSettings()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        switch displayedSections[section] {
        case .default:
            return 2
        case .websites:
            return websiteSettings.count
        case .reset:
            return 1
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .default:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                cell.textLabel?.text = NSLocalizedString("Match Window Size", comment: "")
                matchesWindowSwitch.isOn = Prefs.BrowsingSettings.requestDesktopWebsiteMatchesWindow
                cell.accessoryView = matchesWindowSwitch
                return cell
            }
            let matchesWindow = Prefs.BrowsingSettings.requestDesktopWebsiteMatchesWindow
            cell.textLabel?.text = NSLocalizedString("Request Desktop Website", comment: "")
            cell.textLabel?.isEnabled = !matchesWindow
            defaultSwitch.isOn = Prefs.BrowsingSettings.effectiveRequestDesktopWebsite
            defaultSwitch.isEnabled = !matchesWindow
            cell.accessoryView = defaultSwitch
            return cell
        case .websites:
            guard websiteSettings.indices.contains(indexPath.row),
                  let mode = websiteSettings[indexPath.row].websiteMode else {
                return UITableViewCell()
            }
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = websiteSettings[indexPath.row].host
            let modeSwitch = UISwitch()
            modeSwitch.isOn = mode == .desktop
            modeSwitch.tag = indexPath.row
            modeSwitch.addTarget(self, action: #selector(websiteSwitchDidChange(_:)), for: .valueChanged)
            cell.accessoryView = modeSwitch
            cell.selectionStyle = .none
            return cell
        case .reset:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Reset Desktop Website Settings", comment: "")
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .reset else {
            return
        }
        
        Prefs.BrowsingSettings.requestDesktopWebsite = UIDevice.current.userInterfaceIdiom == .pad
        Prefs.BrowsingSettings.requestDesktopWebsiteMatchesWindow = true
        clearAllWebsiteSettings()
        reloadSettings()
    }
    
    @objc private func matchesWindowSwitchDidChange(_ sender: UISwitch) {
        if !sender.isOn {
            // Keep the mode currently in effect as the fixed default.
            Prefs.BrowsingSettings.requestDesktopWebsite = Prefs.BrowsingSettings.effectiveRequestDesktopWebsite
        }
        Prefs.BrowsingSettings.requestDesktopWebsiteMatchesWindow = sender.isOn
        reloadSettings()
    }
    
    @objc private func defaultSwitchDidChange(_ sender: UISwitch) {
        Prefs.BrowsingSettings.requestDesktopWebsite = sender.isOn
        for setting in websiteSettings where (setting.websiteMode == .desktop) == sender.isOn {
            _ = SiteSettingsStore.shared.clearWebsiteMode(for: setting.host)
        }
        reloadSettings()
    }
    
    @objc private func websiteSwitchDidChange(_ sender: UISwitch) {
        guard websiteSettings.indices.contains(sender.tag) else {
            return
        }
        
        let host = websiteSettings[sender.tag].host
        if sender.isOn == Prefs.BrowsingSettings.requestDesktopWebsite {
            _ = SiteSettingsStore.shared.clearWebsiteMode(for: host)
        } else {
            _ = SiteSettingsStore.shared.setWebsiteMode(sender.isOn ? .desktop : .mobile, for: host)
        }
        reloadSettings()
    }
    
    private func clearAllWebsiteSettings() {
        for setting in websiteSettings {
            _ = SiteSettingsStore.shared.clearWebsiteMode(for: setting.host)
        }
    }
    
    private func reloadSettings() {
        websiteSettings = SiteSettingsStore.shared.settingsWithWebsiteMode()
        tableView.reloadData()
    }
}
