//
//  CustomTrackingProtectionOptionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/7/26.
//

import UIKit

enum CustomTrackingProtectionOption {
    case cookies
    case trackingContent
    case suspectedFingerprinters
    
    var title: String {
        switch self {
        case .cookies:
            return NSLocalizedString("Cookies", tableName: "SettingsLocalizable", comment: "")
        case .trackingContent:
            return NSLocalizedString("Tracking Content", tableName: "SettingsLocalizable", comment: "")
        case .suspectedFingerprinters:
            return NSLocalizedString("Suspected Fingerprinters", tableName: "SettingsLocalizable", comment: "")
        }
    }
    
    var options: [(title: String, description: String?)] {
        switch self {
        case .cookies:
            return cookiePolicyOptions.map { ($0.title, $0.description) }
        case .trackingContent, .suspectedFingerprinters:
            return [
                (NSLocalizedString("In All Tabs", tableName: "SettingsLocalizable", comment: ""), nil),
                (NSLocalizedString("Only in Private Tabs", tableName: "SettingsLocalizable", comment: ""), nil),
                (NSLocalizedString("Do Not Block", comment: ""), nil),
            ]
        }
    }
    
    var selectedOptionIndex: Int {
        switch self {
        case .cookies:
            return cookiePolicyOptions.firstIndex {
                $0.value == Prefs.TrackingProtectionPreferences.customCookiePolicy
            } ?? 0
        case .trackingContent:
            return blockingScopes.firstIndex(of: Prefs.TrackingProtectionPreferences.customTrackingContentScope) ?? 0
        case .suspectedFingerprinters:
            return blockingScopes.firstIndex(of: Prefs.TrackingProtectionPreferences.customSuspectedFingerprinterScope) ?? 1
        }
    }
    
    var selectedOptionTitle: String {
        return options[selectedOptionIndex].title
    }
    
    func selectOption(at index: Int) {
        guard options.indices.contains(index) else {
            return
        }
        switch self {
        case .cookies:
            Prefs.TrackingProtectionPreferences.customCookiePolicy = cookiePolicyOptions[index].value
        case .trackingContent:
            Prefs.TrackingProtectionPreferences.customTrackingContentScope = blockingScopes[index]
        case .suspectedFingerprinters:
            Prefs.TrackingProtectionPreferences.customSuspectedFingerprinterScope = blockingScopes[index]
        }
    }
    
    private var blockingScopes: [CustomBlockingScope] {
        return [.all, .privateOnly, .none]
    }
    
    private var cookiePolicyOptions: [(value: CustomCookiePolicy, title: String, description: String?)] {
        return [
            (.isolateCrossSite, NSLocalizedString("Isolate Cross-Site Cookies", tableName: "SettingsLocalizable", comment: ""), nil),
            (.crossSiteAndSocialTrackers, NSLocalizedString("Cross-Site and Social Media Trackers", tableName: "SettingsLocalizable", comment: ""), nil),
            (.unvisitedWebsites, NSLocalizedString("Cookies from Unvisited Websites", tableName: "SettingsLocalizable", comment: ""), nil),
            (.thirdParty, NSLocalizedString("All Third-Party Cookies", tableName: "SettingsLocalizable", comment: ""), NSLocalizedString("May cause websites to break", tableName: "SettingsLocalizable", comment: "")),
            (.all, NSLocalizedString("All Cookies", tableName: "SettingsLocalizable", comment: ""), NSLocalizedString("Will cause websites to break", tableName: "SettingsLocalizable", comment: "")),
            (.none, NSLocalizedString("Do Not Block", comment: ""), nil),
        ]
    }
}

final class CustomTrackingProtectionOptionViewController: SettingsTableViewController {
    private let option: CustomTrackingProtectionOption
    private let selectionDidChange: () -> Void
    
    init(option: CustomTrackingProtectionOption, selectionDidChange: @escaping () -> Void) {
        self.option = option
        self.selectionDidChange = selectionDidChange
        super.init(style: .insetGrouped)
        title = option.title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? option.options.count : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 0, option.options.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        let displayedOption = option.options[indexPath.row]
        let cell = UITableViewCell(style: displayedOption.description == nil ? .default : .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = displayedOption.title
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = displayedOption.description
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = indexPath.row == option.selectedOptionIndex ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard indexPath.section == 0, option.options.indices.contains(indexPath.row) else {
            return
        }
        option.selectOption(at: indexPath.row)
        selectionDidChange()
        tableView.reloadData()
    }
}
