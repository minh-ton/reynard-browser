//
//  BrowsingPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import UIKit

final class BrowsingPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case desktopWebsite
        
        var text: SettingsSectionText {
            switch self {
            case .desktopWebsite:
                return SettingsSectionText(headerTitle: "Request Desktop Website On")
            }
        }
    }
    
    private enum Row: CaseIterable {
        case allWebsites
    }
    
    private let requestDesktopWebsiteSwitch = UISwitch()
    
    init() {
        super.init(style: .insetGrouped)
        title = "Browsing"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitch()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .desktopWebsite:
            return Row.allCases.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              Row.allCases.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[indexPath.row] {
        case .allWebsites:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = "All Website"
            cell.accessoryView = requestDesktopWebsiteSwitch
            return cell
        }
    }
    
    private func configureSwitch() {
        requestDesktopWebsiteSwitch.addTarget(self, action: #selector(requestDesktopWebsiteSwitchDidChange(_:)), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        requestDesktopWebsiteSwitch.isOn = Prefs.BrowsingSettings.requestDesktopWebsite
    }
    
    @objc private func requestDesktopWebsiteSwitchDidChange(_ sender: UISwitch) {
        Prefs.BrowsingSettings.requestDesktopWebsite = sender.isOn
    }
}
