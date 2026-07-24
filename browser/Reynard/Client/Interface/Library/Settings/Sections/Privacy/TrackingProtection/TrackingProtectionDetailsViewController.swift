//
//  TrackingProtectionDetailsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/7/26.
//

import UIKit

final class TrackingProtectionDetailsViewController: SettingsTableViewController {
    private enum Category: CaseIterable {
        case socialMediaTrackers
        case crossSiteCookies
        case cryptominers
        case knownFingerprinters
        case trackingContent
        case redirectTrackers
        case suspectedFingerprinters
        
        var title: String {
            switch self {
            case .socialMediaTrackers:
                return NSLocalizedString("Social Media Trackers", tableName: "SettingsLocalizable", comment: "")
            case .crossSiteCookies:
                return NSLocalizedString("Cross-Site Cookies", tableName: "SettingsLocalizable", comment: "")
            case .cryptominers:
                return NSLocalizedString("Cryptominers", tableName: "SettingsLocalizable", comment: "")
            case .knownFingerprinters:
                return NSLocalizedString("Known Fingerprinters", tableName: "SettingsLocalizable", comment: "")
            case .trackingContent:
                return NSLocalizedString("Tracking Content", tableName: "SettingsLocalizable", comment: "")
            case .redirectTrackers:
                return NSLocalizedString("Redirect Trackers", tableName: "SettingsLocalizable", comment: "")
            case .suspectedFingerprinters:
                return NSLocalizedString("Suspected Fingerprinters", tableName: "SettingsLocalizable", comment: "")
            }
        }
        
        var description: String {
            switch self {
            case .socialMediaTrackers:
                return NSLocalizedString("Limits the ability of social networks to track your browsing activity around the web.", tableName: "SettingsLocalizable", comment: "")
            case .crossSiteCookies:
                return NSLocalizedString("Total Cookie Protection isolates cookies to the website you’re on so trackers like ad networks can’t use them to follow you across websites.", tableName: "SettingsLocalizable", comment: "")
            case .cryptominers:
                return NSLocalizedString("Prevents malicious scripts gaining access to your device to mine digital currency.", tableName: "SettingsLocalizable", comment: "")
            case .knownFingerprinters:
                return NSLocalizedString("Stops uniquely identifiable data from being collected about your device that can be used for tracking purposes.", tableName: "SettingsLocalizable", comment: "")
            case .trackingContent:
                return NSLocalizedString("Stops outside ads, videos, and other content from loading that contains tracking code. May affect some website functionality.", tableName: "SettingsLocalizable", comment: "")
            case .redirectTrackers:
                return NSLocalizedString("Clears cookies set by redirects to known tracking websites.", tableName: "SettingsLocalizable", comment: "")
            case .suspectedFingerprinters:
                return NSLocalizedString("Enables fingerprinting protection to stop suspected fingerprinters.", tableName: "SettingsLocalizable", comment: "")
            }
        }
        
        var isEnabledForCustomProtection: Bool {
            switch self {
            case .socialMediaTrackers:
                return true
            case .crossSiteCookies:
                return Prefs.TrackingProtectionPreferences.customCookiePolicy != .none
            case .cryptominers:
                return Prefs.TrackingProtectionPreferences.customBlocksCryptominers
            case .knownFingerprinters:
                return Prefs.TrackingProtectionPreferences.customBlocksKnownFingerprinters
            case .trackingContent:
                return Prefs.TrackingProtectionPreferences.customTrackingContentScope != .none
            case .redirectTrackers:
                return Prefs.TrackingProtectionPreferences.customBlocksRedirectTrackers
            case .suspectedFingerprinters:
                return Prefs.TrackingProtectionPreferences.customSuspectedFingerprinterScope != .none
            }
        }
    }
    
    private let categories: [Category]
    private let protectionTitle: String
    
    init(protectionLevel: TrackingProtectionLevel) {
        switch protectionLevel {
        case .standard:
            categories = Category.allCases.filter { $0 != .trackingContent }
            protectionTitle = NSLocalizedString("Standard", tableName: "SettingsLocalizable", comment: "")
        case .strict:
            categories = Category.allCases
            protectionTitle = NSLocalizedString("Strict", tableName: "SettingsLocalizable", comment: "")
        case .custom:
            categories = Category.allCases.filter(\.isEnabledForCustomProtection)
            protectionTitle = NSLocalizedString("Custom", tableName: "SettingsLocalizable", comment: "")
        case .off:
            categories = []
            protectionTitle = ""
        }
        super.init(style: .insetGrouped)
        title = protectionTitle
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissDetails)
        )
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? categories.count : 0
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard section == 0 else {
            return SettingsSectionText()
        }
        let title = String(
            format: NSLocalizedString("What %@ Protection Blocks", comment: "Protection mode name placeholder"),
            protectionTitle
        )
        return SettingsSectionText(headerTitle: title)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 0, categories.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        let category = categories[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = category.title
        cell.detailTextLabel?.text = category.description
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        return cell
    }
    
    @objc private func dismissDetails() {
        dismiss(animated: true)
    }
}
