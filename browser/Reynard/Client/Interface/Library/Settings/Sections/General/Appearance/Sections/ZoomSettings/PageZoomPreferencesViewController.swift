//
//  PageZoomPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import UIKit

final class PageZoomPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case `default`
        case siteSettings
        case reset
        
        var text: SettingsSectionText {
            switch self {
            case .default:
                return SettingsSectionText(headerTitle: NSLocalizedString("DefaultSize", comment: ""))
            case .siteSettings:
                return SettingsSectionText(headerTitle: NSLocalizedString("Specific Site Settings", comment: ""))
            case .reset:
                return SettingsSectionText()
            }
        }
    }
    
    private enum Row {
        case defaultZoom
        case site(SiteSettingsRecord)
        case reset
    }
    
    private var pageZoomSettings: [SiteSettingsRecord] = []
    
    private var displayedSections: [Section] {
        return Section.allCases.filter { section in
            switch section {
            case .default:
                return true
            case .siteSettings:
                return !pageZoomSettings.isEmpty
            case .reset:
                return Prefs.AppearanceSettings.defaultPageZoomLevel != PageZoomLevels.defaultLevel || !pageZoomSettings.isEmpty
            }
        }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Page Zoom", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPageZoomSettings()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        
        switch displayedSections[section] {
        case .default:
            return 1
        case .siteSettings:
            return pageZoomSettings.count
        case .reset:
            return 1
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else {
            return UITableViewCell()
        }
        
        switch row {
        case .defaultZoom:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Zoom Level", comment: "")
            cell.detailTextLabel?.text = PageZoomLevels.displayText(for: Prefs.AppearanceSettings.defaultPageZoomLevel)
            cell.accessoryType = .disclosureIndicator
            return cell
        case .site(let setting):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = setting.host
            cell.detailTextLabel?.text = pageZoomText(for: setting)
            cell.accessoryType = .disclosureIndicator
            return cell
        case .reset:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Reset Page Zoom Settings", comment: "")
            cell.textLabel?.textColor = .systemRed
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let row = row(at: indexPath) else {
            return
        }
        
        switch row {
        case .defaultZoom:
            navigationController?.pushViewController(
                PageZoomLevelPreferencesViewController(mode: .defaultZoom),
                animated: true
            )
        case .site(let setting):
            guard let pageZoom = setting.pageZoom else {
                return
            }
            navigationController?.pushViewController(
                PageZoomLevelPreferencesViewController(mode: .site(host: setting.host, pageZoom: pageZoom)),
                animated: true
            )
        case .reset:
            Prefs.AppearanceSettings.defaultPageZoomLevel = PageZoomLevels.defaultLevel
            _ = SiteSettingsStore.shared.clearAllPageZoomSettings()
            reloadPageZoomSettings()
            tableView.reloadData()
        }
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath),
              case .site(let setting) = row else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { [weak self] _, _, completion in
            _ = SiteSettingsStore.shared.clearPageZoom(forHost: setting.host)
            self?.reloadPageZoomSettings()
            self?.tableView.reloadData()
            completion(true)
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    private func reloadPageZoomSettings() {
        pageZoomSettings = SiteSettingsStore.shared.settingsWithPageZoom()
    }
    
    private func row(at indexPath: IndexPath) -> Row? {
        guard displayedSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch displayedSections[indexPath.section] {
        case .default:
            guard indexPath.row == 0 else {
                return nil
            }
            return .defaultZoom
        case .siteSettings:
            guard pageZoomSettings.indices.contains(indexPath.row) else {
                return nil
            }
            return .site(pageZoomSettings[indexPath.row])
        case .reset:
            guard indexPath.row == 0 else {
                return nil
            }
            return .reset
        }
    }
    
    private func pageZoomText(for setting: SiteSettingsRecord) -> String? {
        guard let pageZoom = setting.pageZoom else {
            return nil
        }
        return PageZoomLevels.displayText(for: pageZoom)
    }
}
