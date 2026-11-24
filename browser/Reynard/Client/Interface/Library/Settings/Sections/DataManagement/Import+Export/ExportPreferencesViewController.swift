//
//  ExportPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import GeckoView
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

final class ExportPreferencesViewController: SettingsTableViewController {
    private enum Section: Int, CaseIterable {
        case introduction
        case data
        case action
    }
    
    private var selectedTypes = Set(UserDataType.allCases)
    private var counts: [UserDataType: Int] = [:]
    private var countErrors: [UserDataType: String] = [:]
    private var isExporting = false
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Export Browsing Data", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCounts()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .data:
            return UserDataType.allCases.count
        case .introduction, .action:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch Section.allCases[indexPath.section] {
        case .introduction:
            let cell = ImportExportIntroductionCell(style: .default, reuseIdentifier: nil)
            cell.configure(
                iconName: "reynard.iphone.and.arrow.right.outward",
                title: NSLocalizedString("Export Browsing Data", comment: ""),
                description: NSLocalizedString("Export your bookmarks, history, and other browser data to a file that can be imported into other browsers.", comment: "")
            )
            return cell
        case .action:
            let isEnabled = !isExporting && !selectedTypes.isEmpty
            let cell = SettingsViewUtils.actionCell(
                title: NSLocalizedString("Export…", comment: ""),
                tintColor: isEnabled ? view.tintColor : .tertiaryLabel
            )
            cell.textLabel?.textAlignment = .center
            cell.isUserInteractionEnabled = isEnabled
            if !isEnabled {
                cell.accessibilityTraits.insert(.notEnabled)
            }
            return cell
        case .data:
            guard UserDataType.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let type = UserDataType.allCases[indexPath.row]
            let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = ImportExportViewUtils.title(for: type)
            cell.detailTextLabel?.text = counts[type].map { ImportExportViewUtils.countDescription($0, for: type) }
            ?? countErrors[type] ?? NSLocalizedString("Loading…", comment: "")
            cell.detailTextLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(named: ImportExportViewUtils.iconName(for: type))
            cell.imageView?.tintColor = view.tintColor
            cell.isUserInteractionEnabled = !isExporting
            if selectedTypes.contains(type) {
                if isExporting {
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    cell.accessoryView = spinner
                } else {
                    cell.accessoryType = .checkmark
                }
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        guard !isExporting else {
            return
        }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .introduction:
            return
        case .action:
            guard !selectedTypes.isEmpty else {
                return
            }
            chooseFolder()
        case .data:
            guard UserDataType.allCases.indices.contains(indexPath.row) else {
                return
            }
            let type = UserDataType.allCases[indexPath.row]
            if selectedTypes.contains(type) {
                selectedTypes.remove(type)
            } else {
                selectedTypes.insert(type)
            }
            tableView.cellForRow(at: indexPath)?.accessoryType = selectedTypes.contains(type) ? .checkmark : .none
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.action.rawValue)], with: .none)
        }
    }
    
    private func loadCounts() {
        for (row, type) in UserDataType.allCases.enumerated() {
            Task { [weak self] in
                guard let self else {
                    return
                }
                
                do {
                    switch type {
                    case .bookmarks:
                        self.counts[type] = await BookmarkStore.shared.bookmarkCount()
                    case .history:
                        self.counts[type] = await HistoryStore.shared.siteCount()
                    case .extensions:
                        self.counts[type] = try await AddonRuntime.shared.list().filter { !$0.isBuiltIn }.count
                    }
                } catch {
                    self.counts[type] = nil
                }
                self.countErrors[type] = self.counts[type] == nil
                ? NSLocalizedString("Count unavailable", comment: "")
                : nil
                self.tableView.reloadRows(at: [IndexPath(row: row, section: Section.data.rawValue)], with: .none)
            }
        }
    }
    
    private func chooseFolder() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        } else {
            picker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    private func exportData(to directoryURL: URL) {
        guard !isExporting, !selectedTypes.isEmpty else {
            return
        }
        
        let types = selectedTypes
        isExporting = true
        tableView.reloadSections(IndexSet([Section.data.rawValue, Section.action.rawValue]), with: .none)
        
        Task {
            let hasAccess = directoryURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
                isExporting = false
                tableView.reloadSections(IndexSet([Section.data.rawValue, Section.action.rawValue]), with: .none)
            }
            
            do {
                _ = try await ImportExportProgressAlert.run(
                    from: self,
                    message: NSLocalizedString("Exporting in progress…", comment: "")
                ) {
                    let fileURL = directoryURL.appendingPathComponent(UserDataExporter.archiveFileName)
                    return try await UserDataExporter.exportData(to: fileURL, types: types)
                }
                AlertPresenter.show(
                    title: NSLocalizedString("Export Complete", comment: ""),
                    message: NSLocalizedString("Your data has been exported.", comment: ""),
                    in: view.window
                )
            } catch {
                AlertPresenter.show(
                    title: NSLocalizedString("Export Failed", comment: ""),
                    message: ImportExportViewUtils.exportErrorMessage(for: error),
                    in: view.window
                )
            }
        }
    }
}

extension ExportPreferencesViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let directoryURL = urls.first else {
            return
        }
        
        controller.dismiss(animated: true) { [weak self] in
            self?.exportData(to: directoryURL)
        }
    }
}
