//
//  AddonsPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

final class AddonsPreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let iconSize = CGSize(width: 24, height: 24)
        static let disabledIconAlpha: CGFloat = 0.5
    }
    
    private enum Section {
        case installed
        case unsupported
        case more
        
        var text: SettingsSectionText {
            switch self {
            case .installed:
                return SettingsSectionText(headerTitle: "Installed Add-ons")
            case .unsupported:
                return SettingsSectionText(headerTitle: "Unsupported Add-ons")
            case .more:
                return SettingsSectionText()
            }
        }
    }
    
    private enum MoreRow: CaseIterable {
        case discover
        case installFromFile
        case updateAll
    }
    
    private static let sharedIconCache = NSCache<NSString, UIImage>()
    private static var hasLoadedInstalledAddons = false
    
    private let iconLoadingQueue = DispatchQueue(label: "com.minh-ton.Reynard.AddonsPreferencesViewController.IconLoadingQueue", qos: .utility)
    private var loadingIconIDs = Set<String>()
    private var installedAddons: [Addon] = []
    private var unsupportedAddons: [Addon] = []
    private var addonStatusTextByID: [String: String] = [:]
    private var updateFooterMessage: String?
    private var isLoadingAddons = false
    private var isInstallingAddonFromFile = false
    private var isCheckingForAddonUpdates = false
    private let lastCheckedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private var displayedSections: [Section] {
        var sections: [Section] = [.installed]
        if !unsupportedAddons.isEmpty {
            sections.append(.unsupported)
        }
        sections.append(.more)
        return sections
    }
    
    private var listedAddonCount: Int {
        return installedAddons.count + unsupportedAddons.count
    }
    
    private var canCheckForAddonUpdates: Bool {
        return listedAddonCount > 0
    }
    
    private var displayedMoreRows: [MoreRow] {
        return canCheckForAddonUpdates ? MoreRow.allCases : [.discover, .installFromFile]
    }
    
    private var addonUpdateActionTitle: String {
        if isCheckingForAddonUpdates {
            return "Updating Add-ons..."
        }
        if let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self),
           browserViewController.addonCoordinator.updateCoordinator.hasPendingApprovals {
            return "Complete Add-on Updates"
        }
        return "Update All Add-ons"
    }
    
    // MARK: - Lifecycle
    
    init() {
        super.init(style: .insetGrouped)
        title = "Add-ons"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Self.sharedIconCache.countLimit = 64
        loadCachedAddons()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        LibrarySharedUtils.resolvedBrowserViewController(from: self)?.addonCoordinator.updateCoordinator.setSettingsVisible(true)
        clearUpdateStatus()
        loadCachedAddons()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        LibrarySharedUtils.resolvedBrowserViewController(from: self)?.addonCoordinator.updateCoordinator.setSettingsVisible(false)
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
        case .installed:
            return installedAddons.isEmpty ? 1 : installedAddons.count
        case .unsupported:
            return unsupportedAddons.count
        case .more:
            return displayedMoreRows.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .installed:
            if installedAddons.isEmpty {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.selectionStyle = .none
                cell.textLabel?.text = isLoadingAddons ? "Loading Add-ons..." : "No Add-ons Installed"
                cell.textLabel?.textColor = .secondaryLabel
                return cell
            }
            
            guard installedAddons.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let addon = installedAddons[indexPath.row]
            let statusText = statusText(for: addon)
            let cell = UITableViewCell(style: statusText == nil ? .default : .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = addon.metaData.name ?? addon.id
            cell.detailTextLabel?.text = statusText
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            cell.imageView?.image = Self.sharedIconCache.object(forKey: addon.id as NSString) ?? UIImage(named: "reynard.puzzlepiece.extension")
            applyAvailabilityState(to: cell, for: addon)
            loadIcon(for: addon)
            return cell
        case .unsupported:
            guard unsupportedAddons.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let addon = unsupportedAddons[indexPath.row]
            let statusText = statusText(for: addon) ?? "Unsupported"
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = addon.metaData.name ?? addon.id
            cell.detailTextLabel?.text = statusText
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            cell.imageView?.image = Self.sharedIconCache.object(forKey: addon.id as NSString) ?? UIImage(named: "reynard.puzzlepiece.extension")
            applyAvailabilityState(to: cell, for: addon)
            loadIcon(for: addon)
            return cell
        case .more:
            guard displayedMoreRows.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            switch displayedMoreRows[indexPath.row] {
            case .discover:
                cell.textLabel?.text = "Discover Add-ons..."
                cell.textLabel?.textColor = view.tintColor
            case .installFromFile:
                cell.textLabel?.text = isInstallingAddonFromFile ? "Installing Add-on..." : "Install Add-on From File..."
                cell.textLabel?.textColor = isInstallingAddonFromFile ? .secondaryLabel : view.tintColor
                if isInstallingAddonFromFile {
                    cell.selectionStyle = .none
                }
            case .updateAll:
                cell.textLabel?.text = addonUpdateActionTitle
                cell.textLabel?.textColor = isCheckingForAddonUpdates ? .secondaryLabel : view.tintColor
                if isCheckingForAddonUpdates {
                    cell.selectionStyle = .none
                }
            }
            
            return cell
        }
    }
    
    // MARK: - Table Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch displayedSections[indexPath.section] {
        case .installed, .unsupported:
            guard let addon = addonForSelection(at: indexPath) else {
                return
            }
            navigationController?.pushViewController(
                AddonDetailsPreferencesViewController(addonID: addon.id),
                animated: true
            )
        case .more:
            guard displayedMoreRows.indices.contains(indexPath.row) else {
                return
            }
            switch displayedMoreRows[indexPath.row] {
            case .discover:
                LibrarySharedUtils.openLinkInBrowser("https://addons.mozilla.org/android/", from: self)
            case .installFromFile:
                guard !isInstallingAddonFromFile else {
                    return
                }
                chooseAddonPackage()
            case .updateAll:
                guard !isCheckingForAddonUpdates else {
                    return
                }
                updateAddons()
            }
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        let displayedSection = displayedSections[section]
        switch displayedSection {
        case .installed:
            return installedAddons.isEmpty ? SettingsSectionText() : displayedSection.text
        case .unsupported:
            return unsupportedAddons.isEmpty ? SettingsSectionText() : displayedSection.text
        case .more:
            guard canCheckForAddonUpdates else {
                return displayedSection.text
            }
            if let updateFooterMessage {
                return SettingsSectionText(footerTitle: updateFooterMessage)
            }
            if let lastGlobalCheckAt = Prefs.AddonSettings.lastGlobalCheckAt {
                return SettingsSectionText(
                    footerTitle: "Last checked on \(lastCheckedDateFormatter.string(from: lastGlobalCheckAt))."
                )
            }
            return displayedSection.text
        }
    }
    
    // MARK: - Add-on Loading
    
    private func loadCachedAddons() {
        let visibleAddons = AddonRuntime.shared.installedAddons.filter { !$0.isBuiltIn }
        installedAddons = visibleAddons.filter { !$0.metaData.isUnsupported }
        unsupportedAddons = visibleAddons.filter { $0.metaData.isUnsupported }
        
        if installedAddons.isEmpty && unsupportedAddons.isEmpty && !Self.hasLoadedInstalledAddons {
            guard !isLoadingAddons else {
                return
            }
            isLoadingAddons = true
            tableView.reloadData()
            Task { [weak self] in
                await self?.loadRuntimeAddons()
            }
            return
        }
        
        isLoadingAddons = false
        tableView.reloadData()
    }
    
    private func loadRuntimeAddons() async {
        let refreshedAddons: [Addon]
        do {
            refreshedAddons = try await AddonRuntime.shared.list()
        } catch {
            refreshedAddons = AddonRuntime.shared.installedAddons
        }
        
        await MainActor.run {
            Self.hasLoadedInstalledAddons = true
            let visibleAddons = refreshedAddons.filter { !$0.isBuiltIn }
            self.installedAddons = visibleAddons.filter { !$0.metaData.isUnsupported }
            self.unsupportedAddons = visibleAddons.filter { $0.metaData.isUnsupported }
            self.isLoadingAddons = false
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Selection
    
    private func addonForSelection(at indexPath: IndexPath) -> Addon? {
        guard displayedSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch displayedSections[indexPath.section] {
        case .installed:
            guard !installedAddons.isEmpty,
                  installedAddons.indices.contains(indexPath.row) else {
                return nil
            }
            return installedAddons[indexPath.row]
        case .unsupported:
            guard unsupportedAddons.indices.contains(indexPath.row) else {
                return nil
            }
            return unsupportedAddons[indexPath.row]
        case .more:
            return nil
        }
    }
    
    // MARK: - Installation
    
    private func chooseAddonPackage() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [
                    UTType(importedAs: "org.mozilla.xpi-extension"),
                    .zip,
                ],
                asCopy: true
            )
        } else {
            picker = UIDocumentPickerViewController(
                documentTypes: [
                    "org.mozilla.xpi-extension",
                    kUTTypeZipArchive as String,
                ],
                in: .import
            )
        }
        if #available(iOS 13.0, *) {
            picker.shouldShowFileExtensions = true
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    private func installAddonPackage(from packageURL: URL) {
        isInstallingAddonFromFile = true
        reloadActionSection()
        
        Task { [weak self] in
            guard let self else {
                return
            }
            
            do {
                let stagedPackageURL = try Self.stageAddonPackage(from: packageURL)
                _ = try await AddonRuntime.shared.install(url: stagedPackageURL.absoluteString)
                await self.loadRuntimeAddons()
                
                await MainActor.run {
                    self.isInstallingAddonFromFile = false
                    self.reloadActionSection()
                }
            } catch {
                await MainActor.run {
                    self.isInstallingAddonFromFile = false
                    self.reloadActionSection()
                    let presentation = AddonErrorPresenter.installErrorPresentation(
                        for: error,
                        addonName: packageURL.deletingPathExtension().lastPathComponent
                    )
                    guard !presentation.isUserCancelled else {
                        return
                    }
                    AlertPresenter.show(title: nil, message: presentation.alertMessage)
                }
            }
        }
    }
    
    private static func stageAddonPackage(from packageURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let stagingDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent("Addons", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
        
        let destinationURL = stagingDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("xpi")
        
        let hasSecurityScopedAccess = packageURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: packageURL, to: destinationURL)
        return destinationURL
    }
    
    // MARK: - Icons
    
    private func loadIcon(for addon: Addon) {
        let cacheKey = addon.id as NSString
        guard Self.sharedIconCache.object(forKey: cacheKey) == nil,
              loadingIconIDs.contains(addon.id) == false,
              addon.metaData.iconURL != nil else {
            return
        }
        
        loadingIconIDs.insert(addon.id)
        let iconURL = addon.metaData.iconURL
        iconLoadingQueue.async { [weak self] in
            guard let self else {
                return
            }
            
            let iconImage = AddonIconLoader.loadImage(from: iconURL, targetSize: UX.iconSize)
            DispatchQueue.main.async {
                self.loadingIconIDs.remove(addon.id)
                if let iconImage {
                    Self.sharedIconCache.setObject(iconImage, forKey: cacheKey)
                }
                
                guard let currentIndexPath = self.indexPath(forAddonID: addon.id),
                      let cell = self.tableView.cellForRow(at: currentIndexPath) else {
                    return
                }
                
                cell.imageView?.image = iconImage ?? UIImage(named: "reynard.puzzlepiece.extension")
                cell.setNeedsLayout()
            }
        }
    }
    
    private func statusText(for addon: Addon) -> String? {
        if let statusText = addonStatusTextByID[addon.id] {
            return statusText
        }
        if addon.metaData.isUnsupported {
            return "Unsupported"
        }
        return nil
    }
    
    private func applyAvailabilityState(to cell: UITableViewCell, for addon: Addon) {
        guard addon.metaData.enabled == false else {
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.alpha = 1
            return
        }
        
        cell.textLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.textColor = .tertiaryLabel
        cell.imageView?.alpha = UX.disabledIconAlpha
    }
    
    // MARK: - Updates
    
    private func clearUpdateStatus() {
        addonStatusTextByID.removeAll()
        updateFooterMessage = nil
        
        let pendingApprovalAddonIDs = Prefs.AddonSettings.pendingApprovalAddonIDs
        guard !pendingApprovalAddonIDs.isEmpty else {
            return
        }
        
        pendingApprovalAddonIDs.forEach { addonStatusTextByID[$0] = "Needs permission to update" }
        updateFooterMessage = pendingApprovalAddonIDs.count == 1
        ? "1 add-on needs permission to update."
        : "\(pendingApprovalAddonIDs.count) add-ons need permission to update."
    }
    
    private func updateAddons() {
        guard let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self) else {
            return
        }
        
        isCheckingForAddonUpdates = true
        addonStatusTextByID.removeAll()
        updateFooterMessage = nil
        tableView.reloadData()
        
        Task { [weak self] in
            guard let self else {
                return
            }
            
            let result: AddonUpdateBatchResult
            if browserViewController.addonCoordinator.updateCoordinator.hasPendingApprovals {
                result = await browserViewController.addonCoordinator.updateCoordinator.completePendingUpdates { [weak self] addonID, statusText in
                    self?.applyUpdateStatus(statusText, toAddonID: addonID)
                }
            } else {
                result = await browserViewController.addonCoordinator.updateCoordinator.updateAllAddons { [weak self] addonID, statusText in
                    self?.applyUpdateStatus(statusText, toAddonID: addonID)
                }
            }
            
            await self.loadRuntimeAddons()
            
            await MainActor.run {
                self.isCheckingForAddonUpdates = false
                
                let pendingApprovalAddonIDs = Prefs.AddonSettings.pendingApprovalAddonIDs
                pendingApprovalAddonIDs.forEach { self.addonStatusTextByID[$0] = "Needs permission to update" }
                self.updateFooterMessage = self.updateFooterSummary(for: result)
                self.tableView.reloadData()
            }
        }
    }
    
    private func applyUpdateStatus(_ statusText: String?, toAddonID addonID: String) {
        if let statusText {
            addonStatusTextByID[addonID] = statusText
        } else {
            addonStatusTextByID.removeValue(forKey: addonID)
        }
        if let indexPath = indexPath(forAddonID: addonID) {
            tableView.reloadRows(at: [indexPath], with: .none)
        } else {
            tableView.reloadData()
        }
    }
    
    private func updateFooterSummary(for result: AddonUpdateBatchResult) -> String? {
        var parts: [String] = []
        
        if result.updatedCount > 0 {
            parts.append(result.updatedCount == 1 ? "1 add-on updated." : "\(result.updatedCount) add-ons updated.")
        }
        
        if result.pendingApprovalCount > 0 {
            parts.append(
                result.pendingApprovalCount == 1
                ? "1 add-on needs permission to update."
                : "\(result.pendingApprovalCount) add-ons need permission to update."
            )
        }
        
        if result.failedCount > 0 {
            parts.append(result.failedCount == 1 ? "1 add-on failed to update." : "\(result.failedCount) add-ons failed to update.")
        }
        
        if parts.isEmpty, result.noUpdateCount > 0 {
            return "No updates found."
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    
    private func indexPath(forAddonID addonID: String) -> IndexPath? {
        if let row = installedAddons.firstIndex(where: { $0.id == addonID }),
           let section = displayedSections.firstIndex(of: .installed) {
            return IndexPath(row: row, section: section)
        }
        
        if let row = unsupportedAddons.firstIndex(where: { $0.id == addonID }),
           let section = displayedSections.firstIndex(of: .unsupported) {
            return IndexPath(row: row, section: section)
        }
        
        return nil
    }
    
    private func reloadActionSection() {
        guard let section = displayedSections.firstIndex(of: .more) else {
            return
        }
        tableView.reloadSections(IndexSet(integer: section), with: .none)
    }
}

extension AddonsPreferencesViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        
        installAddonPackage(from: url)
    }
}
