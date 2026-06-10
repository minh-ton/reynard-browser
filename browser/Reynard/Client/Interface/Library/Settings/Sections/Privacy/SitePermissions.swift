//
//  SitePermissions.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import GeckoView
import AVFoundation
import CoreLocation
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
        case crossSiteCookies
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
            case .crossSiteCookies:
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
            case .crossSiteCookies:
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
        .crossSiteCookies,
        .localDeviceAccess,
        .localNetworkAccess,
    ]
    private var didResetPermissionsForAllSites = false
    
    private var disabledPermissions: [String] {
        var permissions: [String] = []
        
        if isCameraPermissionDisabled() {
            permissions.append("Camera")
        }
        if isMicrophonePermissionDisabled() {
            permissions.append("Microphone")
        }
        if isLocationPermissionDisabled() {
            permissions.append("Location")
        }
        
        return permissions
    }
    
    private var visibleSections: [Section] {
        var sections: [Section] = []
        
        if !disabledPermissions.isEmpty {
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
                cell.textLabel?.text = disabledPermissionsDescription()
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
            cell.detailTextLabel?.text = permissionActionTitle(
                for: defaultPermissionAction(for: row.permission),
                permission: row.permission
            )
            if isPermissionDisabled(row.permission) {
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
            if didResetPermissionsForAllSites {
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
                openAppSettings()
            }
        case .permissions:
            guard let row = row(at: indexPath) else {
                return
            }
            guard !isPermissionDisabled(row.permission) else {
                return
            }
            
            navigationController?.pushViewController(
                SitePermissionDetailsViewController(permission: row.permission, title: row.title),
                animated: true
            )
        case .websiteActions:
            resetPermissionsForAllSites()
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
    
    private func resetPermissionsForAllSites() {
        let permissions: [SitePermission] = [
            .autoplay,
            .camera,
            .microphone,
            .location,
            .persistentStorage,
            .crossOriginStorageAccess,
            .localDeviceAccess,
            .localNetworkAccess,
        ]
        let actions: [SitePermissionAction] = [
            .allowed,
            .askToAllow,
            .blocked,
        ]
        
        for permission in permissions {
            for action in actions {
                let entries = SitePermissionStore.shared.hosts(for: permission, action: action)
                for entry in entries {
                    SitePermissionStore.shared.removePersistedActionAndWait(for: permission, host: entry.host)
                    clearGeckoPermission(for: permission, host: entry.host)
                }
            }
        }
        
        didResetPermissionsForAllSites = true
        tableView.reloadData()
    }
    
    private func isPermissionDisabled(_ permission: SitePermission) -> Bool {
        switch permission {
        case .camera:
            return isCameraPermissionDisabled()
        case .microphone:
            return isMicrophonePermissionDisabled()
        case .location:
            return isLocationPermissionDisabled()
        default:
            return false
        }
    }
    
    private func disabledPermissionsDescription() -> String {
        let names = disabledPermissions
        let permissionList = formattedPermissionList(names)
        
        if names.count == 1 {
            return "\(permissionList) is currently disabled for Reynard. Open the Settings app to enable this permission."
        }
        
        return "\(permissionList) are currently disabled for Reynard. Open the Settings app to enable these permissions."
    }
    
    private func formattedPermissionList(_ names: [String]) -> String {
        if names.isEmpty {
            return ""
        }
        
        if names.count == 1 {
            return names[0]
        }
        
        if names.count == 2 {
            return "\(names[0]) and \(names[1])"
        }
        
        let head = names.dropLast().joined(separator: ", ")
        let tail = names[names.count - 1]
        return "\(head), and \(tail)"
    }
    
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

private final class SitePermissionDetailsViewController: SettingsTableViewController {
    private struct PermissionOption {
        let title: String
        let action: SitePermissionAction
    }
    
    private struct SiteRecord {
        let host: String
        let updatedAt: Date
    }
    
    private enum Section {
        case defaultBehavior
        case allowedSites
        case deniedSites
        case changedSites
    }
    
    private let permission: SitePermission
    private let store: SitePermissionStore
    private var allowedSites: [SiteRecord] = []
    private var deniedSites: [SiteRecord] = []
    private var changedSites: [(host: String, action: SitePermissionAction)] = []
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(permission: SitePermission, title: String, store: SitePermissionStore = .shared) {
        self.permission = permission
        self.store = store
        super.init(style: .insetGrouped)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadSites()
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
            return options.count
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
        case .changedSites:
            if changedSites.isEmpty {
                return 1
            }
            return changedSites.count
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
        case .changedSites:
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
            guard options.indices.contains(indexPath.row) else {
                return cell
            }
            let option = options[indexPath.row]
            cell.textLabel?.text = option.title
            cell.accessoryType = option.action == selectedDefaultAction ? .checkmark : .none
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
            cell.detailTextLabel?.text = subtitle(for: .allowed, at: site.updatedAt)
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
            cell.detailTextLabel?.text = subtitle(for: .blocked, at: site.updatedAt)
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .default
            return cell
        case .changedSites:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if changedSites.isEmpty {
                cell.textLabel?.text = "No Sites Added"
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
                return cell
            }
            guard changedSites.indices.contains(indexPath.row) else {
                return cell
            }
            let changedSite = changedSites[indexPath.row]
            cell.textLabel?.text = changedSite.host
            cell.detailTextLabel?.text = permissionActionTitle(
                for: changedSite.action,
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
              options.indices.contains(indexPath.row) else {
            return
        }
        
        setDefaultAction(options[indexPath.row].action)
        reloadSites()
        tableView.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSites()
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
            return makeClearConfiguration(
                for: allowedSites[indexPath.row].host
            )
        case .deniedSites:
            guard !deniedSites.isEmpty else {
                return nil
            }
            guard deniedSites.indices.contains(indexPath.row) else {
                return nil
            }
            return makeClearConfiguration(
                for: deniedSites[indexPath.row].host
            )
        case .defaultBehavior:
            return nil
        case .changedSites:
            guard !changedSites.isEmpty else {
                return nil
            }
            guard changedSites.indices.contains(indexPath.row) else {
                return nil
            }
            return makeClearConfiguration(
                for: changedSites[indexPath.row].host
            )
        }
    }
    
    private var visibleSections: [Section] {
        if permission == .autoplay {
            return [
                .defaultBehavior,
                .changedSites,
            ]
        }
        
        return [
            .defaultBehavior,
            .allowedSites,
            .deniedSites,
        ]
    }
    
    private var selectedDefaultAction: SitePermissionAction {
        return defaultPermissionAction(for: permission)
    }
    
    private var options: [PermissionOption] {
        switch permission {
        case .autoplay:
            return [
                PermissionOption(title: "Allow Audio and Video", action: .allowed),
                PermissionOption(title: "Block Audio only", action: .askToAllow),
                PermissionOption(title: "Block Audio and Video", action: .blocked),
            ]
        default:
            return [
                PermissionOption(title: "Ask", action: .askToAllow),
                PermissionOption(title: "Allow", action: .allowed),
                PermissionOption(title: "Deny", action: .blocked),
            ]
        }
    }
    
    private func reloadSites() {
        if permission == .autoplay {
            let defaultAction = selectedDefaultAction
            var items: [(host: String, action: SitePermissionAction)] = []
            let possibleActions: [SitePermissionAction] = [.allowed, .askToAllow, .blocked]
            for action in possibleActions {
                if action == defaultAction {
                    continue
                }
                
                let entries = store.hosts(for: permission, action: action)
                for entry in entries {
                    items.append((host: entry.host, action: action))
                }
            }
            
            changedSites = items.sorted { lhs, rhs in
                lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            allowedSites = []
            deniedSites = []
            return
        }
        
        let allowedEntries = store.hosts(for: permission, action: .allowed)
        let deniedEntries = store.hosts(for: permission, action: .blocked)
        allowedSites = allowedEntries.map { SiteRecord(host: $0.host, updatedAt: $0.updatedAt) }
        deniedSites = deniedEntries.map { SiteRecord(host: $0.host, updatedAt: $0.updatedAt) }
        changedSites = []
    }
    
    private func setDefaultAction(_ action: SitePermissionAction) {
        switch permission {
        case .autoplay:
            Prefs.SitePermissionSettings.defaultAutoplayPermission = action
        case .camera:
            Prefs.SitePermissionSettings.defaultCameraPermission = action
        case .microphone:
            Prefs.SitePermissionSettings.defaultMicrophonePermission = action
        case .location:
            Prefs.SitePermissionSettings.defaultLocationPermission = action
        case .persistentStorage:
            Prefs.SitePermissionSettings.defaultPersistentStoragePermission = action
        case .crossOriginStorageAccess:
            Prefs.SitePermissionSettings.defaultCrossOriginStorageAccessPermission = action
        case .localDeviceAccess:
            Prefs.SitePermissionSettings.defaultLocalDeviceAccessPermission = action
        case .localNetworkAccess:
            Prefs.SitePermissionSettings.defaultLocalNetworkAccessPermission = action
        case .notification:
            return
        case .mediaKeySystemAccess:
            return
        }
    }
    
    private func makeClearConfiguration(for host: String) -> UISwipeActionsConfiguration {
        let clearAction = UIContextualAction(style: .destructive, title: "Clear") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            
            self.store.removePersistedActionAndWait(for: self.permission, host: host)
            clearGeckoPermission(for: self.permission, host: host)
            self.reloadSites()
            self.tableView.reloadData()
            completion(true)
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [clearAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    private func subtitle(for action: SitePermissionAction, at date: Date) -> String {
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

private func permissionActionTitle(for action: SitePermissionAction, permission: SitePermission) -> String {
    switch permission {
    case .autoplay:
        switch action {
        case .allowed:
            return "Allow Audio and Video"
        case .askToAllow:
            return "Block Audio only"
        case .blocked:
            return "Block Audio and Video"
        }
    default:
        switch action {
        case .allowed:
            return "Allow"
        case .askToAllow:
            return "Ask"
        case .blocked:
            return "Deny"
        }
    }
}

private func defaultPermissionAction(for permission: SitePermission) -> SitePermissionAction {
    switch permission {
    case .autoplay:
        return Prefs.SitePermissionSettings.defaultAutoplayPermission
    case .camera:
        if isCameraPermissionDisabled() {
            return .blocked
        }
        return Prefs.SitePermissionSettings.defaultCameraPermission
    case .microphone:
        if isMicrophonePermissionDisabled() {
            return .blocked
        }
        return Prefs.SitePermissionSettings.defaultMicrophonePermission
    case .location:
        if isLocationPermissionDisabled() {
            return .blocked
        }
        return Prefs.SitePermissionSettings.defaultLocationPermission
    case .persistentStorage:
        return Prefs.SitePermissionSettings.defaultPersistentStoragePermission
    case .crossOriginStorageAccess:
        return Prefs.SitePermissionSettings.defaultCrossOriginStorageAccessPermission
    case .localDeviceAccess:
        return Prefs.SitePermissionSettings.defaultLocalDeviceAccessPermission
    case .localNetworkAccess:
        return Prefs.SitePermissionSettings.defaultLocalNetworkAccessPermission
    case .notification:
        return .askToAllow
    case .mediaKeySystemAccess:
        return .askToAllow
    }
}

private func isCameraPermissionDisabled() -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    return status == .restricted || status == .denied
}

private func isMicrophonePermissionDisabled() -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    return status == .restricted || status == .denied
}

private func isLocationPermissionDisabled() -> Bool {
    let status = CLLocationManager.authorizationStatus()
    return status == .restricted || status == .denied
}

private func geckoPermissionKey(for permission: SitePermission) -> String {
    switch permission {
    case .location:
        return "geo"
    default:
        return permission.rawValue
    }
}

private func clearGeckoPermission(for permission: SitePermission, host: String) {
    let key = geckoPermissionKey(for: permission)
    let normalizedHost = host.lowercased()
    let origins = [
        "http://\(normalizedHost)",
        "https://\(normalizedHost)",
    ]
    
    for origin in origins {
        PermissionDelegate.shared.removePermission(
            uri: origin,
            permissionKey: key,
            privateMode: false
        )
    }
    
    Task {
        for origin in origins {
            let permissions = (try? await PermissionDelegate.shared.permissions(
                for: origin,
                privateMode: false
            )) ?? []
            
            for resolvedPermission in permissions {
                guard SitePermission(contentPermission: resolvedPermission) == permission else {
                    continue
                }
                
                PermissionDelegate.shared.removePermission(resolvedPermission)
            }
        }
    }
}
