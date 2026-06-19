//
//  SitePermissionsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SitePermissionsViewController: SettingsTableViewController {
    private enum Section {
        case availability
        case permissions
        case websiteActions
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private enum AvailabilityRow: CaseIterable {
        case disabledPermissions
        case openSettings
    }
    
    private enum WebsiteActionRow: CaseIterable {
        case resetPermissions
    }
    
    private enum Row {
        case autoplay
        case camera
        case microphone
        case location
        case persistentStorage
        case crossOriginStorageAccess
        case localDeviceAccess
        case localNetworkAccess
        
        var title: String {
            switch self {
            case .autoplay:
                return "Autoplay"
            case .camera:
                return "Camera"
            case .microphone:
                return "Microphone"
            case .location:
                return "Location"
            case .persistentStorage:
                return "Persistent Storage"
            case .crossOriginStorageAccess:
                return "Cross-site Cookies"
            case .localDeviceAccess:
                return "Device Apps and Services"
            case .localNetworkAccess:
                return "Local Network Devices"
            }
        }
        
        var permission: SitePermission {
            switch self {
            case .autoplay:
                return .autoplay
            case .camera:
                return .camera
            case .microphone:
                return .microphone
            case .location:
                return .location
            case .persistentStorage:
                return .persistentStorage
            case .crossOriginStorageAccess:
                return .crossOriginStorageAccess
            case .localDeviceAccess:
                return .localDeviceAccess
            case .localNetworkAccess:
                return .localNetworkAccess
            }
        }
    }
    
    private let permissionOptions: [Row] = [
        .autoplay,
        .camera,
        .microphone,
        .location,
        .persistentStorage,
        .crossOriginStorageAccess,
        .localDeviceAccess,
        .localNetworkAccess,
    ]
    private var hasResetAllSitePermissions = false
    
    private var displayedSections: [Section] {
        var sections: [Section] = []
        
        if !SiteSettingsUtils.disabledPermissionNames().isEmpty {
            sections.append(.availability)
        }
        
        sections.append(.permissions)
        sections.append(.websiteActions)
        return sections
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Site Permissions"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        
        switch displayedSections[section] {
        case .availability:
            return AvailabilityRow.allCases.count
        case .permissions:
            return permissionOptions.count
        case .websiteActions:
            return WebsiteActionRow.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        let section = displayedSections[indexPath.section]
        
        switch section {
        case .availability:
            guard AvailabilityRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            switch AvailabilityRow.allCases[indexPath.row] {
            case .disabledPermissions:
                return disabledPermissionMessageCell()
            case .openSettings:
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Open Settings"
                cell.textLabel?.textColor = view.tintColor
                cell.accessoryType = .none
                return cell
            }
        case .permissions:
            guard let row = permissionOption(at: indexPath) else {
                return UITableViewCell()
            }
            
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = SiteSettingsUtils.actionTitle(
                for: SiteSettingsUtils.defaultAction(for: row.permission),
                permission: row.permission
            )
            if SiteSettingsUtils.isSystemDisabled(row.permission) {
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.textColor = .tertiaryLabel
                cell.accessoryType = .none
                cell.selectionStyle = .none
                cell.isUserInteractionEnabled = false
            } else {
                cell.textLabel?.textColor = .label
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                cell.isUserInteractionEnabled = true
            }
            return cell
        case .websiteActions:
            guard WebsiteActionRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            switch WebsiteActionRow.allCases[indexPath.row] {
            case .resetPermissions:
                cell.textLabel?.text = "Reset Permissions for all Sites"
                cell.textLabel?.textColor = .systemRed
                if hasResetAllSitePermissions {
                    cell.detailTextLabel?.text = "Successfully reset permissions for all sites."
                } else {
                    cell.detailTextLabel?.text = nil
                }
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryType = .none
                return cell
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }
        
        let section = displayedSections[indexPath.section]
        
        switch section {
        case .availability:
            guard AvailabilityRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            if AvailabilityRow.allCases[indexPath.row] == .openSettings {
                SiteSettingsUtils.openAppSettings()
            }
        case .permissions:
            guard let row = permissionOption(at: indexPath) else {
                return
            }
            guard !SiteSettingsUtils.isSystemDisabled(row.permission) else {
                return
            }
            
            navigationController?.pushViewController(
                SitePermissionDetailsViewController(permission: row.permission, title: row.title),
                animated: true
            )
        case .websiteActions:
            guard WebsiteActionRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            switch WebsiteActionRow.allCases[indexPath.row] {
            case .resetPermissions:
                resetSitePermissions()
            }
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    private func disabledPermissionMessageCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = SiteSettingsUtils.disabledPermissionMessage()
        cell.textLabel?.textColor = .secondaryLabel
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        return cell
    }
    
    private func permissionOption(at indexPath: IndexPath) -> Row? {
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .permissions else {
            return nil
        }
        
        return permissionOptions[safe: indexPath.row]
    }
    
    private func resetSitePermissions() {
        let actions: [SitePermissionAction] = [
            .allowed,
            .askToAllow,
            .blocked,
        ]
        
        for row in permissionOptions {
            for action in actions {
                let entries = SitePermissionStore.shared.storedHosts(for: row.permission, action: action)
                for entry in entries {
                    SitePermissionStore.shared.removePersistedAction(for: row.permission, host: entry.host)
                    SiteSettingsUtils.clearGeckoPermission(for: row.permission, host: entry.host)
                }
            }
        }
        
        hasResetAllSitePermissions = true
        tableView.reloadData()
    }
}
