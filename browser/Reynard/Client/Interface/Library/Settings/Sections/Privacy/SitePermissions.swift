//
//  SitePermissions.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import GeckoView
import UIKit

final class SitePermissionsViewController: SettingsTableViewController {
    private enum Section {
        case availability
        case permissions
        case websiteActions
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
    
    private let permissionRows: [Row] = [
        .autoplay,
        .camera,
        .microphone,
        .location,
        .persistentStorage,
        .crossOriginStorageAccess,
        .localDeviceAccess,
        .localNetworkAccess,
    ]
    private var didResetAllSitePermissions = false
    
    private var visibleSections: [Section] {
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else {
            return 0
        }
        
        switch visibleSections[section] {
        case .availability:
            return 2
        case .permissions:
            return permissionRows.count
        case .websiteActions:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        let section = visibleSections[indexPath.section]
        
        switch section {
        case .availability:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = SiteSettingsUtils.disabledPermissionMessage()
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.numberOfLines = 0
                cell.selectionStyle = .none
                return cell
            }
            
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Open Settings"
            cell.textLabel?.textColor = view.tintColor
            cell.accessoryType = .none
            return cell
        case .permissions:
            guard let row = row(at: indexPath) else {
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
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "Reset Permissions for all Sites"
            cell.textLabel?.textColor = .systemRed
            if didResetAllSitePermissions {
                cell.detailTextLabel?.text = "Successfully reset permissions for all sites."
            } else {
                cell.detailTextLabel?.text = nil
            }
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .none
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard visibleSections.indices.contains(indexPath.section) else {
            return
        }
        
        let section = visibleSections[indexPath.section]
        
        switch section {
        case .availability:
            if indexPath.row == 1 {
                SiteSettingsUtils.openAppSettings()
            }
        case .permissions:
            guard let row = row(at: indexPath) else {
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
            resetAllSitePermissions()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    private func row(at indexPath: IndexPath) -> Row? {
        guard visibleSections.indices.contains(indexPath.section),
              visibleSections[indexPath.section] == .permissions else {
            return nil
        }
        
        return permissionRows[safe: indexPath.row]
    }
    
    private func resetAllSitePermissions() {
        let actions: [SitePermissionAction] = [
            .allowed,
            .askToAllow,
            .blocked,
        ]
        
        for row in permissionRows {
            for action in actions {
                let entries = SitePermissionStore.shared.hosts(for: row.permission, action: action)
                for entry in entries {
                    SitePermissionStore.shared.removePersistedActionAndWait(for: row.permission, host: entry.host)
                    SiteSettingsUtils.clearGeckoPermission(for: row.permission, host: entry.host)
                }
            }
        }
        
        didResetAllSitePermissions = true
        tableView.reloadData()
    }
}

private final class SitePermissionDetailsViewController: SettingsTableViewController {
    private struct ActionOption {
        let title: String
        let action: SitePermissionAction
    }
    
    private struct SiteEntry {
        let host: String
        let updatedAt: Date
    }
    
    private enum Section {
        case defaultBehavior
        case allowedSites
        case deniedSites
        case customActionSites
    }
    
    private let permission: SitePermission
    private var allowedSites: [SiteEntry] = []
    private var deniedSites: [SiteEntry] = []
    private var customActionSites: [(host: String, action: SitePermissionAction)] = []
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(permission: SitePermission, title: String) {
        self.permission = permission
        super.init(style: .insetGrouped)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadSiteLists()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else {
            return 0
        }
        
        switch visibleSections[section] {
        case .defaultBehavior:
            return actionOptions.count
        case .allowedSites:
            if allowedSites.isEmpty {
                return 1
            }
            return allowedSites.count
        case .deniedSites:
            if deniedSites.isEmpty {
                return 1
            }
            return deniedSites.count
        case .customActionSites:
            if customActionSites.isEmpty {
                return 1
            }
            return customActionSites.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else {
            return nil
        }
        
        switch visibleSections[section] {
        case .defaultBehavior:
            return "Default Behavior"
        case .allowedSites:
            return "Allowed Sites"
        case .deniedSites:
            return "Denied Sites"
        case .customActionSites:
            return "Changed Sites"
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch visibleSections[indexPath.section] {
        case .defaultBehavior:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            guard actionOptions.indices.contains(indexPath.row) else {
                return cell
            }
            let option = actionOptions[indexPath.row]
            cell.textLabel?.text = option.title
            cell.accessoryType = option.action == SiteSettingsUtils.defaultAction(for: permission) ? .checkmark : .none
            return cell
        case .allowedSites:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if allowedSites.isEmpty {
                cell.textLabel?.text = "No Sites Added"
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
                return cell
            }
            guard allowedSites.indices.contains(indexPath.row) else {
                return cell
            }
            let site = allowedSites[indexPath.row]
            cell.textLabel?.text = site.host
            cell.detailTextLabel?.text = siteSubtitle(for: .allowed, at: site.updatedAt)
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .default
            return cell
        case .deniedSites:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if deniedSites.isEmpty {
                cell.textLabel?.text = "No Sites Added"
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
                return cell
            }
            guard deniedSites.indices.contains(indexPath.row) else {
                return cell
            }
            let site = deniedSites[indexPath.row]
            cell.textLabel?.text = site.host
            cell.detailTextLabel?.text = siteSubtitle(for: .blocked, at: site.updatedAt)
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .default
            return cell
        case .customActionSites:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if customActionSites.isEmpty {
                cell.textLabel?.text = "No Sites Added"
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
                return cell
            }
            guard customActionSites.indices.contains(indexPath.row) else {
                return cell
            }
            let site = customActionSites[indexPath.row]
            cell.textLabel?.text = site.host
            cell.detailTextLabel?.text = SiteSettingsUtils.actionTitle(
                for: site.action,
                permission: permission
            )
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .default
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard visibleSections.indices.contains(indexPath.section),
              visibleSections[indexPath.section] == .defaultBehavior,
              actionOptions.indices.contains(indexPath.row) else {
            return
        }
        
        SiteSettingsUtils.setDefaultAction(actionOptions[indexPath.row].action, for: permission)
        reloadSiteLists()
        tableView.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSiteLists()
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard visibleSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch visibleSections[indexPath.section] {
        case .allowedSites:
            guard !allowedSites.isEmpty else {
                return nil
            }
            guard allowedSites.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionConfiguration(
                for: allowedSites[indexPath.row].host
            )
        case .deniedSites:
            guard !deniedSites.isEmpty else {
                return nil
            }
            guard deniedSites.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionConfiguration(
                for: deniedSites[indexPath.row].host
            )
        case .defaultBehavior:
            return nil
        case .customActionSites:
            guard !customActionSites.isEmpty else {
                return nil
            }
            guard customActionSites.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionConfiguration(
                for: customActionSites[indexPath.row].host
            )
        }
    }
    
    private var visibleSections: [Section] {
        if permission == .autoplay {
            return [
                .defaultBehavior,
                .customActionSites,
            ]
        }
        
        return [
            .defaultBehavior,
            .allowedSites,
            .deniedSites,
        ]
    }
    
    private var actionOptions: [ActionOption] {
        switch permission {
        case .autoplay:
            return actionOptions(for: [.allowed, .askToAllow, .blocked])
        default:
            return actionOptions(for: [.askToAllow, .allowed, .blocked])
        }
    }

    private func actionOptions(for actions: [SitePermissionAction]) -> [ActionOption] {
        actions.map {
            ActionOption(
                title: SiteSettingsUtils.actionTitle(for: $0, permission: permission),
                action: $0
            )
        }
    }
    
    private func reloadSiteLists() {
        if permission == .autoplay {
            let defaultAction = SiteSettingsUtils.defaultAction(for: permission)
            var items: [(host: String, action: SitePermissionAction)] = []
            for action in [SitePermissionAction.allowed, .askToAllow, .blocked] {
                if action == defaultAction {
                    continue
                }
                
                let entries = SitePermissionStore.shared.hosts(for: permission, action: action)
                for entry in entries {
                    items.append((host: entry.host, action: action))
                }
            }
            
            customActionSites = items.sorted { lhs, rhs in
                lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            allowedSites = []
            deniedSites = []
            return
        }
        
        let allowedEntries = SitePermissionStore.shared.hosts(for: permission, action: .allowed)
        let deniedEntries = SitePermissionStore.shared.hosts(for: permission, action: .blocked)
        allowedSites = allowedEntries.map { SiteEntry(host: $0.host, updatedAt: $0.updatedAt) }
        deniedSites = deniedEntries.map { SiteEntry(host: $0.host, updatedAt: $0.updatedAt) }
        customActionSites = []
    }
    
    private func clearSiteActionConfiguration(for host: String) -> UISwipeActionsConfiguration {
        let clearAction = UIContextualAction(style: .destructive, title: "Clear") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            
            SitePermissionStore.shared.removePersistedActionAndWait(for: self.permission, host: host)
            SiteSettingsUtils.clearGeckoPermission(for: self.permission, host: host)
            self.reloadSiteLists()
            self.tableView.reloadData()
            completion(true)
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [clearAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    private func siteSubtitle(for action: SitePermissionAction, at date: Date) -> String {
        let timestamp = timestampFormatter.string(from: date)
        switch action {
        case .allowed:
            return "Allowed on \(timestamp)"
        case .blocked:
            return "Denied on \(timestamp)"
        case .askToAllow:
            return "Changed on \(timestamp)"
        }
    }
    
}
