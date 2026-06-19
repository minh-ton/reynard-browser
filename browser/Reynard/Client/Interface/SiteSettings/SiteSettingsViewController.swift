//
//  SiteSettingsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class SiteSettingsViewController: UITableViewController {
    private let permissionCellReuseIdentifier = "Cell"
    
    private enum Section {
        case availability
        case permissions
        case siteActions
    }
    
    private enum Row: CaseIterable {
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
            case .crossOriginStorageAccess:
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
    
    private enum LoadingState {
        case loading
        case loaded
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
    private let host: String
    private let origin: String
    private let session: GeckoSession
    private var loadState: LoadingState = .loading
    private var loadedGeckoPermissions: [ContentPermission] = []
    private var didResetSitePermissions = false
    
    private var visibleSections: [Section] {
        var sections: [Section] = []
        
        if !SiteSettingsUtils.disabledPermissionNames().isEmpty {
            sections.append(.availability)
        }
        
        sections.append(.permissions)
        sections.append(.siteActions)
        return sections
    }
    
    init?(url: URL, session: GeckoSession) {
        guard let host = URLUtils.normalizedHost(url.host),
              let origin = URLUtils.httpOriginString(for: url) else {
            return nil
        }
        
        self.host = host
        self.origin = origin
        self.session = session
        super.init(style: .insetGrouped)
        title = "Settings for \(host)"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { [weak self] in
            await self?.loadPermissionsFromGecko()
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
            return loadState == .loaded ? permissionRows.count : 0
        case .siteActions:
            return loadState == .loaded ? 1 : 0
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
        case .siteActions:
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
        
        switch visibleSections[indexPath.section] {
        case .availability:
            return availabilityCell(at: indexPath)
        case .permissions:
            return permissionCell(at: indexPath)
        case .siteActions:
            return resetSitePermissionsCell()
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard visibleSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch visibleSections[indexPath.section] {
        case .availability:
            handleAvailabilitySelection(at: indexPath)
        case .permissions:
            handlePermissionSelection(at: indexPath)
        case .siteActions:
            resetSitePermissions()
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Table Data
    
    private func availabilityCell(at indexPath: IndexPath) -> UITableViewCell {
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
    }
    
    private func permissionCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: permissionCellReuseIdentifier)
        ?? UITableViewCell(style: .value1, reuseIdentifier: permissionCellReuseIdentifier)
        
        guard let row = row(at: indexPath) else {
            return cell
        }
        
        let titles = SiteSettingsUtils.actionTitles(for: row.permission)
        let selectedIndex = selectedOptionIndex(for: row)
        cell.textLabel?.text = row.title
        if SiteSettingsUtils.isSystemDisabled(row.permission) {
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = titles[selectedIndex]
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
            cell.accessoryView = permissionMenuButton(for: row)
            cell.accessoryType = .none
        } else {
            cell.detailTextLabel?.text = titles[selectedIndex]
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    
    private func resetSitePermissionsCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = "Reset Permissions for this Site"
        cell.textLabel?.textColor = .systemRed
        cell.detailTextLabel?.text = didResetSitePermissions ? "Successfully reset permissions for this site." : nil
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }
    
    private func row(at indexPath: IndexPath) -> Row? {
        guard visibleSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch visibleSections[indexPath.section] {
        case .permissions:
            return permissionRows[safe: indexPath.row]
        case .siteActions,
                .availability:
            return nil
        }
    }
    
    // MARK: - Actions
    
    private func handleAvailabilitySelection(at indexPath: IndexPath) {
        guard indexPath.row == 1 else {
            return
        }
        
        SiteSettingsUtils.openAppSettings()
    }
    
    private func handlePermissionSelection(at indexPath: IndexPath) {
        guard let row = row(at: indexPath),
              !SiteSettingsUtils.isSystemDisabled(row.permission) else {
            return
        }
        
        if #available(iOS 17.4, *),
           let cell = tableView.cellForRow(at: indexPath),
           let button = cell.accessoryView as? UIButton {
            button.performPrimaryAction()
            return
        }
        
        let picker = SitePermissionOptionsViewController(
            title: row.title,
            options: SiteSettingsUtils.actionTitles(for: row.permission),
            selectedIndex: selectedOptionIndex(for: row)
        ) { [weak self] optionIndex in
            self?.applyOption(at: optionIndex, for: row)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    // MARK: - Permissions
    
    @MainActor
    private func loadPermissionsFromGecko() async {
        let permissions = (try? await PermissionDelegate.permissions(
            for: origin,
            privateMode: session.isPrivateMode
        )) ?? []
        loadedGeckoPermissions = permissions
        syncStore(with: permissions)
        loadState = .loaded
        tableView.reloadData()
    }
    
    private func syncStore(with permissions: [ContentPermission]) {
        var seenPermissions = Set<SitePermission>()
        
        for permission in permissions {
            guard let sitePermission = SitePermission(contentPermission: permission),
                  let action = sitePermission == .autoplay ? SitePermissionAction(autoplayValue: permission.rawValue) : SitePermissionAction(value: permission.value) else {
                continue
            }
            
            if SiteSettingsUtils.isSystemDisabled(sitePermission) {
                continue
            }
            
            seenPermissions.insert(sitePermission)
            if SitePermissionStore.shared.resolvedAction(for: sitePermission, host: host, session: session) != action {
                SitePermissionStore.shared.updateAction(action, for: sitePermission, host: host, session: session)
            }
        }
        
        for row in Row.allCases {
            let permission = row.permission
            if !SiteSettingsUtils.isSystemDisabled(permission),
               !seenPermissions.contains(permission),
               SitePermissionStore.shared.resolvedAction(for: permission, host: host, session: session) != .askToAllow {
                SitePermissionStore.shared.removeAction(for: permission, host: host, session: session)
            }
        }
    }
    
    private func applyOption(at optionIndex: Int, for row: Row) {
        let action: SitePermissionAction
        switch optionIndex {
        case 0:
            action = .allowed
        case 1:
            action = .askToAllow
        default:
            action = .blocked
        }
        
        setAction(action, for: row.permission)
        tableView.reloadData()
    }
    
    private func setAction(_ action: SitePermissionAction, for permission: SitePermission) {
        SitePermissionStore.shared.updateAction(action, for: permission, host: host, session: session)
        let key = SiteSettingsUtils.geckoKey(for: permission)
        if permission == .autoplay {
            PermissionDelegate.setPermission(
                uri: origin,
                permissionKey: key,
                rawValue: action.autoplayValue,
                privateMode: session.isPrivateMode
            )
            session.reload()
            return
        }
        
        PermissionDelegate.setPermission(
            uri: origin,
            permissionKey: key,
            rawValue: action.contentPermissionValue.rawValue,
            privateMode: session.isPrivateMode
        )
    }
    
    private func resetSitePermissions() {
        for permission in loadedGeckoPermissions {
            PermissionDelegate.removePermission(permission)
        }
        for permission in SitePermission.allCases {
            PermissionDelegate.removePermission(
                uri: origin,
                permissionKey: SiteSettingsUtils.geckoKey(for: permission),
                privateMode: session.isPrivateMode
            )
        }
        
        for permission in SitePermission.allCases {
            SitePermissionStore.shared.removeAction(for: permission, host: host, session: session)
        }
        loadedGeckoPermissions = []
        didResetSitePermissions = true
        tableView.reloadData()
    }
    
    // MARK: - Helpers
    
    private func configureView() {
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            SiteSettingsUtils.makeDismissButton(target: self, action: #selector(dismissModal))
        ]
    }
    
    @available(iOS 14.0, *)
    private func permissionMenuButton(for row: Row) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(SiteSettingsUtils.actionTitles(for: row.permission)[selectedOptionIndex(for: row)], for: .normal)
        button.setImage(UIImage(named: "reynard.chevron.up.chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        if #available(iOS 15.0, *) {
            button.changesSelectionAsPrimaryAction = true
        }
        button.menu = permissionMenu(for: row)
        button.sizeToFit()
        return button
    }
    
    @available(iOS 14.0, *)
    private func permissionMenu(for row: Row) -> UIMenu {
        let selectedIndex = selectedOptionIndex(for: row)
        let actions = SiteSettingsUtils.actionTitles(for: row.permission).enumerated().map { index, title in
            UIAction(title: title, state: index == selectedIndex ? .on : .off) { [weak self] _ in
                self?.applyOption(at: index, for: row)
            }
        }
        
        if #available(iOS 15.0, *) {
            return UIMenu(title: "", options: .singleSelection, children: actions)
        }
        return UIMenu(title: "", children: actions)
    }
    
    private func selectedOptionIndex(for row: Row) -> Int {
        let permission = row.permission
        switch SitePermissionStore.shared.resolvedAction(for: permission, host: host, session: session) {
        case .allowed:
            return 0
        case .askToAllow:
            return 1
        case .blocked:
            return 2
        }
    }
}
