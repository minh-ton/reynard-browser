//
//  SitePermissionDetailsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SitePermissionDetailsViewController: SettingsTableViewController {
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
        case allowedSiteEntries
        case blockedSiteEntries
        case customSiteActions
        
        var text: SettingsSectionText {
            switch self {
            case .defaultBehavior:
                return SettingsSectionText(headerTitle: "Default Behavior")
            case .allowedSiteEntries:
                return SettingsSectionText(headerTitle: "Allowed Sites")
            case .blockedSiteEntries:
                return SettingsSectionText(headerTitle: "Denied Sites")
            case .customSiteActions:
                return SettingsSectionText(headerTitle: "Changed Sites")
            }
        }
    }
    
    private let permission: SitePermission
    private var allowedSiteEntries: [SiteEntry] = []
    private var blockedSiteEntries: [SiteEntry] = []
    private var customSiteActions: [(host: String, action: SitePermissionAction)] = []
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(permission: SitePermission, title: String) {
        self.permission = permission
        super.init(style: .insetGrouped)
        configureViewController(title: title)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSiteEntries()
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
        case .defaultBehavior:
            return defaultActionOptions.count
        case .allowedSiteEntries:
            return max(allowedSiteEntries.count, 1)
        case .blockedSiteEntries:
            return max(blockedSiteEntries.count, 1)
        case .customSiteActions:
            return max(customSiteActions.count, 1)
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .defaultBehavior:
            return defaultActionCell(for: indexPath)
        case .allowedSiteEntries:
            return allowedSiteEntryCell(for: indexPath)
        case .blockedSiteEntries:
            return blockedSiteEntryCell(for: indexPath)
        case .customSiteActions:
            return customSiteActionCell(for: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .defaultBehavior,
              defaultActionOptions.indices.contains(indexPath.row) else {
            return
        }
        
        SiteSettingsUtils.setDefaultAction(defaultActionOptions[indexPath.row].action, for: permission)
        reloadSiteEntries()
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard displayedSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch displayedSections[indexPath.section] {
        case .allowedSiteEntries:
            guard allowedSiteEntries.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionSwipeConfiguration(for: allowedSiteEntries[indexPath.row].host)
        case .blockedSiteEntries:
            guard blockedSiteEntries.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionSwipeConfiguration(for: blockedSiteEntries[indexPath.row].host)
        case .customSiteActions:
            guard customSiteActions.indices.contains(indexPath.row) else {
                return nil
            }
            return clearSiteActionSwipeConfiguration(for: customSiteActions[indexPath.row].host)
        case .defaultBehavior:
            return nil
        }
    }
    
    private func configureViewController(title: String) {
        self.title = title
    }
    
    private var displayedSections: [Section] {
        if permission == .autoplay {
            return [
                .defaultBehavior,
                .customSiteActions,
            ]
        }
        
        return [
            .defaultBehavior,
            .allowedSiteEntries,
            .blockedSiteEntries,
        ]
    }
    
    private var defaultActionOptions: [ActionOption] {
        switch permission {
        case .autoplay:
            return defaultActionOptions(for: [.allowed, .askToAllow, .blocked])
        default:
            return defaultActionOptions(for: [.askToAllow, .allowed, .blocked])
        }
    }
    
    private func defaultActionCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard defaultActionOptions.indices.contains(indexPath.row) else {
            return cell
        }
        
        let option = defaultActionOptions[indexPath.row]
        cell.textLabel?.text = option.title
        cell.accessoryType = option.action == SiteSettingsUtils.defaultAction(for: permission) ? .checkmark : .none
        return cell
    }
    
    private func allowedSiteEntryCell(for indexPath: IndexPath) -> UITableViewCell {
        guard !allowedSiteEntries.isEmpty else {
            return emptySiteEntryCell()
        }
        guard allowedSiteEntries.indices.contains(indexPath.row) else {
            return UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        }
        
        let site = allowedSiteEntries[indexPath.row]
        return siteEntryCell(host: site.host, subtitle: siteActionSubtitle(for: .allowed, at: site.updatedAt))
    }
    
    private func blockedSiteEntryCell(for indexPath: IndexPath) -> UITableViewCell {
        guard !blockedSiteEntries.isEmpty else {
            return emptySiteEntryCell()
        }
        guard blockedSiteEntries.indices.contains(indexPath.row) else {
            return UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        }
        
        let site = blockedSiteEntries[indexPath.row]
        return siteEntryCell(host: site.host, subtitle: siteActionSubtitle(for: .blocked, at: site.updatedAt))
    }
    
    private func customSiteActionCell(for indexPath: IndexPath) -> UITableViewCell {
        guard !customSiteActions.isEmpty else {
            return emptySiteEntryCell()
        }
        guard customSiteActions.indices.contains(indexPath.row) else {
            return UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        }
        
        let site = customSiteActions[indexPath.row]
        return siteEntryCell(
            host: site.host,
            subtitle: SiteSettingsUtils.actionTitle(for: site.action, permission: permission)
        )
    }
    
    private func emptySiteEntryCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = "No Sites Added"
        cell.textLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .none
        return cell
    }
    
    private func siteEntryCell(host: String, subtitle: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = host
        cell.detailTextLabel?.text = subtitle
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .default
        return cell
    }
    
    private func defaultActionOptions(for actions: [SitePermissionAction]) -> [ActionOption] {
        actions.map {
            ActionOption(
                title: SiteSettingsUtils.actionTitle(for: $0, permission: permission),
                action: $0
            )
        }
    }
    
    private func reloadSiteEntries() {
        if permission == .autoplay {
            let defaultAction = SiteSettingsUtils.defaultAction(for: permission)
            var items: [(host: String, action: SitePermissionAction)] = []
            for action in [SitePermissionAction.allowed, .askToAllow, .blocked] {
                if action == defaultAction {
                    continue
                }
                
                let entries = SitePermissionStore.shared.storedHosts(for: permission, action: action)
                for entry in entries {
                    items.append((host: entry.host, action: action))
                }
            }
            
            customSiteActions = items.sorted { lhs, rhs in
                lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            allowedSiteEntries = []
            blockedSiteEntries = []
            return
        }
        
        let allowedEntries = SitePermissionStore.shared.storedHosts(for: permission, action: .allowed)
        let deniedEntries = SitePermissionStore.shared.storedHosts(for: permission, action: .blocked)
        allowedSiteEntries = allowedEntries.map { SiteEntry(host: $0.host, updatedAt: $0.updatedAt) }
        blockedSiteEntries = deniedEntries.map { SiteEntry(host: $0.host, updatedAt: $0.updatedAt) }
        customSiteActions = []
    }
    
    private func clearSiteActionSwipeConfiguration(for host: String) -> UISwipeActionsConfiguration {
        let clearAction = UIContextualAction(style: .destructive, title: "Clear") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            
            SitePermissionStore.shared.removePersistedAction(for: self.permission, host: host)
            SiteSettingsUtils.clearGeckoPermission(for: self.permission, host: host)
            self.reloadSiteEntries()
            self.tableView.reloadData()
            completion(true)
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [clearAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    private func siteActionSubtitle(for action: SitePermissionAction, at date: Date) -> String {
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
