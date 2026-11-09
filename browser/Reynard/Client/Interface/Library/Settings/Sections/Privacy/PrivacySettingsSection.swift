//
//  PrivacySettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class PrivacySettingsSection: NSObject {
    enum Row: CaseIterable {
        case alwaysUsePrivateBrowsing
        case sitePermissions
        case httpsOnlyMode
        case dnsOverHTTPS
        case trackingProtection
    }
    
    private let alwaysUsePrivateBrowsingSwitch = UISwitch()
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    func configureSwitch() {
        alwaysUsePrivateBrowsingSwitch.addTarget(
            self,
            action: #selector(alwaysUsePrivateBrowsingDidChange(_:)),
            for: .valueChanged
        )
    }
    
    func refreshDisplayedState() {
        alwaysUsePrivateBrowsingSwitch.isOn = Prefs.PrivateBrowsingSettings.alwaysUsePrivateBrowsing
    }
    
    func cell(at index: Int) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .alwaysUsePrivateBrowsing:
            let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = NSLocalizedString("Always Use Private Browsing", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("New tabs open in Private Browsing by default, and Reynard starts in Private Browsing every time.", comment: "")
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.numberOfLines = 0
            cell.accessoryView = alwaysUsePrivateBrowsingSwitch
            return cell
        case .sitePermissions:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Website Permissions", comment: ""))
        case .httpsOnlyMode:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("HTTPS-Only Mode", tableName: "SettingsLocalizable", comment: ""))
        case .dnsOverHTTPS:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("DNS over HTTPS", tableName: "SettingsLocalizable", comment: ""))
        case .trackingProtection:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Tracking Protection", comment: ""))
        }
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index) else {
            return
        }
        
        switch Row.allCases[index] {
        case .alwaysUsePrivateBrowsing:
            return
        case .sitePermissions:
            let destination = SitePermissionsViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        case .httpsOnlyMode:
            let destination = HTTPSOnlyModePreferencesViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        case .dnsOverHTTPS:
            let destination = DNSOverHTTPSPreferencesViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        case .trackingProtection:
            let destination = TrackingProtectionPreferencesViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        }
    }
    
    @objc private func alwaysUsePrivateBrowsingDidChange(_ sender: UISwitch) {
        Prefs.PrivateBrowsingSettings.alwaysUsePrivateBrowsing = sender.isOn
    }
}
