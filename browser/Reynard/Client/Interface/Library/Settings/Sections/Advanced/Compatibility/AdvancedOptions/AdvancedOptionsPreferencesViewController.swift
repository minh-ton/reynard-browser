//
//  AdvancedOptionsPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 15/8/26.
//

import UIKit

final class AdvancedOptionsPreferencesViewController: SettingsTableViewController, UITextFieldDelegate {
    private enum Section: CaseIterable {
        case userAgent
    }
    
    private enum Field: CaseIterable {
        case userAgent
        case oscpu
        case buildID
        case platform
        case appVersion
        
        var title: String {
            switch self {
            case .userAgent:
                return "userAgent"
            case .oscpu:
                return "oscpu"
            case .buildID:
                return "buildID"
            case .platform:
                return "platform"
            case .appVersion:
                return "appVersion"
            }
        }
    }
    
    private let userAgentPolicy = UserAgentPolicy()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Advanced Options", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(AdvancedOptionsValueCell.self, forCellReuseIdentifier: "AdvancedOptionsValueCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        return Field.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              Field.allCases.indices.contains(indexPath.row),
              let cell = tableView.dequeueReusableCell(
                withIdentifier: "AdvancedOptionsValueCell",
                for: indexPath
              ) as? AdvancedOptionsValueCell else {
            return UITableViewCell()
        }
        
        let field = Field.allCases[indexPath.row]
        cell.titleLabel.text = field.title
        cell.textField.delegate = self
        cell.textField.tag = indexPath.row
        cell.textField.text = value(for: field)
        cell.textField.placeholder = placeholder(for: field)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Field.allCases.indices.contains(indexPath.row),
              let cell = tableView.cellForRow(at: indexPath) as? AdvancedOptionsValueCell else {
            return
        }
        cell.textField.becomeFirstResponder()
    }
    
    // MARK: - Text Field Delegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        save(textField)
        textField.resignFirstResponder()
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        save(textField)
    }
    
    // MARK: - Values
    
    private var defaultConfiguration: UserAgentConfiguration {
        return userAgentPolicy.defaultConfiguration(
            prefersDesktopMode: Prefs.BrowsingSettings.effectiveRequestDesktopWebsite
        )
    }
    
    private func value(for field: Field) -> String {
        switch field {
        case .userAgent:
            return Prefs.CompatibilitySettings.customUserAgent
        case .oscpu:
            return Prefs.CompatibilitySettings.customOscpu
        case .buildID:
            return Prefs.CompatibilitySettings.customBuildID
        case .platform:
            return Prefs.CompatibilitySettings.customPlatform
        case .appVersion:
            return Prefs.CompatibilitySettings.customAppVersion
        }
    }
    
    private func placeholder(for field: Field) -> String? {
        switch field {
        case .userAgent:
            return defaultConfiguration.override
        case .oscpu:
            return defaultConfiguration.oscpuOverride
        case .buildID:
            return nil
        case .platform:
            return defaultConfiguration.platformOverride
        case .appVersion:
            return defaultConfiguration.appVersionOverride
        }
    }
    
    private func save(_ textField: UITextField) {
        guard Field.allCases.indices.contains(textField.tag) else {
            return
        }
        
        let field = Field.allCases[textField.tag]
        let value = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let customValue = value == (placeholder(for: field) ?? "") ? "" : value
        textField.text = customValue
        
        switch field {
        case .userAgent:
            Prefs.CompatibilitySettings.customUserAgent = customValue
        case .oscpu:
            Prefs.CompatibilitySettings.customOscpu = customValue
        case .buildID:
            Prefs.CompatibilitySettings.customBuildID = customValue
        case .platform:
            Prefs.CompatibilitySettings.customPlatform = customValue
        case .appVersion:
            Prefs.CompatibilitySettings.customAppVersion = customValue
        }
    }
}
