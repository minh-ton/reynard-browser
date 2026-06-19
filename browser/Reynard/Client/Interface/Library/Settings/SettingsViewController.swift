//
//  SettingsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SettingsViewController: SettingsTableViewController {
    enum Section: Int, CaseIterable {
        case updates
        case jit
        case general
        case privacy
        case about
        
        var text: SettingsSectionText {
            switch self {
            case .updates:
                return SettingsSectionText(headerTitle: "Update Available")
            case .jit:
                return SettingsSectionText(headerTitle: "JIT")
            case .general:
                return SettingsSectionText(headerTitle: "General")
            case .privacy:
                return SettingsSectionText(headerTitle: "Privacy")
            case .about:
                return SettingsSectionText(headerTitle: "About")
            }
        }
    }
    
    private let updatesSection = UpdatesSettingsSection()
    private let jitSection = JITSettingsSection()
    private let generalSection = GeneralSettingsSection()
    private let privacySection = PrivacySettingsSection()
    private let aboutSection = AboutSettingsSection()
    
    var displayedSections: [Section] {
        var hiddenSections: Set<Section> = []
        let unsandboxed = getEntitlementValue("com.apple.private.security.no-sandbox")
        
        if !BrowserUpdates.shared.hasUpdate || (unsandboxed && !updatesSection.installedThroughTrollStore) {
            hiddenSections.insert(.updates)
        }
        
        if unsandboxed {
            hiddenSections.insert(.jit)
        }
        
        return Section.allCases.filter { !hiddenSections.contains($0) }
    }
    
    // MARK: - Lifecycle
    
    init() {
        super.init(style: .insetGrouped)
        configureViewController()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observeJITMode()
        jitSection.refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        jitSection.refreshDisplayedState()
        tableView.reloadData()
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
        case .updates:
            return updatesSection.rowCount
        case .jit:
            return jitSection.rowCount
        case .general:
            return generalSection.rowCount
        case .privacy:
            return privacySection.rowCount
        case .about:
            return aboutSection.rowCount
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .updates:
            return updatesSection.cell(at: indexPath.row, tintColor: view.tintColor)
        case .jit:
            return jitSection.cell(at: indexPath.row, tintColor: view.tintColor)
        case .general:
            return generalSection.cell(at: indexPath.row)
        case .privacy:
            return privacySection.cell(at: indexPath.row)
        case .about:
            return aboutSection.cell(at: indexPath.row)
        }
    }
    
    // MARK: - Table Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch displayedSections[indexPath.section] {
        case .updates:
            updatesSection.selectRow(at: indexPath.row, from: self)
        case .jit:
            jitSection.selectRow(at: indexPath.row, from: self)
        case .general:
            generalSection.selectRow(at: indexPath.row, from: self)
        case .privacy:
            privacySection.selectRow(at: indexPath.row, from: self)
        case .about:
            aboutSection.selectRow(at: indexPath.row)
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard displayedSections.indices.contains(section) else {
            return nil
        }
        
        switch displayedSections[section] {
        case .updates where updatesSection.installedThroughTrollStore:
            return updatesSection.trollStoreFooterView()
        case .jit:
            return jitSection.footerView()
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .updates else {
            return UITableView.automaticDimension
        }
        
        return updatesSection.rowHeight(at: indexPath.row, in: tableView)
    }
    
    // MARK: - View Setup
    
    private func configureViewController() {
        title = "Settings"
        jitSection.attach(to: self)
    }
    
    private func observeJITMode() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncJITModeBanner(_:)),
            name: .jitlessModeDidActivate,
            object: nil
        )
    }
    
    @objc private func syncJITModeBanner(_ notification: Notification) {
        jitSection.refreshDisplayedState()
        tableView.reloadData()
    }
    
}

// MARK: - UIDocumentPickerDelegate

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        
        jitSection.savePairingFile(from: url)
    }
}
