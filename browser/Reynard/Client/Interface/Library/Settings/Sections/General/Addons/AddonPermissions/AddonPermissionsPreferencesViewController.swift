//
//  AddonPermissionsPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

final class AddonPermissionsPreferencesViewController: SettingsTableViewController {
    private struct SectionModel {
        let text: SettingsSectionText
        let displayedRows: [Row]
        
        init(headerTitle: String? = nil, footerTitle: String? = nil, displayedRows: [Row]) {
            text = SettingsSectionText(headerTitle: headerTitle, footerTitle: footerTitle)
            self.displayedRows = displayedRows
        }
    }
    
    private enum Row {
        case message(String)
        case toggle(title: String, subtitle: String?, isOn: Bool, isEnabled: Bool, kind: ToggleKind)
        case warning(String)
    }
    
    private enum ToggleKind {
        case allSites([String])
        case optionalPermission(String)
        case origin(String)
        case optionalDataCollection(String)
    }
    
    private let addonID: String
    private var addon: Addon?
    private var isUpdatingPermissions = false
    
    private var permissionSections: [SectionModel] {
        guard let addon else {
            return []
        }
        
        let metaData = addon.metaData
        let requiredPermissions = AddonPermissionSupport.localizePermissions(metaData.requiredPermissions + metaData.requiredOrigins)
        let optionalPermissions = AddonPermissionSupport.localizeOptionalPermissions(
            metaData.optionalPermissions,
            grantedPermissions: metaData.grantedOptionalPermissions
        )
        
        var combinedOptionalOrigins: [String] = []
        for origin in metaData.optionalOrigins + metaData.grantedOptionalOrigins where !combinedOptionalOrigins.contains(origin) {
            combinedOptionalOrigins.append(origin)
        }
        
        let allSiteOrigins = AddonPermissionSupport.allSiteOriginPermissions(combinedOptionalOrigins)
        let allSitesEnabled = metaData.grantedOptionalOrigins.contains(where: { allSiteOrigins.contains($0) })
        let optionalOrigins = AddonPermissionSupport.localizeOptionalOrigins(
            combinedOptionalOrigins,
            grantedOrigins: metaData.grantedOptionalOrigins
        ).filter { !allSiteOrigins.contains($0.name) }
        let optionalDataCollectionPermissions = AddonPermissionSupport.localizeOptionalDataCollectionPermissions(
            metaData.optionalDataCollectionPermissions,
            grantedPermissions: metaData.grantedOptionalDataCollectionPermissions
        )
        
        var sections: [SectionModel] = []
        
        if requiredPermissions.isEmpty,
           optionalPermissions.isEmpty,
           optionalOrigins.isEmpty,
           metaData.requiredDataCollectionPermissions.isEmpty,
           optionalDataCollectionPermissions.isEmpty {
            sections.append(
                SectionModel(
                    displayedRows: [.message(AddonPermissionSupport.noPermissionsRequiredDescription)]
                )
            )
            return sections
        }
        
        if !requiredPermissions.isEmpty {
            sections.append(
                SectionModel(
                    headerTitle: "Required Permissions",
                    displayedRows: requiredPermissions.map(Row.message)
                )
            )
        }
        
        var optionalRows: [Row] = []
        if !allSiteOrigins.isEmpty {
            optionalRows.append(
                .toggle(
                    title: AddonPermissionSupport.allowForAllSitesTitle,
                    subtitle: AddonPermissionSupport.allowForAllSitesSubtitle,
                    isOn: allSitesEnabled,
                    isEnabled: !isUpdatingPermissions,
                    kind: .allSites(allSiteOrigins)
                )
            )
        }
        
        optionalPermissions.forEach { permission in
            optionalRows.append(
                .toggle(
                    title: permission.localizedName,
                    subtitle: nil,
                    isOn: permission.granted,
                    isEnabled: !isUpdatingPermissions,
                    kind: .optionalPermission(permission.name)
                )
            )
            
            if permission.name == "userScripts" {
                optionalRows.append(.warning(AddonPermissionSupport.userScriptsWarning))
            }
        }
        
        optionalOrigins.forEach { permission in
            optionalRows.append(
                .toggle(
                    title: permission.localizedName,
                    subtitle: nil,
                    isOn: permission.granted,
                    isEnabled: !allSitesEnabled && !isUpdatingPermissions,
                    kind: .origin(permission.name)
                )
            )
        }
        
        if !optionalRows.isEmpty {
            sections.append(SectionModel(headerTitle: "Optional Permissions", displayedRows: optionalRows))
        }
        
        if let requiredDataCollectionDescription = AddonPermissionSupport.requiredDataCollectionDescription(for: metaData.requiredDataCollectionPermissions) {
            sections.append(
                SectionModel(
                    headerTitle: "Required Data Collection",
                    displayedRows: [.message(requiredDataCollectionDescription)]
                )
            )
        }
        
        if !optionalDataCollectionPermissions.isEmpty {
            sections.append(
                SectionModel(
                    headerTitle: "Optional Data Collection",
                    displayedRows: optionalDataCollectionPermissions.map {
                        .toggle(
                            title: $0.localizedName,
                            subtitle: nil,
                            isOn: $0.granted,
                            isEnabled: !isUpdatingPermissions,
                            kind: .optionalDataCollection($0.name)
                        )
                    }
                )
            )
        }
        
        return sections
    }
    
    // MARK: - Lifecycle
    
    init(addonID: String) {
        self.addonID = addonID
        super.init(style: .insetGrouped)
        title = "Permissions"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            await self?.refreshAddon()
        }
    }
    
    // MARK: - Table Structure
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        permissionSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard permissionSections.indices.contains(section) else {
            return 0
        }
        
        return permissionSections[section].displayedRows.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard permissionSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return permissionSections[section].text
    }
    
    // MARK: - Cells
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard permissionSections.indices.contains(indexPath.section),
              permissionSections[indexPath.section].displayedRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch permissionSections[indexPath.section].displayedRows[indexPath.row] {
        case .message(let text):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = text
            cell.textLabel?.numberOfLines = 0
            return cell
        case .toggle(let title, let subtitle, let isOn, let isEnabled, _):
            let cell = UITableViewCell(style: subtitle == nil ? .default : .subtitle, reuseIdentifier: nil)
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.isEnabled = isEnabled
            toggle.tag = indexPath.section * 1000 + indexPath.row
            toggle.addTarget(self, action: #selector(permissionSwitchDidChange(_:)), for: .valueChanged)
            cell.selectionStyle = .none
            cell.textLabel?.text = title
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.text = subtitle
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryView = toggle
            return cell
        case .warning(let text):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = text
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.textColor = .secondaryLabel
            return cell
        }
    }
    
    // MARK: - Actions
    
    @objc private func permissionSwitchDidChange(_ sender: UISwitch) {
        let section = sender.tag / 1000
        let row = sender.tag % 1000
        
        guard permissionSections.indices.contains(section),
              permissionSections[section].displayedRows.indices.contains(row),
              case let .toggle(_, _, isOn, _, kind) = permissionSections[section].displayedRows[row],
              let addon else {
            return
        }
        
        let desiredState = sender.isOn
        if desiredState == isOn {
            return
        }
        
        let request: AddonPermissionChangeRequest
        switch kind {
        case .allSites(let origins):
            request = AddonPermissionChangeRequest(origins: origins)
        case .optionalPermission(let permission):
            request = AddonPermissionChangeRequest(permissions: [permission])
        case .origin(let origin):
            request = AddonPermissionChangeRequest(origins: [origin])
        case .optionalDataCollection(let permission):
            request = AddonPermissionChangeRequest(dataCollectionPermissions: [permission])
        }
        
        Task { [weak self] in
            guard let self else {
                return
            }
            
            await MainActor.run {
                self.isUpdatingPermissions = true
                self.tableView.reloadData()
            }
            
            do {
                let updatedAddon = try await (desiredState
                                              ? AddonRuntime.shared.addOptionalPermissions(request, to: addon)
                                              : AddonRuntime.shared.removeOptionalPermissions(request, from: addon))
                
                await MainActor.run {
                    self.isUpdatingPermissions = false
                    self.addon = updatedAddon
                    self.title = updatedAddon.metaData.name ?? updatedAddon.id
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingPermissions = false
                    self.addon = addon
                    self.tableView.reloadData()
                    AlertPresenter.show(title: "Failed to update permissions", message: "\(error)")
                }
            }
        }
    }
    
    // MARK: - Add-on Loading
    
    private func refreshAddon() async {
        do {
            let refreshedAddon = try await AddonRuntime.shared.addon(byID: addonID)
            await MainActor.run {
                guard let refreshedAddon else {
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                
                self.addon = refreshedAddon
                self.title = refreshedAddon.metaData.name ?? refreshedAddon.id
                self.tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                AlertPresenter.show(title: "Failed to reload add-on", message: "\(error)")
            }
        }
    }
    
}
