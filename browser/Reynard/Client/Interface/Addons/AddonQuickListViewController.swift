//
//  AddonQuickListViewController.swift
//  Reynard
//

import UIKit
import GeckoView
import UniformTypeIdentifiers
import MobileCoreServices

final class AddonQuickListViewController: UITableViewController, UIDocumentPickerDelegate {
    private enum Section: Int, CaseIterable {
        case addons
        case management
    }

    private enum ManagementAction: Int, CaseIterable {
        case discover
        case installFromFile
        case updateAll
    }

    private let itemProvider: () -> [AddressBarMenu.AddonItem]
    private let onSelect: (AddonMenuItem, UIViewController) -> Void
    private let onUninstall: (Addon) -> Void
    private let onDiscover: (UIViewController) -> Void
    private let onInstallFromFile: (URL) async throws -> Void
    private let onUpdateAll: () async -> AddonUpdateBatchResult
    private var items: [AddressBarMenu.AddonItem] = []
    private var isInstalling = false
    private var isUpdating = false
    private var openingIndexPath: IndexPath?
    private let selectionFeedback = UIImpactFeedbackGenerator(style: .light)

    init(
        itemProvider: @escaping () -> [AddressBarMenu.AddonItem],
        onSelect: @escaping (AddonMenuItem, UIViewController) -> Void,
        onUninstall: @escaping (Addon) -> Void,
        onDiscover: @escaping (UIViewController) -> Void,
        onInstallFromFile: @escaping (URL) async throws -> Void,
        onUpdateAll: @escaping () async -> AddonUpdateBatchResult
    ) {
        self.itemProvider = itemProvider
        self.onSelect = onSelect
        self.onUninstall = onUninstall
        self.onDiscover = onDiscover
        self.onInstallFromFile = onInstallFromFile
        self.onUpdateAll = onUpdateAll
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Add-ons", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "AddonQuickList"
        tableView.accessibilityIdentifier = "AddonQuickList.Table"
        clearsSelectionOnViewWillAppear = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        tableView.keyboardDismissMode = .onDrag
        selectionFeedback.prepare()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadItems),
            name: .addonRuntimeDidChange,
            object: nil
        )
        reloadItems()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    @objc private func reloadItems() {
        items = itemProvider()
        tableView.reloadData()
        backgroundViewForCurrentState()
    }

    private func backgroundViewForCurrentState() {
        guard items.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let label = UILabel()
        label.text = NSLocalizedString("No add-ons are available for this page.", comment: "")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "AddonQuickList.EmptyState"
        tableView.backgroundView = label
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .addons:
            return items.count
        case .management:
            return ManagementAction.allCases.count
        case nil:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isManagement = indexPath.section == Section.management.rawValue
        let identifier = isManagement ? "AddonQuickListManagementCell" : "AddonQuickListItemCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        guard !isManagement else {
            configureManagementCell(cell, at: indexPath)
            return cell
        }
        guard items.indices.contains(indexPath.row) else { return cell }
        let item = items[indexPath.row]
        cell.textLabel?.text = item.menuItem.title
        cell.detailTextLabel?.text = item.menuItem.addon.metaData.name
        cell.imageView?.image = item.image
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.accessibilityIdentifier = "AddonQuickList.Item.\(item.menuItem.addon.id)"
        cell.accessibilityHint = NSLocalizedString(
            "Double tap to open. Swipe up or down for available actions.",
            comment: ""
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == Section.management.rawValue {
            tableView.deselectRow(at: indexPath, animated: true)
            performManagementAction(at: indexPath)
            return
        }
        guard items.indices.contains(indexPath.row) else { return }
        guard openingIndexPath == nil else { return }
        openingIndexPath = indexPath
        selectionFeedback.impactOccurred()
        selectionFeedback.prepare()
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.accessibilityLabel = NSLocalizedString("Loading Add-on", comment: "")
        spinner.startAnimating()
        tableView.cellForRow(at: indexPath)?.accessoryView = spinner
        tableView.isUserInteractionEnabled = false
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect(items[indexPath.row].menuItem, self)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == Section.addons.rawValue else { return nil }
        guard items.indices.contains(indexPath.row) else { return nil }
        let addon = items[indexPath.row].menuItem.addon
        guard !addon.isBuiltIn else { return nil }
        let uninstall = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Uninstall", comment: "")
        ) { [weak self] _, _, completion in
            self?.onUninstall(addon)
            completion(true)
        }
        uninstall.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [uninstall])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func configureManagementCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let action = ManagementAction(rawValue: indexPath.row) else { return }
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none
        cell.textLabel?.textColor = view.tintColor
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .default
        cell.accessibilityHint = nil
        switch action {
        case .discover:
            cell.textLabel?.text = NSLocalizedString("Discover Add-ons…", comment: "")
            cell.imageView?.image = UIImage(systemName: "safari")
        case .installFromFile:
            cell.textLabel?.text = isInstalling
                ? NSLocalizedString("Installing Add-on…", comment: "")
                : NSLocalizedString("Install Add-on from File…", comment: "")
            cell.imageView?.image = UIImage(systemName: "folder")
            cell.selectionStyle = isInstalling ? .none : .default
        case .updateAll:
            cell.textLabel?.text = isUpdating
                ? NSLocalizedString("Checking for Updates…", comment: "")
                : NSLocalizedString("Update All Add-ons", comment: "")
            cell.imageView?.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            cell.selectionStyle = isUpdating ? .none : .default
        }
        cell.accessibilityIdentifier = "AddonQuickList.Management.\(action)"
    }

    private func performManagementAction(at indexPath: IndexPath) {
        guard let action = ManagementAction(rawValue: indexPath.row) else { return }
        switch action {
        case .discover:
            onDiscover(self)
        case .installFromFile:
            guard !isInstalling else { return }
            presentDocumentPicker()
        case .updateAll:
            guard !isUpdating else { return }
            updateAllAddons()
        }
    }

    private func presentDocumentPicker() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [UTType(importedAs: "org.mozilla.xpi-extension"), .zip],
                asCopy: true
            )
        } else {
            picker = UIDocumentPickerViewController(
                documentTypes: ["org.mozilla.xpi-extension", kUTTypeZipArchive as String],
                in: .import
            )
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        isInstalling = true
        tableView.reloadSections(IndexSet(integer: Section.management.rawValue), with: .none)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await onInstallFromFile(url)
                await MainActor.run {
                    self.isInstalling = false
                    self.reloadItems()
                }
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.tableView.reloadSections(IndexSet(integer: Section.management.rawValue), with: .none)
                    let presentation = AddonErrorPresenter.installErrorPresentation(
                        for: error,
                        addonName: url.deletingPathExtension().lastPathComponent
                    )
                    if !presentation.isUserCancelled {
                        AlertPresenter.show(title: nil, message: presentation.alertMessage)
                    }
                }
            }
        }
    }

    private func updateAllAddons() {
        isUpdating = true
        tableView.reloadSections(IndexSet(integer: Section.management.rawValue), with: .none)
        Task { [weak self] in
            guard let self else { return }
            let result = await onUpdateAll()
            await MainActor.run {
                self.isUpdating = false
                self.reloadItems()
                AlertPresenter.show(title: nil, message: self.updateSummary(for: result))
            }
        }
    }

    private func updateSummary(for result: AddonUpdateBatchResult) -> String {
        var parts: [String] = []
        if result.updatedCount > 0 {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("%lld add-ons updated.", comment: "Update count"),
                Int64(result.updatedCount)
            ))
        }
        if result.pendingApprovalCount > 0 {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("%lld add-ons need permission.", comment: "Update count"),
                Int64(result.pendingApprovalCount)
            ))
        }
        if result.failedCount > 0 {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("%lld updates failed.", comment: "Update count"),
                Int64(result.failedCount)
            ))
        }
        return parts.isEmpty
            ? NSLocalizedString("No updates found.", comment: "")
            : parts.joined(separator: " ")
    }
}
