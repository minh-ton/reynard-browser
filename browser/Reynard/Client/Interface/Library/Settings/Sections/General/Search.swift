//
//  Search.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit

final class SearchPreferencesViewController: SettingsTableViewController {
    init() {
        super.init(style: .insetGrouped)
        title = "Search"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = "Search Engine"
        cell.detailTextLabel?.text = Prefs.SearchSettings.searchEngine.displayName
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        navigationController?.pushViewController(SearchEnginePreferencesViewController(), animated: true)
    }
}

final class SettingsTextFieldCell: UITableViewCell {
    let textField = UITextField()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SearchEnginePreferencesViewController: SettingsTableViewController, UITextFieldDelegate {
    init() {
        super.init(style: .insetGrouped)
        title = "Search Engine"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(SettingsTextFieldCell.self, forCellReuseIdentifier: "SettingsTextFieldCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Prefs.SearchSettings.searchEngine == .custom ? 2 : 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? SearchEngine.allCases.count : 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTextFieldCell", for: indexPath) as? SettingsTextFieldCell else {
                return UITableViewCell()
            }
            cell.textField.delegate = self
            cell.textField.placeholder = "https://example.com/search?q=%s"
            cell.textField.text = Prefs.SearchSettings.customSearchTemplate
            return cell
        }
        let engine = SearchEngine.allCases[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = engine.displayName
        cell.accessoryType = Prefs.SearchSettings.searchEngine == engine ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard indexPath.section == 0,
              SearchEngine.allCases.indices.contains(indexPath.row) else { return }
        let selectedEngine = SearchEngine.allCases[indexPath.row]
        let wasCustom = Prefs.SearchSettings.searchEngine == .custom
        Prefs.SearchSettings.searchEngine = selectedEngine
        if wasCustom != (selectedEngine == .custom) {
            tableView.reloadData()
        } else {
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
        if selectedEngine == .custom {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as? SettingsTextFieldCell else { return }
                cell.textField.becomeFirstResponder()
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Search Engine" : nil
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        let baseText = "Enter URL with %s in place of query"
        guard !Prefs.SearchSettings.customSearchTemplate.isEmpty,
              isValidCustomSearchTemplate(Prefs.SearchSettings.customSearchTemplate) else { return baseText }
        return "\(baseText). The current value must be a valid http(s) URL."
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        Prefs.SearchSettings.customSearchTemplate = textField.text ?? ""
        tableView.reloadData()
        let value = Prefs.SearchSettings.customSearchTemplate
        guard !value.isEmpty, !isValidCustomSearchTemplate(value) else { return }
        presentAlert(
            title: "Invalid Search URL",
            message: "Enter a valid http(s) URL containing %s where the search query should go."
        )
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
