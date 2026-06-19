//
//  AddonDetailsPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

final class AddonDetailsPreferencesViewController: SettingsTableViewController {
    private enum Section {
        case status
        case actions
        case destinations
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private enum ActionRow {
        case enabled
        case privateBrowsing
        case settings
        case details
        case permissions
        case remove
    }
    
    private enum StatusRow: CaseIterable {
        case message
    }
    
    private struct StatusMessage {
        let text: String
        let color: UIColor
    }
    
    private let addonID: String
    private let enableSwitch = UISwitch()
    private let privateBrowsingSwitch = UISwitch()
    private var addon: Addon?
    private var isUpdatingAddon = false
    
    private var displayedSections: [Section] {
        var sections: [Section] = []
        if statusMessage != nil {
            sections.append(.status)
        }
        sections.append(.actions)
        if !displayedNavigationRows.isEmpty {
            sections.append(.destinations)
        }
        return sections
    }
    
    private var displayedActionRows: [ActionRow] {
        var rows: [ActionRow] = [.enabled]
        
        if addon?.metaData.enabled == true {
            rows.append(.privateBrowsing)
        }
        return rows
    }
    
    private var displayedNavigationRows: [ActionRow] {
        var rows: [ActionRow] = []
        
        if settingsPageURL != nil {
            rows.append(.settings)
        }
        
        rows.append(contentsOf: [.details, .permissions, .remove])
        return rows
    }
    
    private var settingsPageURL: String? {
        guard let optionsURLString = addon?.metaData.optionsPageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !optionsURLString.isEmpty,
              URL(string: optionsURLString) != nil else {
            return nil
        }
        return optionsURLString
    }
    
    private var statusMessage: StatusMessage? {
        guard let addon else {
            return nil
        }
        
        let metaData = addon.metaData
        if metaData.isBlocklisted {
            return StatusMessage(
                text: "This extension is blocked for violating Mozilla's policies and has been disabled.",
                color: .systemRed
            )
        }
        
        if metaData.isUnsupported {
            return StatusMessage(
                text: "This extension isn't supported by this version of Reynard and has been disabled.",
                color: .systemOrange
            )
        }
        
        if metaData.isUnsigned {
            let addonName = metaData.name ?? addon.id
            return StatusMessage(
                text: "\(addonName) could not be verified as secure and has been disabled.",
                color: .systemRed
            )
        }
        
        if metaData.isIncompatible {
            let addonName = metaData.name ?? addon.id
            return StatusMessage(
                text: "\(addonName) is not compatible with this version of Reynard.",
                color: .systemOrange
            )
        }
        
        if metaData.isSoftBlocked {
            return StatusMessage(
                text: metaData.enabled
                ? "This extension is restricted. Using it may be risky."
                : "This extension is restricted and has been disabled. You can enable it, but this may be risky.",
                color: .systemOrange
            )
        }
        
        return nil
    }
    
    // MARK: - Lifecycle
    
    init(addonID: String) {
        self.addonID = addonID
        super.init(style: .insetGrouped)
        title = "Add-on"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitches()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            await self?.refreshAddon()
        }
    }
    
    // MARK: - Table Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        
        switch displayedSections[section] {
        case .status:
            return StatusRow.allCases.count
        case .actions:
            return displayedActionRows.count
        case .destinations:
            return displayedNavigationRows.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .status:
            guard StatusRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            switch StatusRow.allCases[indexPath.row] {
            case .message:
                return statusMessageCell()
            }
        case .actions:
            return addonActionCell(for: indexPath)
        case .destinations:
            return addonNavigationCell(for: indexPath)
        }
    }
    
    // MARK: - Table Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        guard displayedSections.indices.contains(indexPath.section),
              let addon,
              !isUpdatingAddon else {
            return
        }
        
        switch displayedSections[indexPath.section] {
        case .status:
            return
        case .actions:
            guard displayedActionRows.indices.contains(indexPath.row) else {
                return
            }
            
            switch displayedActionRows[indexPath.row] {
            case .enabled, .privateBrowsing:
                return
            case .settings, .details, .permissions, .remove:
                return
            }
        case .destinations:
            guard displayedNavigationRows.indices.contains(indexPath.row) else {
                return
            }
            
            switch displayedNavigationRows[indexPath.row] {
            case .settings:
                guard let settingsPageURL else {
                    return
                }
                LibrarySharedUtils.openLinkInBrowser(settingsPageURL, from: self)
            case .details:
                navigationController?.pushViewController(AddonInformationPreferencesViewController(addonID: addon.id), animated: true)
            case .permissions:
                navigationController?.pushViewController(AddonPermissionsPreferencesViewController(addonID: addon.id), animated: true)
            case .remove:
                confirmRemoval()
            case .enabled, .privateBrowsing:
                return
            }
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    // MARK: - Actions
    
    @objc private func privateBrowsingSwitchChanged(_ sender: UISwitch) {
        let desiredState = sender.isOn
        
        Task { [weak self] in
            guard let self, let addon = self.addon else {
                await MainActor.run {
                    sender.setOn(!desiredState, animated: true)
                }
                return
            }
            
            await MainActor.run {
                self.isUpdatingAddon = true
                self.tableView.reloadData()
            }
            
            do {
                let updatedAddon = try await AddonRuntime.shared.setAllowedInPrivateBrowsing(addon, allowed: desiredState)
                
                await MainActor.run {
                    self.isUpdatingAddon = false
                    self.display(addon: updatedAddon)
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingAddon = false
                    self.display(addon: addon)
                    AlertPresenter.show(title: "Failed to update private browsing access", message: "\(error)")
                }
            }
        }
    }
    
    @objc private func enableSwitchChanged(_ sender: UISwitch) {
        let desiredState = sender.isOn
        
        Task { [weak self] in
            guard let self, let addon = self.addon else {
                await MainActor.run {
                    sender.setOn(!desiredState, animated: true)
                }
                return
            }
            
            await MainActor.run {
                self.isUpdatingAddon = true
                self.tableView.reloadData()
            }
            
            do {
                let updatedAddon = try await (desiredState
                                              ? AddonRuntime.shared.enable(addon)
                                              : AddonRuntime.shared.disable(addon))
                
                await MainActor.run {
                    self.isUpdatingAddon = false
                    self.display(addon: updatedAddon)
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingAddon = false
                    self.display(addon: addon)
                    AlertPresenter.show(title: "Failed to \(desiredState ? "enable" : "disable") add-on", message: "\(error)")
                }
            }
        }
    }
    
    // MARK: - View Setup
    
    private func configureSwitches() {
        enableSwitch.isEnabled = false
        enableSwitch.addTarget(self, action: #selector(enableSwitchChanged(_:)), for: .valueChanged)
        privateBrowsingSwitch.isEnabled = false
        privateBrowsingSwitch.addTarget(self, action: #selector(privateBrowsingSwitchChanged(_:)), for: .valueChanged)
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
                
                self.display(addon: refreshedAddon)
            }
        } catch {
            await MainActor.run {
                AlertPresenter.show(title: "Failed to reload add-on", message: "\(error)")
            }
        }
    }
    
    private func display(addon: Addon) {
        self.addon = addon
        title = addon.metaData.name ?? addon.id
        enableSwitch.isOn = addon.metaData.enabled
        enableSwitch.isEnabled = addon.metaData.canBeEnabled && !isUpdatingAddon
        privateBrowsingSwitch.isOn = addon.metaData.allowedInPrivateBrowsing
        privateBrowsingSwitch.isEnabled = addon.metaData.incognito != .notAllowed && !isUpdatingAddon
        tableView.reloadData()
    }
    
    // MARK: - Cells
    
    private func statusMessageCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        
        if let statusMessage {
            cell.textLabel?.text = statusMessage.text
            cell.textLabel?.textColor = statusMessage.color
        }
        
        return cell
    }
    
    private func addonActionCell(for indexPath: IndexPath) -> UITableViewCell {
        guard displayedActionRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        
        switch displayedActionRows[indexPath.row] {
        case .enabled:
            cell.textLabel?.text = "Enabled"
            cell.selectionStyle = .none
            cell.accessoryView = enableSwitch
        case .privateBrowsing:
            cell.textLabel?.text = addon?.metaData.incognito == .notAllowed
            ? "Not Allowed in Private Browsing"
            : "Allow in Private Browsing"
            cell.textLabel?.textColor = addon?.metaData.incognito == .notAllowed ? .secondaryLabel : .label
            cell.selectionStyle = .none
            cell.accessoryView = privateBrowsingSwitch
        case .remove:
            cell.textLabel?.text = "Remove"
            cell.textLabel?.textColor = addon == nil || isUpdatingAddon ? .secondaryLabel : .systemRed
        case .settings, .details, .permissions:
            break
        }
        
        if addon == nil || isUpdatingAddon {
            cell.isUserInteractionEnabled = false
        }
        
        return cell
    }
    
    private func addonNavigationCell(for indexPath: IndexPath) -> UITableViewCell {
        guard displayedNavigationRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = addon == nil || isUpdatingAddon ? .secondaryLabel : view.tintColor
        cell.accessoryType = .disclosureIndicator
        
        switch displayedNavigationRows[indexPath.row] {
        case .settings:
            cell.textLabel?.text = "Settings"
        case .details:
            cell.textLabel?.text = "Details"
        case .permissions:
            cell.textLabel?.text = "Permissions"
        case .remove:
            cell.textLabel?.text = "Remove"
            cell.textLabel?.textColor = addon == nil || isUpdatingAddon ? .secondaryLabel : .systemRed
            cell.accessoryType = .none
        case .enabled, .privateBrowsing:
            break
        }
        
        if addon == nil || isUpdatingAddon {
            cell.isUserInteractionEnabled = false
        }
        
        return cell
    }
    
    // MARK: - Removal
    
    private func confirmRemoval() {
        let addonName = addon?.metaData.name ?? addonID
        AlertPresenter.show(
            title: "Do you want to remove \(addonName)?",
            message: nil,
            buttons: [
                AlertPresenter.Button(title: "Cancel", style: .cancel),
                AlertPresenter.Button(title: "Remove", style: .destructive) { [weak self] in
                    self?.uninstallAddon()
                },
            ]
        )
    }
    
    private func uninstallAddon() {
        Task { [weak self] in
            guard let self, let addon = self.addon else {
                return
            }
            
            await MainActor.run {
                self.isUpdatingAddon = true
                self.tableView.reloadData()
            }
            
            do {
                try await AddonRuntime.shared.uninstall(addon)
                await MainActor.run {
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingAddon = false
                    self.display(addon: addon)
                    AlertPresenter.show(title: "Failed to remove add-on", message: "\(error)")
                }
            }
        }
    }
}
