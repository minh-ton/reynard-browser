//
//  TrackingProtectionPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/7/26.
//

import GeckoView
import UIKit

final class TrackingProtectionPreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let footerHorizontalPadding: CGFloat = 20
        static let footerVerticalPadding: CGFloat = 8
        static let optionIndentationLevel = 1
    }
    
    private enum Row: Equatable {
        case standard
        case strict
        case strictBaselineAllowList
        case strictConvenienceAllowList
        case custom
        case customBaselineAllowList
        case customConvenienceAllowList
        case customCookies
        case customTrackingContent
        case customCryptominers
        case customKnownFingerprinters
        case customRedirectTrackers
        case customSuspectedFingerprinters
        case off
        
        var protectionLevel: TrackingProtectionLevel? {
            switch self {
            case .standard:
                return .standard
            case .strict:
                return .strict
            case .custom:
                return .custom
            case .off:
                return .off
            default:
                return nil
            }
        }
    }
    
    private struct Exception {
        let host: String
        let permissions: [ContentPermission]
    }
    
    private var displayedProtectionLevel = Prefs.TrackingProtectionPreferences.level
    private let globalPrivacyControlSwitch = UISwitch()
    private weak var protectionDetailsFooter: UIControl?
    private weak var protectionDetailsLabel: UILabel?
    private var exceptions: [Exception] = []
    
    private var displayedRows: [Row] {
        return displayedRows(for: displayedProtectionLevel)
    }
    
    private func displayedRows(for protectionLevel: TrackingProtectionLevel) -> [Row] {
        var rows: [Row] = [.standard, .strict]
        if protectionLevel == .strict {
            rows.append(contentsOf: [.strictBaselineAllowList, .strictConvenienceAllowList])
        }
        rows.append(.custom)
        if protectionLevel == .custom {
            rows.append(contentsOf: [
                .customBaselineAllowList,
                .customConvenienceAllowList,
                .customCookies,
                .customTrackingContent,
                .customCryptominers,
                .customKnownFingerprinters,
                .customRedirectTrackers,
                .customSuspectedFingerprinters,
            ])
        }
        rows.append(.off)
        return rows
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Tracking Protection", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.estimatedSectionFooterHeight = 44
        globalPrivacyControlSwitch.isOn = Prefs.TrackingProtectionPreferences.globalPrivacyControlEnabled
        globalPrivacyControlSwitch.addTarget(self, action: #selector(globalPrivacyControlSwitchDidChange), for: .valueChanged)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        Task { [weak self] in
            await self?.loadExceptions()
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return displayedProtectionLevel != .off && !exceptions.isEmpty ? 3 : 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return displayedRows.count
        case 1:
            return 1
        case 2:
            return exceptions.count
        default:
            return 0
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        if section == 2 {
            return SettingsSectionText(headerTitle: NSLocalizedString("Exceptions", comment: ""))
        }
        return section == 0
        ? SettingsSectionText(headerTitle: NSLocalizedString("Enhanced Tracking Protection", comment: ""))
        : SettingsSectionText()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath == IndexPath(row: 0, section: 1) {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Tell Websites Not to Share & Sell Data", tableName: "SettingsLocalizable", comment: "")
            cell.textLabel?.numberOfLines = 0
            cell.accessoryView = globalPrivacyControlSwitch
            cell.selectionStyle = .none
            return cell
        }
        if indexPath.section == 2, exceptions.indices.contains(indexPath.row) {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = exceptions[indexPath.row].host
            cell.selectionStyle = .none
            return cell
        }
        guard indexPath.section == 0, displayedRows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch displayedRows[indexPath.row] {
        case .standard:
            return protectionLevelCell(
                title: NSLocalizedString("Standard", tableName: "SettingsLocalizable", comment: ""),
                description: NSLocalizedString("Pages will load normally, but block fewer trackers.", tableName: "SettingsLocalizable", comment: ""),
                protectionLevel: .standard
            )
        case .strict:
            return protectionLevelCell(
                title: NSLocalizedString("Strict", tableName: "SettingsLocalizable", comment: ""),
                description: NSLocalizedString("Stronger tracking protection and faster performance, but some websites may not work properly.", tableName: "SettingsLocalizable", comment: ""),
                protectionLevel: .strict
            )
        case .strictBaselineAllowList:
            return togglePreferenceCell(
                title: NSLocalizedString("Fix Major Website Issues", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.strictBaselineAllowListEnabled,
                isEnabled: true
            )
        case .strictConvenienceAllowList:
            return togglePreferenceCell(
                title: NSLocalizedString("Fix Minor Website Issues", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.strictConvenienceAllowListEnabled,
                isEnabled: Prefs.TrackingProtectionPreferences.strictBaselineAllowListEnabled
            )
        case .custom:
            return protectionLevelCell(
                title: NSLocalizedString("Custom", tableName: "SettingsLocalizable", comment: ""),
                description: NSLocalizedString("Choose which trackers and scripts to block.", tableName: "SettingsLocalizable", comment: ""),
                protectionLevel: .custom
            )
        case .customBaselineAllowList:
            return togglePreferenceCell(
                title: NSLocalizedString("Fix Major Website Issues", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.customBaselineAllowListEnabled,
                isEnabled: true
            )
        case .customConvenienceAllowList:
            return togglePreferenceCell(
                title: NSLocalizedString("Fix Minor Website Issues", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.customConvenienceAllowListEnabled,
                isEnabled: Prefs.TrackingProtectionPreferences.customBaselineAllowListEnabled
            )
        case .customCookies:
            return customChoiceCell(
                title: NSLocalizedString("Cookies", tableName: "SettingsLocalizable", comment: ""),
                selection: CustomTrackingProtectionOption.cookies.selectedOptionTitle
            )
        case .customTrackingContent:
            return customChoiceCell(
                title: NSLocalizedString("Tracking Content", tableName: "SettingsLocalizable", comment: ""),
                selection: CustomTrackingProtectionOption.trackingContent.selectedOptionTitle
            )
        case .customCryptominers:
            return togglePreferenceCell(
                title: NSLocalizedString("Cryptominers", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.customBlocksCryptominers,
                isEnabled: true
            )
        case .customKnownFingerprinters:
            return togglePreferenceCell(
                title: NSLocalizedString("Known Fingerprinters", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.customBlocksKnownFingerprinters,
                isEnabled: true
            )
        case .customRedirectTrackers:
            return togglePreferenceCell(
                title: NSLocalizedString("Redirect Trackers", tableName: "SettingsLocalizable", comment: ""),
                description: nil,
                isChecked: Prefs.TrackingProtectionPreferences.customBlocksRedirectTrackers,
                isEnabled: true
            )
        case .customSuspectedFingerprinters:
            return customChoiceCell(
                title: NSLocalizedString("Suspected Fingerprinters", tableName: "SettingsLocalizable", comment: ""),
                selection: CustomTrackingProtectionOption.suspectedFingerprinters.selectedOptionTitle
            )
        case .off:
            return protectionLevelCell(title: NSLocalizedString("No Protection", comment: ""), description: nil, protectionLevel: .off)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard indexPath.section == 0, displayedRows.indices.contains(indexPath.row) else {
            return
        }
        
        switch displayedRows[indexPath.row] {
        case .standard:
            selectProtectionLevel(.standard)
        case .strict:
            selectProtectionLevel(.strict)
        case .strictBaselineAllowList:
            Prefs.TrackingProtectionPreferences.strictBaselineAllowListEnabled.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .strictConvenienceAllowList:
            guard Prefs.TrackingProtectionPreferences.strictBaselineAllowListEnabled else {
                return
            }
            Prefs.TrackingProtectionPreferences.strictConvenienceAllowListEnabled.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .custom:
            selectProtectionLevel(.custom)
        case .customBaselineAllowList:
            Prefs.TrackingProtectionPreferences.customBaselineAllowListEnabled.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .customConvenienceAllowList:
            guard Prefs.TrackingProtectionPreferences.customBaselineAllowListEnabled else {
                return
            }
            Prefs.TrackingProtectionPreferences.customConvenienceAllowListEnabled.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .customCookies:
            showCustomOption(.cookies)
        case .customTrackingContent:
            showCustomOption(.trackingContent)
        case .customCryptominers:
            Prefs.TrackingProtectionPreferences.customBlocksCryptominers.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .customKnownFingerprinters:
            Prefs.TrackingProtectionPreferences.customBlocksKnownFingerprinters.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .customRedirectTrackers:
            Prefs.TrackingProtectionPreferences.customBlocksRedirectTrackers.toggle()
            applyEnhancedTrackingProtectionAndReloadTabs()
            tableView.reloadData()
        case .customSuspectedFingerprinters:
            showCustomOption(.suspectedFingerprinters)
        case .off:
            selectProtectionLevel(.off)
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2, exceptions.indices.contains(indexPath.row) else {
            return nil
        }
        let clearAction = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Clear", comment: "Swipe action")
        ) { [weak self] _, _, completion in
            guard let self, self.exceptions.indices.contains(indexPath.row) else {
                completion(false)
                return
            }
            let exception = self.exceptions.remove(at: indexPath.row)
            for permission in exception.permissions {
                PermissionDelegate.setPermission(permission, value: .deny)
            }
            self.reloadAllTabs()
            if self.exceptions.isEmpty {
                tableView.deleteSections(IndexSet(integer: 2), with: .fade)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [clearAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0 else {
            return nil
        }
        
        guard let title = protectionDetailsTitle(for: Prefs.TrackingProtectionPreferences.level) else {
            return nil
        }
        
        let footer = UIControl()
        footer.addTarget(self, action: #selector(showProtectionDetails), for: .touchUpInside)
        footer.isAccessibilityElement = true
        footer.accessibilityLabel = title
        footer.accessibilityTraits = .link
        protectionDetailsFooter = footer
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = view.tintColor
        label.numberOfLines = 0
        label.text = title
        protectionDetailsLabel = label
        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: UX.footerHorizontalPadding),
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -UX.footerHorizontalPadding),
            label.topAnchor.constraint(equalTo: footer.topAnchor, constant: UX.footerVerticalPadding),
            label.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -UX.footerVerticalPadding),
        ])
        return footer
    }
    
    private func protectionDetailsTitle(for protectionLevel: TrackingProtectionLevel) -> String? {
        let protectionName: String
        switch protectionLevel {
        case .standard:
            protectionName = NSLocalizedString("Standard", tableName: "SettingsLocalizable", comment: "")
        case .strict:
            protectionName = NSLocalizedString("Strict", tableName: "SettingsLocalizable", comment: "")
        case .custom:
            protectionName = NSLocalizedString("Custom", tableName: "SettingsLocalizable", comment: "")
        case .off:
            return nil
        }

        return String(
            format: NSLocalizedString("Learn more about %@ Protection...", comment: "Protection name placeholder"),
            protectionName
        )
    }
    
    private func protectionLevelCell(title: String, description: String?, protectionLevel: TrackingProtectionLevel) -> UITableViewCell {
        let cell = UITableViewCell(style: description == nil ? .default : .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = description
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = protectionLevel == Prefs.TrackingProtectionPreferences.level ? .checkmark : .none
        return cell
    }
    
    private func togglePreferenceCell(title: String, description: String?, isChecked: Bool, isEnabled: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: description == nil ? .default : .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.isEnabled = isEnabled
        cell.detailTextLabel?.text = description
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.isEnabled = isEnabled
        cell.detailTextLabel?.numberOfLines = 0
        cell.indentationLevel = UX.optionIndentationLevel
        cell.accessoryType = isChecked ? .checkmark : .none
        cell.selectionStyle = isEnabled ? .default : .none
        return cell
    }
    
    private func customChoiceCell(title: String, selection: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = selection
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.indentationLevel = UX.optionIndentationLevel
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    private func selectProtectionLevel(_ protectionLevel: TrackingProtectionLevel) {
        guard Prefs.TrackingProtectionPreferences.level != protectionLevel else {
            return
        }
        Prefs.TrackingProtectionPreferences.level = protectionLevel
        applyEnhancedTrackingProtectionAndReloadTabs()
        
        let protectionDetailsTitle = protectionDetailsTitle(for: protectionLevel)
        protectionDetailsFooter?.accessibilityLabel = protectionDetailsTitle
        protectionDetailsFooter?.isHidden = protectionDetailsTitle == nil
        protectionDetailsLabel?.text = protectionDetailsTitle
        
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard displayedRows.indices.contains(indexPath.row) else {
                continue
            }
            if let rowProtectionLevel = displayedRows[indexPath.row].protectionLevel {
                tableView.cellForRow(at: indexPath)?.accessoryType = rowProtectionLevel == protectionLevel ? .checkmark : .none
            }
        }
        
        let previousRows = displayedRows
        let showedExceptions = displayedProtectionLevel != .off && !exceptions.isEmpty
        let showsExceptions = protectionLevel != .off && !exceptions.isEmpty
        let updatedRows = displayedRows(for: protectionLevel)
        let deletedIndexPaths = previousRows.enumerated().compactMap { index, row in
            return updatedRows.contains(row) ? nil : IndexPath(row: index, section: 0)
        }
        let insertedIndexPaths = updatedRows.enumerated().compactMap { index, row in
            return previousRows.contains(row) ? nil : IndexPath(row: index, section: 0)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.tableView.performBatchUpdates {
                self.displayedProtectionLevel = protectionLevel
                if showedExceptions, !showsExceptions {
                    self.tableView.deleteSections(IndexSet(integer: 2), with: .fade)
                } else if !showedExceptions, showsExceptions {
                    self.tableView.insertSections(IndexSet(integer: 2), with: .fade)
                }
                self.tableView.deleteRows(at: deletedIndexPaths, with: .automatic)
                self.tableView.insertRows(at: insertedIndexPaths, with: .automatic)
            }
        }
    }
    
    @MainActor
    private func loadExceptions() async {
        let permissions = (try? await PermissionDelegate.allPermissions()) ?? []
        let trackingPermissions = permissions.compactMap { permission -> (String, ContentPermission)? in
            guard permission.permission == .tracking,
                  permission.value == .allow,
                  let host = URL(string: permission.uri)?.host else {
                return nil
            }
            return (host, permission)
        }
        exceptions = Dictionary(grouping: trackingPermissions, by: \.0)
            .map { Exception(host: $0.key, permissions: $0.value.map(\.1)) }
            .sorted { $0.host < $1.host }
        UIView.performWithoutAnimation {
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
    }
    
    private func showCustomOption(_ option: CustomTrackingProtectionOption) {
        let destination = CustomTrackingProtectionOptionViewController(option: option) { [weak self] in
            self?.applyEnhancedTrackingProtectionAndReloadTabs()
        }
        navigationController?.pushViewController(destination, animated: true)
    }
    
    private func applyEnhancedTrackingProtectionAndReloadTabs() {
        TrackingProtectionPolicyController.applyEnhancedTrackingProtection()
        reloadAllTabs()
    }
    
    private func reloadAllTabs() {
        guard let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self) else {
            return
        }
        for tab in browserViewController.tabManager.regularTabs + browserViewController.tabManager.privateTabs {
            tab.session.reload()
        }
    }
    
    @objc private func globalPrivacyControlSwitchDidChange(_ sender: UISwitch) {
        Prefs.TrackingProtectionPreferences.globalPrivacyControlEnabled = sender.isOn
        TrackingProtectionPolicyController.applyGlobalPrivacyControl()
        reloadAllTabs()
    }
    
    @objc private func showProtectionDetails() {
        guard Prefs.TrackingProtectionPreferences.level != .off else {
            return
        }
        let details = TrackingProtectionDetailsViewController(protectionLevel: Prefs.TrackingProtectionPreferences.level)
        let navigationController = UINavigationController(rootViewController: details)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}
