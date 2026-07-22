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
        case media
        case permissions
        case websiteActions
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
                return NSLocalizedString("Camera", comment: "")
            case .microphone:
                return NSLocalizedString("Microphone", comment: "")
            case .location:
                return NSLocalizedString("Location", comment: "")
            case .persistentStorage:
                return NSLocalizedString("Persistent Storage", comment: "")
            case .crossOriginStorageAccess:
                return NSLocalizedString("Cross-Site Cookies", comment: "")
            case .localDeviceAccess:
                return NSLocalizedString("Device Apps and Services", comment: "")
            case .localNetworkAccess:
                return NSLocalizedString("Local Network Devices", comment: "")
            case .autoplay:
                return NSLocalizedString("Autoplay", comment: "")
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
    
    private let mediaRows: [Row] = [
        .autoplay,
    ]
    private let permissionRows: [Row] = [
        .camera,
        .microphone,
        .location,
    ]
    private let host: String
    private let origin: String
    private let session: GeckoSession
    private var loadState: LoadingState = .loading
    private var loadedGeckoPermissions: [ContentPermission] = []
    
    private var visibleSections: [Section] {
        var sections: [Section] = []
        
        if !SiteSettingsUtils.disabledPermissionNames().isEmpty {
            sections.append(.availability)
        }
        
        sections.append(.media)
        sections.append(.permissions)
        sections.append(.websiteActions)
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
        title = String(format: NSLocalizedString("Settings for %@", comment: "Website host"), host)
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
        case .media:
            return loadState == .loaded ? mediaRows.count : 0
        case .permissions:
            return loadState == .loaded ? permissionRows.count : 0
        case .websiteActions:
            return loadState == .loaded ? 2 : 0
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else {
            return nil
        }
        
        switch visibleSections[section] {
        case .availability:
            return nil
        case .media:
            return NSLocalizedString("Media", comment: "")
        case .permissions:
            return NSLocalizedString("Permissions", comment: "")
        case .websiteActions:
            return nil
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
        case .media:
            return permissionCell(at: indexPath)
        case .permissions:
            return permissionCell(at: indexPath)
        case .websiteActions:
            return websiteActionCell(at: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard visibleSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch visibleSections[indexPath.section] {
        case .availability:
            handleAvailabilitySelection(at: indexPath)
        case .media:
            handlePermissionSelection(at: indexPath)
        case .permissions:
            handlePermissionSelection(at: indexPath)
        case .websiteActions:
            handleWebsiteActionSelection(at: indexPath)
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
        cell.textLabel?.text = NSLocalizedString("Open Settings", comment: "")
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
    
    private func websiteActionCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.row == 0 {
            cell.textLabel?.text = NSLocalizedString("Clear Cookies and Website Data", comment: "")
            cell.textLabel?.textColor = .systemRed
        } else {
            cell.textLabel?.text = NSLocalizedString("Reset Settings for This Website", comment: "")
            cell.textLabel?.textColor = .systemRed
        }
        cell.textLabel?.textAlignment = .center
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
        case .media:
            return mediaRows[safe: indexPath.row]
        case .permissions:
            return permissionRows[safe: indexPath.row]
        case .availability, .websiteActions:
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
        
        if #available(iOS 14.0, *) {
            if #available(iOS 17.4, *),
               let cell = tableView.cellForRow(at: indexPath),
               let button = cell.accessoryView as? UIButton {
                button.performPrimaryAction()
            }
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
    
    private func handleWebsiteActionSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            confirmClearWebsiteData()
        } else {
            confirmResetWebsiteSettings()
        }
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
        if action == .askToAllow, permission != .autoplay {
            PermissionDelegate.removePermission(
                uri: origin,
                permissionKey: key,
                privateMode: session.isPrivateMode
            )
            return
        }
        
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
    
    private func confirmResetWebsiteSettings() {
        AlertPresenter.show(
            title: nil,
            message: NSLocalizedString("This will reset settings for this website. This action cannot be undone.", comment: ""),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Reset", comment: "Destructive button"), style: .destructive) { [weak self] in
                    self?.performResetWebsiteSettings()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
    
    private func confirmClearWebsiteData() {
        AlertPresenter.show(
            title: NSLocalizedString("Clear Cookies and Website Data", comment: ""),
            message: String(
                format: NSLocalizedString("Removing cookies and website data for %@ may require you to sign in again.", comment: "Website host"),
                host
            ),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Clear", comment: "Destructive button"), style: .destructive) { [weak self] in
                    self?.clearWebsiteData()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
    
    private func clearWebsiteData() {
        Task { [weak self] in
            guard let self else {
                return
            }
            
            do {
                try await GeckoStorageController.clearData(
                    forHost: host,
                    flags: GeckoStorageClearFlags.cookies
                    | GeckoStorageClearFlags.authSessions
                    | GeckoStorageClearFlags.domStorages
                )
                await MainActor.run {
                    self.session.reload()
                }
            } catch {
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn’t Clear Cookies and Website Data", comment: ""),
                    message: "\(error)"
                )
            }
        }
    }
    
    private func performResetWebsiteSettings() {
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
