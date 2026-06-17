//
//  SiteSettings.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import GeckoView
import AVFoundation
import CoreLocation
import UIKit

final class SiteSettingsViewController: UITableViewController {
    private enum Section {
        case availability
        case permissions
        case websiteActions
    }
    
    private enum Row: CaseIterable {
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
            case .autoplay:
                return "Autoplay"
            }
        }
        
        var permission: SitePermission {
            switch self {
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
            case .autoplay:
                return .autoplay
            }
        }
    }
    
    private let permissionRows: [Row] = [.autoplay, .camera, .microphone, .location, .persistentStorage, .crossSiteCookies, .localDeviceAccess, .localNetworkAccess]
    private let host: String
    private let origin: String
    private let session: GeckoSession
    private let store: SitePermissionStore
    private var isLoaded = false
    private var geckoPermissions: [ContentPermission] = []
    private var didResetPermissions = false
    
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
    
    init?(url: URL, session: GeckoSession, store: SitePermissionStore = .shared) {
        guard let host = url.host?.lowercased(),
              let origin = Self.originString(for: url) else {
            return nil
        }
        
        self.host = host
        self.origin = origin
        self.session = session
        self.store = store
        super.init(style: .insetGrouped)
        title = "Settings for \(host)"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        navigationItem.rightBarButtonItems = [siteSettingsDismissButton(target: self, action: #selector(dismissModal))]
        
        Task { [weak self] in
            await self?.loadPermissions()
        }
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
            guard isLoaded else {
                return 0
            }
            return permissionRows.count
        case .websiteActions:
            guard isLoaded else {
                return 0
            }
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else {
            return nil
        }
        
        switch visibleSections[section] {
        case .availability:
            return nil
        case .permissions:
            return "Permissions"
        case .websiteActions:
            return "Actions"
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        if visibleSections[indexPath.section] == .availability {
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
        }
        
        if visibleSections[indexPath.section] == .websiteActions {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "Reset Permissions for this Site"
            cell.textLabel?.textColor = .systemRed
            if didResetPermissions {
                cell.detailTextLabel?.text = "Successfully reset permissions for this site."
            } else {
                cell.detailTextLabel?.text = nil
            }
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.selectionStyle = .default
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
        ?? UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        
        guard let row = row(at: indexPath) else {
            return cell
        }
        
        cell.textLabel?.text = row.title
        if isPermissionDisabled(row.permission) {
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = options(for: row)[selectedIndex(for: row)]
            cell.detailTextLabel?.textColor = .tertiaryLabel
            cell.selectionStyle = .none
            cell.isUserInteractionEnabled = false
            cell.accessoryView = nil
            cell.accessoryType = .none
            return cell
        }
        
        cell.textLabel?.textColor = .label
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = true
        
        if #available(iOS 14.0, *) {
            cell.detailTextLabel?.text = nil
            cell.accessoryView = popupButton(for: row)
            cell.accessoryType = .none
        } else {
            cell.detailTextLabel?.text = options(for: row)[selectedIndex(for: row)]
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard visibleSections.indices.contains(indexPath.section) else {
            return
        }
        
        if visibleSections[indexPath.section] == .availability {
            if indexPath.row == 1 {
                openAppSettings()
            }
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        if visibleSections[indexPath.section] == .websiteActions {
            resetPermissions()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        guard let row = row(at: indexPath) else {
            return
        }
        
        if isPermissionDisabled(row.permission) {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        if #available(iOS 17.4, *),
           let cell = tableView.cellForRow(at: indexPath),
           let button = cell.accessoryView as? UIButton {
            button.performPrimaryAction()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        let picker = SitePermissionOptionsViewController(
            title: row.title,
            options: options(for: row),
            selectedIndex: selectedIndex(for: row)
        ) { [weak self] selectedIndex in
            self?.applySelection(selectedIndex, for: row)
        }
        navigationController?.pushViewController(picker, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @available(iOS 14.0, *)
    private func popupButton(for row: Row) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(options(for: row)[selectedIndex(for: row)], for: .normal)
        button.setImage(UIImage(systemName: "chevron.up.chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        if #available(iOS 15.0, *) {
            button.changesSelectionAsPrimaryAction = true
        }
        button.menu = popupMenu(for: row)
        button.sizeToFit()
        return button
    }
    
    @available(iOS 14.0, *)
    private func popupMenu(for row: Row) -> UIMenu {
        let selectedIndex = selectedIndex(for: row)
        let actions = options(for: row).enumerated().map { index, title in
            UIAction(title: title, state: index == selectedIndex ? .on : .off) { [weak self] _ in
                self?.applySelection(index, for: row)
            }
        }
        
        if #available(iOS 15.0, *) {
            return UIMenu(title: "", options: .singleSelection, children: actions)
        }
        return UIMenu(title: "", children: actions)
    }
    
    @MainActor
    private func loadPermissions() async {
        let permissions = (try? await PermissionDelegate.shared.permissions(
            for: origin,
            privateMode: session.isPrivateMode
        )) ?? []
        geckoPermissions = permissions
        reconcileStore(with: permissions)
        isLoaded = true
        tableView.reloadData()
    }
    
    private func reconcileStore(with permissions: [ContentPermission]) {
        var seenPermissions = Set<SitePermission>()
        
        for permission in permissions {
            guard let sitePermission = SitePermission(contentPermission: permission),
                  let action = sitePermission == .autoplay ? SitePermissionAction(autoplayValue: permission.rawValue) : SitePermissionAction(value: permission.value) else {
                continue
            }
            
            if isPermissionDisabled(sitePermission) {
                continue
            }
            
            seenPermissions.insert(sitePermission)
            if store.action(for: sitePermission, host: host, session: session) != action {
                store.setActionAndWait(action, for: sitePermission, host: host, session: session)
            }
        }
        
        for row in Row.allCases {
            let permission = row.permission
            if !isPermissionDisabled(permission),
               !seenPermissions.contains(permission),
               store.action(for: permission, host: host, session: session) != .askToAllow {
                store.removeActionAndWait(for: permission, host: host, session: session)
            }
        }
        
    }
    
    private func row(at indexPath: IndexPath) -> Row? {
        guard visibleSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch visibleSections[indexPath.section] {
        case .permissions:
            return permissionRows[safe: indexPath.row]
        case .websiteActions,
                .availability:
            return nil
        }
    }
    
    private func options(for row: Row) -> [String] {
        if row == .autoplay {
            return [
                "Allow Audio and Video",
                "Block Audio only",
                "Block Audio and Video",
            ]
        }
        
        return ["Allow", "Ask", "Deny"]
    }
    
    private func selectedIndex(for row: Row) -> Int {
        let permission = row.permission
        switch store.action(for: permission, host: host, session: session) {
        case .allowed:
            return 0
        case .askToAllow:
            return 1
        case .blocked:
            return 2
        }
    }
    
    private func applySelection(_ selectedIndex: Int, for row: Row) {
        let permission = row.permission
        let action: SitePermissionAction
        switch selectedIndex {
        case 0:
            action = .allowed
        case 1:
            action = .askToAllow
        default:
            action = .blocked
        }
        
        apply(action, for: permission)
        tableView.reloadData()
    }
    
    private func apply(_ action: SitePermissionAction, for permission: SitePermission) {
        store.setActionAndWait(action, for: permission, host: host, session: session)
        let key = permission == .location ? "geo" : permission.rawValue
        if permission == .autoplay {
            PermissionDelegate.shared.setPermission(
                uri: origin,
                permissionKey: key,
                rawValue: action.autoplayValue,
                privateMode: session.isPrivateMode
            )
            session.reload()
            return
        }
        
        PermissionDelegate.shared.setPermission(
            uri: origin,
            permissionKey: key,
            rawValue: action.contentPermissionValue.rawValue,
            privateMode: session.isPrivateMode
        )
    }
    
    private func resetPermissions() {
        for permission in geckoPermissions {
            PermissionDelegate.shared.removePermission(permission)
        }
        for permission in SitePermission.allCases {
            PermissionDelegate.shared.removePermission(
                uri: origin,
                permissionKey: permission == .location ? "geo" : permission.rawValue,
                privateMode: session.isPrivateMode
            )
        }
        
        for permission in SitePermission.allCases {
            store.removeActionAndWait(for: permission, host: host, session: session)
        }
        geckoPermissions = []
        didResetPermissions = true
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
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
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

private final class SitePermissionOptionsViewController: UITableViewController {
    private let optionTitles: [String]
    private var selectedIndex: Int
    private let onSelect: (Int) -> Void
    
    init(title: String, options: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.optionTitles = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [siteSettingsDismissButton(target: self, action: #selector(dismissModal))]
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        optionTitles.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
        ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
        cell.textLabel?.text = optionTitles[indexPath.row]
        cell.accessoryType = indexPath.row == selectedIndex ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.row
        onSelect(indexPath.row)
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
}

private func siteSettingsDismissButton(target: Any?, action: Selector) -> UIBarButtonItem {
    let button: UIBarButtonItem
    if #available(iOS 26.0, *), MakeButtons.hasLiquidGlass {
        button = UIBarButtonItem(barButtonSystemItem: .cancel, target: target, action: action)
        button.tintColor = .label
    } else {
        button = UIBarButtonItem(barButtonSystemItem: .done, target: target, action: action)
    }
    return button
}
