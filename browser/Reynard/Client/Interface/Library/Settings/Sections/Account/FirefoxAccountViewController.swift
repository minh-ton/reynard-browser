//
//  FirefoxAccountViewController.swift
//  Reynard
//
//  Account details, Sync status, per-engine toggles and sign out.
//

import UIKit

final class FirefoxAccountViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case account
        case engines
        case device
        case signOut
    }

    private enum AccountRow {
        case profile
        case reauthenticate
        case syncNow
    }

    private let engines: [(engine: SyncPreferences.Engine, title: String)] = [
        (.tabs, NSLocalizedString("Open Tabs", comment: "")),
        (.history, NSLocalizedString("History", comment: "")),
        (.bookmarks, NSLocalizedString("Bookmarks", comment: "")),
    ]

    private var accountRows: [AccountRow] {
        FxAAccountManager.shared.needsReauthentication
            ? [.profile, .reauthenticate]
            : [.profile, .syncNow]
    }

    private static let relativeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func statusText() -> String {
        let accounts = FxAAccountManager.shared
        if accounts.needsReauthentication {
            return NSLocalizedString("Sign in again to resume syncing", comment: "")
        }
        if SyncManager.shared.isSyncing {
            return NSLocalizedString("Syncing…", comment: "")
        }
        if let error = SyncPreferences.lastSyncError, !error.isEmpty {
            return NSLocalizedString("Last sync had problems", comment: "")
        }
        if let date = SyncPreferences.lastSyncDate {
            return String(
                format: NSLocalizedString("Last synced %@", comment: ""),
                relativeFormatter.string(from: date)
            )
        }
        return NSLocalizedString("Not synced yet", comment: "")
    }

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Mozilla Account", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        for name in [Notification.Name.fxaAccountStateDidChange, .syncStatusDidChange] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(stateDidChange),
                name: name,
                object: nil
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func stateDidChange() {
        guard FxAAccountManager.shared.isSignedIn else {
            navigationController?.popViewController(animated: true)
            return
        }
        tableView.reloadData()
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section.allCases[section] {
        case .account:
            return accountRows.count
        case .engines:
            return engines.count
        case .device:
            return 1
        case .signOut:
            return 1
        }
    }

    override func sectionText(for section: Int) -> SettingsSectionText {
        switch Section.allCases[section] {
        case .account:
            return SettingsSectionText(
                headerTitle: NSLocalizedString("Account", comment: ""),
                footerTitle: SyncPreferences.lastSyncError.flatMap { $0.isEmpty ? nil : $0 }
            )
        case .engines:
            return SettingsSectionText(
                headerTitle: NSLocalizedString("Sync", comment: ""),
                footerTitle: NSLocalizedString("History syncs both ways. Bookmarks from Firefox appear in a “Firefox Bookmarks” folder that is refreshed on every sync; changes you make inside that folder aren't sent back to Firefox.", comment: "")
            )
        case .device:
            return SettingsSectionText(
                headerTitle: NSLocalizedString("This Device", comment: ""),
                footerTitle: NSLocalizedString("The name your other Firefox browsers show for this device.", comment: "")
            )
        case .signOut:
            return SettingsSectionText()
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let accounts = FxAAccountManager.shared
        switch Section.allCases[indexPath.section] {
        case .account:
            switch accountRows[indexPath.row] {
            case .profile:
                let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.textLabel?.text = accounts.account?.displayName ?? accounts.account?.email
                    ?? NSLocalizedString("Mozilla Account", comment: "")
                var detail = Self.statusText()
                if accounts.account?.displayName != nil, let email = accounts.account?.email {
                    detail = email + "\n" + detail
                }
                cell.detailTextLabel?.text = detail
                cell.detailTextLabel?.numberOfLines = 0
                cell.detailTextLabel?.textColor = accounts.needsReauthentication ? .systemRed : .secondaryLabel
                cell.selectionStyle = .none
                return cell
            case .reauthenticate:
                return SettingsViewUtils.actionCell(
                    title: NSLocalizedString("Sign In Again", comment: ""),
                    tintColor: view.tintColor
                )
            case .syncNow:
                let cell = SettingsViewUtils.actionCell(
                    title: SyncManager.shared.isSyncing
                        ? NSLocalizedString("Syncing…", comment: "")
                        : NSLocalizedString("Sync Now", comment: ""),
                    tintColor: SyncManager.shared.isSyncing ? .secondaryLabel : view.tintColor
                )
                return cell
            }

        case .engines:
            let item = engines[indexPath.row]
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = item.title
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = SyncPreferences.isEnabled(item.engine)
            toggle.tag = indexPath.row
            toggle.addTarget(self, action: #selector(engineToggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            return cell

        case .device:
            let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Device Name", comment: "")
            cell.detailTextLabel?.text = SyncPreferences.deviceName
            cell.accessoryType = .disclosureIndicator
            return cell

        case .signOut:
            let cell = SettingsViewUtils.actionCell(
                title: NSLocalizedString("Sign Out", comment: ""),
                tintColor: .systemRed
            )
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        switch Section.allCases[indexPath.section] {
        case .account:
            switch accountRows[indexPath.row] {
            case .profile:
                break
            case .reauthenticate:
                FxASignInLauncher.start(from: self)
            case .syncNow:
                SyncManager.shared.requestSync(reason: .user)
                tableView.reloadData()
            }
        case .engines:
            break
        case .device:
            presentDeviceNameEditor()
        case .signOut:
            confirmSignOut(sourceView: tableView.cellForRow(at: indexPath))
        }
    }

    // MARK: - Actions

    @objc private func engineToggleChanged(_ sender: UISwitch) {
        guard engines.indices.contains(sender.tag) else {
            return
        }
        let engine = engines[sender.tag].engine
        SyncPreferences.setEnabled(sender.isOn, for: engine)
        if sender.isOn {
            SyncManager.shared.requestSync(reason: .user)
        } else if engine == .bookmarks {
            BookmarkStore.shared.removeSyncedBookmarks()
            SyncPreferences.setLastModified(0, for: "bookmarks")
        }
    }

    private func presentDeviceNameEditor() {
        let alert = UIAlertController(
            title: NSLocalizedString("Device Name", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = SyncPreferences.deviceName
            textField.placeholder = SyncPreferences.defaultDeviceName
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                await FxAAccountManager.shared.updateDeviceName(name.isEmpty ? SyncPreferences.defaultDeviceName : name)
                self?.tableView.reloadData()
            }
        })
        present(alert, animated: true)
    }

    private func confirmSignOut(sourceView: UIView?) {
        let sheet = UIAlertController(
            title: NSLocalizedString("Sign Out?", comment: ""),
            message: NSLocalizedString("Reynard will stop syncing and remove the “Firefox Bookmarks” folder. Your history stays on this device.", comment: ""),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Sign Out", comment: ""), style: .destructive) { _ in
            Task { @MainActor in
                await FxAAccountManager.shared.signOut()
            }
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(sheet, animated: true)
    }
}
