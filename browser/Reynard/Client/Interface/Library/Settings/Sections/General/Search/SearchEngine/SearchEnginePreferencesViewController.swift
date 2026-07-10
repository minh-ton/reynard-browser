//
//  SearchEnginePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class SearchEnginePreferencesViewController: SettingsTableViewController, UITextFieldDelegate {
    private enum Section: CaseIterable {
        case engines
        
        var text: SettingsSectionText {
            switch self {
            case .engines:
                return SettingsSectionText(
                    headerTitle: "Search Engine",
                    footerTitle: "Use %s for search terms, as in example.com\u{2060}/\u{2060}search\u{2060}?\u{2060}q\u{2060}=\u{2060}%s."
                )
            }
        }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Search Engine"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        registerCells()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        normalizeSelectedSearchEngine()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .engines:
            return SearchEngine.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch Section.allCases[indexPath.section] {
        case .engines:
            guard SearchEngine.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let engine = SearchEngine.allCases[indexPath.row]
            if engine == .custom {
                return customSearchTemplateCell(for: indexPath)
            }
            
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = engine.displayName
            cell.accessoryType = selectedSearchEngine == engine ? .checkmark : .none
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section),
              Section.allCases[indexPath.section] == .engines,
              SearchEngine.allCases.indices.contains(indexPath.row) else { return }
        let selectedEngine = SearchEngine.allCases[indexPath.row]
        guard selectedEngine != .custom else {
            focusCustomSearchTemplateField()
            return
        }
        
        Prefs.SearchSettings.searchEngine = selectedEngine
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        return Section.allCases[section].text
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let submittedText = textField.text ?? ""
        if submittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearCustomSearchTemplate(textField)
            return true
        }
        
        let normalizedTemplate = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTemplate.contains("%s"),
              URLUtils.normalizedCustomURL(from: normalizedTemplate.replacingOccurrences(of: "%s", with: "reynard")) != nil else {
            Prefs.SearchSettings.customSearchTemplate = submittedText
            Prefs.SearchSettings.searchEngine = .google
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
            return false
        }
        
        let exampleDestination = normalizedTemplate.replacingOccurrences(of: "%s", with: "reynard")
        Prefs.SearchSettings.customSearchTemplate = URLUtils.isWebURL(exampleDestination) ? normalizedTemplate : "https://\(normalizedTemplate)"
        Prefs.SearchSettings.searchEngine = .custom
        textField.text = Prefs.SearchSettings.customSearchTemplate
        textField.resignFirstResponder()
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let editedText = textField.text ?? ""
        if editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearCustomSearchTemplate(textField)
            return
        }
        
        let normalizedTemplate = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTemplate.contains("%s"),
              URLUtils.normalizedCustomURL(from: normalizedTemplate.replacingOccurrences(of: "%s", with: "reynard")) != nil else {
            Prefs.SearchSettings.customSearchTemplate = editedText
            Prefs.SearchSettings.searchEngine = .google
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
            return
        }
        
        let exampleDestination = normalizedTemplate.replacingOccurrences(of: "%s", with: "reynard")
        Prefs.SearchSettings.customSearchTemplate = URLUtils.isWebURL(exampleDestination) ? normalizedTemplate : "https://\(normalizedTemplate)"
        textField.text = Prefs.SearchSettings.customSearchTemplate
        if Prefs.SearchSettings.searchEngine == .custom {
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
    }
    
    private func normalizeSelectedSearchEngine() {
        if Prefs.SearchSettings.searchEngine == .custom,
           !SearchEngine.canSearch(using: Prefs.SearchSettings.customSearchTemplate) {
            Prefs.SearchSettings.searchEngine = .google
        }
    }
    
    private func clearCustomSearchTemplate(_ textField: UITextField) {
        Prefs.SearchSettings.customSearchTemplate = ""
        Prefs.SearchSettings.searchEngine = .google
        textField.text = ""
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
    
    private func focusCustomSearchTemplateField() {
        guard let row = SearchEngine.allCases.firstIndex(of: .custom),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? CustomSearchTemplateCell else {
            return
        }
        
        cell.textField.becomeFirstResponder()
    }
    
    private func registerCells() {
        tableView.register(CustomSearchTemplateCell.self, forCellReuseIdentifier: "CustomSearchTemplateCell")
    }
    
    private func customSearchTemplateCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "CustomSearchTemplateCell", for: indexPath) as? CustomSearchTemplateCell else {
            return UITableViewCell()
        }
        
        cell.textField.delegate = self
        cell.textField.placeholder = "Custom Search URL"
        cell.textField.text = Prefs.SearchSettings.customSearchTemplate
        cell.accessoryType = selectedSearchEngine == .custom ? .checkmark : .none
        return cell
    }
    
    private var selectedSearchEngine: SearchEngine {
        guard Prefs.SearchSettings.searchEngine == .custom else {
            return Prefs.SearchSettings.searchEngine
        }
        
        return SearchEngine.canSearch(using: Prefs.SearchSettings.customSearchTemplate) ? .custom : .google
    }
}
