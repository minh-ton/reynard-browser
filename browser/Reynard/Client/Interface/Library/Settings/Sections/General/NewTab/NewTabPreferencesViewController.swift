//
//  NewTabPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

import UIKit

final class NewTabPreferencesViewController: SettingsTableViewController, UITextFieldDelegate {
    private enum Section: CaseIterable {
        case showOnNewTab
        case behavior
        
        var text: SettingsSectionText {
            switch self {
            case .showOnNewTab:
                return SettingsSectionText(headerTitle: NSLocalizedString("Open New Tabs To", comment: ""))
            case .behavior:
                return SettingsSectionText(headerTitle: NSLocalizedString("Behavior", comment: ""))
            }
        }
    }
    
    private enum Row: CaseIterable {
        case homepage
        case blankPage
        case customURL
        
        var title: String {
            switch self {
            case .homepage:
                return NSLocalizedString("Homepage", comment: "")
            case .blankPage:
                return NSLocalizedString("Blank Page", comment: "")
            case .customURL:
                return NSLocalizedString("Custom URL", comment: "")
            }
        }
        
        var newTabDisplayOption: NewTabDisplayOption {
            switch self {
            case .homepage:
                return .homepage
            case .blankPage:
                return .blankPage
            case .customURL:
                return .customURL
            }
        }
    }

    private lazy var automaticallyOpensKeyboardSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = Prefs.NewTabSettings.automaticallyOpensKeyboard
        toggle.accessibilityLabel = NSLocalizedString("Open Keyboard", comment: "")
        toggle.addTarget(self, action: #selector(automaticallyOpensKeyboardChanged), for: .valueChanged)
        return toggle
    }()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("New Tab", comment: "")
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
        automaticallyOpensKeyboardSwitch.setOn(
            Prefs.NewTabSettings.automaticallyOpensKeyboard,
            animated: false
        )
        automaticallyOpensKeyboardSwitch.accessibilityValue = automaticallyOpensKeyboardSwitch.isOn
            ? NSLocalizedString("On", comment: "")
            : NSLocalizedString("Off", comment: "")
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
        case .showOnNewTab:
            return Row.allCases.count
        case .behavior:
            return 1
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }

        switch Section.allCases[indexPath.section] {
        case .showOnNewTab:
            guard Row.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            switch Row.allCases[indexPath.row] {
            case .homepage, .blankPage:
                return checkmarkCell(for: Row.allCases[indexPath.row])
            case .customURL:
                return customURLCell(for: indexPath)
            }
        case .behavior:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Open Keyboard", comment: "")
            cell.accessoryView = automaticallyOpensKeyboardSwitch
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }

        switch Section.allCases[indexPath.section] {
        case .showOnNewTab:
            guard Row.allCases.indices.contains(indexPath.row) else { return }
            switch Row.allCases[indexPath.row] {
            case .homepage:
                selectNewTabDisplayOption(.homepage)
            case .blankPage:
                selectNewTabDisplayOption(.blankPage)
            case .customURL:
                focusCustomURLField()
            }
        case .behavior:
            automaticallyOpensKeyboardSwitch.setOn(
                !automaticallyOpensKeyboardSwitch.isOn,
                animated: true
            )
            automaticallyOpensKeyboardChanged()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let submittedText = textField.text ?? ""
        if submittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearCustomURL(textField)
            return true
        }
        
        guard let url = URLUtils.normalizedCustomURL(from: submittedText) else {
            return false
        }
        
        Prefs.NewTabSettings.customNewTabURL = url.absoluteString
        textField.text = url.absoluteString
        selectNewTabDisplayOption(.customURL)
        textField.resignFirstResponder()
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let editedText = textField.text ?? ""
        if editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearCustomURL(textField)
            return
        }
        
        guard Prefs.NewTabSettings.newTabDisplayOption == .customURL,
              let url = URLUtils.normalizedCustomURL(from: editedText) else {
            return
        }
        
        Prefs.NewTabSettings.customNewTabURL = url.absoluteString
        textField.text = url.absoluteString
    }
    
    private func selectNewTabDisplayOption(_ option: NewTabDisplayOption) {
        Prefs.NewTabSettings.newTabDisplayOption = option
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }

    @objc private func automaticallyOpensKeyboardChanged() {
        Prefs.NewTabSettings.automaticallyOpensKeyboard = automaticallyOpensKeyboardSwitch.isOn
        automaticallyOpensKeyboardSwitch.accessibilityValue = automaticallyOpensKeyboardSwitch.isOn
            ? NSLocalizedString("On", comment: "")
            : NSLocalizedString("Off", comment: "")
    }
    
    private func clearCustomURL(_ textField: UITextField) {
        Prefs.NewTabSettings.customNewTabURL = ""
        textField.text = ""
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
    
    private func focusCustomURLField() {
        let customURLIndex = Row.allCases.firstIndex(of: .customURL) ?? 0
        guard let cell = tableView.cellForRow(at: IndexPath(row: customURLIndex, section: 0)) as? CustomNewTabURLCell else {
            return
        }
        
        cell.textField.becomeFirstResponder()
    }
    
    private func registerCells() {
        tableView.register(CustomNewTabURLCell.self, forCellReuseIdentifier: "CustomNewTabURLCell")
    }
    
    private func checkmarkCell(for row: Row) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.accessoryType = Prefs.NewTabSettings.newTabDisplayOption == row.newTabDisplayOption ? .checkmark : .none
        return cell
    }
    
    private func customURLCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "CustomNewTabURLCell", for: indexPath) as? CustomNewTabURLCell else {
            return UITableViewCell()
        }
        
        cell.textField.delegate = self
        cell.textField.placeholder = Row.customURL.title
        cell.textField.text = Prefs.NewTabSettings.customNewTabURL
        cell.accessoryType = showsCustomURLCheckmark ? .checkmark : .none
        return cell
    }
    
    private var showsCustomURLCheckmark: Bool {
        return Prefs.NewTabSettings.newTabDisplayOption == .customURL &&
        URLUtils.isWebURL(Prefs.NewTabSettings.customNewTabURL)
    }
    
}
