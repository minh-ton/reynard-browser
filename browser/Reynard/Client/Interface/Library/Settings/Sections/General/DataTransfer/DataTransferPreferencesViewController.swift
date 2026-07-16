//
//  DataTransferPreferencesViewController.swift
//  Reynard
//

import UIKit
import UniformTypeIdentifiers

final class DataTransferPreferencesViewController: SettingsTableViewController, UIDocumentPickerDelegate {
    private let launchStore: ReynardDataTransferLaunchStore
    private let policy = DataTransferSettingsPolicy()

    init(
        launchStore: ReynardDataTransferLaunchStore = .shared
    ) {
        self.launchStore = launchStore
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Import/Backup Data", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        actions(in: section).count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let action = action(at: indexPath) else {
            return UITableViewCell()
        }

        let cell = SettingsViewUtils.actionCell(
            title: title(for: action),
            tintColor: nil
        )
        let enabled = policy.isEnabled(
            action,
            hasPendingOperation: launchStore.pendingOperation() != nil
        )
        cell.selectionStyle = enabled ? .default : .none
        if !enabled {
            cell.textLabel?.textColor = .secondaryLabel
            cell.accessibilityTraits.insert(.notEnabled)
        }
        cell.accessibilityHint = enabled
            ? accessibilityHint(for: action)
            : NSLocalizedString("A Reynard data action is already pending.", comment: "")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let action = action(at: indexPath),
              policy.isEnabled(
                action,
                hasPendingOperation: launchStore.pendingOperation() != nil
              ) else {
            return
        }

        switch action {
        case .export:
            confirmExport()
        case .importBackup:
            presentImportPicker()
        }
    }

    override func sectionText(for section: Int) -> SettingsSectionText {
        guard section == 0 else {
            return SettingsSectionText()
        }
        let hasPendingOperation = launchStore.pendingOperation() != nil
        if hasPendingOperation {
            return SettingsSectionText(footerTitle: NSLocalizedString(
                "A Reynard data action is waiting. Close and reopen Reynard to continue.",
                comment: ""
            ))
        }
        return SettingsSectionText(footerTitle: NSLocalizedString(
            "Reynard closes the browser engine during export and restore so your backup stays consistent.",
            comment: ""
        ))
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let sourceURL = urls.first else { return }
        prepareImport(from: sourceURL)
    }

    private func actions(in section: Int) -> [DataTransferSettingsPolicy.Action] {
        section == 0 ? policy.actions : []
    }

    private func action(at indexPath: IndexPath) -> DataTransferSettingsPolicy.Action? {
        let sectionActions = actions(in: indexPath.section)
        guard sectionActions.indices.contains(indexPath.row) else { return nil }
        return sectionActions[indexPath.row]
    }

    private func title(for action: DataTransferSettingsPolicy.Action) -> String {
        switch action {
        case .export:
            return NSLocalizedString("Export", comment: "")
        case .importBackup:
            return NSLocalizedString("Import", comment: "")
        }
    }

    private func accessibilityHint(for action: DataTransferSettingsPolicy.Action) -> String {
        switch action {
        case .export:
            return NSLocalizedString("Prepares a backup on the next launch.", comment: "")
        case .importBackup:
            return NSLocalizedString("Choose a Reynard backup to restore on the next launch.", comment: "")
        }
    }

    private func confirmExport() {
        let alert = UIAlertController(
            title: NSLocalizedString("Export Reynard Data", comment: ""),
            message: NSLocalizedString(
                "Reynard must reopen without the browser engine to make a consistent backup.",
                comment: ""
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Prepare Backup", comment: ""),
            style: .default
        ) { [weak self] _ in
            self?.schedule(.export)
        })
        present(alert, animated: true)
    }

    private func presentImportPicker() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            guard let backupType = UTType("com.minh-ton.reynard.backup") else { return }
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [backupType],
                asCopy: true
            )
        } else {
            picker = UIDocumentPickerViewController(
                documentTypes: ["com.minh-ton.reynard.backup"],
                in: .import
            )
        }
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    private func prepareImport(from sourceURL: URL) {
        let alert = workingAlert()
        present(alert, animated: true) {
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("Copying and checking the selected backup…", comment: "")
            )
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try Self.copyPendingImport(from: sourceURL) }
                DispatchQueue.main.async { [weak self, weak alert] in
                    guard let self else { return }
                    alert?.dismiss(animated: true) {
                        switch result {
                        case let .success(prepared):
                            guard self.launchStore.schedule(
                                .importBackup(bookmarkData: prepared.bookmarkData)
                            ) else {
                                try? FileManager.default.removeItem(at: prepared.packageURL)
                                self.showPendingOperationMessage()
                                return
                            }
                            self.tableView.reloadData()
                            self.showReopenMessage(NSLocalizedString(
                                "Close and reopen Reynard to restore the selected backup.",
                                comment: ""
                            ))
                        case let .failure(error):
                            self.showImportError(error)
                        }
                    }
                }
            }
        }
    }

    private static func copyPendingImport(from sourceURL: URL) throws -> (
        packageURL: URL,
        bookmarkData: Data
    ) {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let pendingRoot = ReynardDirectories.shared.temporary
            .appendingPathComponent("PendingImport", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let destination = pendingRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("reynardbackup")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            _ = try ReynardPendingImportPreflight().validate(at: destination)
            let bookmarkData = try destination.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return (destination, bookmarkData)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func workingAlert() -> UIAlertController {
        let alert = UIAlertController(
            title: NSLocalizedString("Preparing Import", comment: ""),
            message: NSLocalizedString("Copying and checking the selected backup…", comment: "") + "\n\n",
            preferredStyle: .alert
        )
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -18),
        ])
        return alert
    }

    private func schedule(_ operation: ReynardDataTransferOperation) {
        guard launchStore.schedule(operation) else {
            showPendingOperationMessage()
            return
        }
        tableView.reloadData()
        let message: String
        switch operation {
        case .export:
            message = NSLocalizedString("Close and reopen Reynard to prepare the backup.", comment: "")
        case .importBackup:
            return
        }
        showReopenMessage(message)
    }

    private func showPendingOperationMessage() {
        showMessage(
            title: NSLocalizedString("Data Action Already Pending", comment: ""),
            message: NSLocalizedString(
                "Close and reopen Reynard to finish the waiting data action first.",
                comment: ""
            )
        )
    }

    private func showReopenMessage(_ message: String) {
        showMessage(title: NSLocalizedString("Ready for Next Launch", comment: ""), message: message)
    }

    private func showImportError(_ error: Error) {
        let message: String
        if let transferError = error as? ReynardDataTransferError,
           transferError == .unsupportedVersion {
            message = NSLocalizedString("This backup version isn’t supported.", comment: "")
        } else {
            message = NSLocalizedString("The selected file is not a valid Reynard backup.", comment: "")
        }
        showMessage(title: NSLocalizedString("Couldn’t Prepare Import", comment: ""), message: message)
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
