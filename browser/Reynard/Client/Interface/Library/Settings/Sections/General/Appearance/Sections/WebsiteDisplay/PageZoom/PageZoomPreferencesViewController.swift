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
                return SettingsSectionText(headerTitle: "Default Setting")
            case .siteSettings:
                return SettingsSectionText(headerTitle: "Page Zoom on")
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
        title = "Page Zoom"
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
            cell.textLabel?.text = "Zoom Level"
            configureZoomPickerCell(cell, mode: .defaultZoom)
            return cell
        case .site(let setting):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = setting.host
            if let pageZoom = setting.pageZoom {
                configureZoomPickerCell(cell, mode: .site(host: setting.host, pageZoom: pageZoom))
            }
            return cell
        case .reset:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Reset Page Zoom Settings"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
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
            handlePageZoomSelection(at: indexPath, mode: .defaultZoom)
        case .site(let setting):
            guard let pageZoom = setting.pageZoom else {
                return
            }
            handlePageZoomSelection(at: indexPath, mode: .site(host: setting.host, pageZoom: pageZoom))
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
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
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
    
    private func configureZoomPickerCell(_ cell: UITableViewCell, mode: PageZoomLevelPreferencesViewController.Mode) {
        if #available(iOS 14.0, *) {
            cell.detailTextLabel?.text = nil
            cell.accessoryView = pageZoomMenuButton(for: mode)
            cell.accessoryType = .none
        } else {
            cell.detailTextLabel?.text = PageZoomLevels.displayText(for: selectedPageZoomLevel(for: mode))
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
    }
    
    private func handlePageZoomSelection(at indexPath: IndexPath, mode: PageZoomLevelPreferencesViewController.Mode) {
        if #available(iOS 14.0, *) {
            if #available(iOS 17.4, *),
               let cell = tableView.cellForRow(at: indexPath),
               let button = cell.accessoryView as? UIButton {
                button.performPrimaryAction()
            }
            return
        }
        
        navigationController?.pushViewController(
            PageZoomLevelPreferencesViewController(mode: mode),
            animated: true
        )
    }
    
    private func applyPageZoomLevel(_ level: Int, mode: PageZoomLevelPreferencesViewController.Mode) {
        switch mode {
        case .defaultZoom:
            Prefs.AppearanceSettings.defaultPageZoomLevel = level
        case .site(let host, _):
            _ = SiteSettingsStore.shared.setPageZoom(level, forHost: host)
        }
        reloadPageZoomSettings()
        tableView.reloadData()
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
    
    @available(iOS 14.0, *)
    private func pageZoomMenuButton(for mode: PageZoomLevelPreferencesViewController.Mode) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(PageZoomLevels.displayText(for: selectedPageZoomLevel(for: mode)), for: .normal)
        button.setImage(UIImage(named: "reynard.chevron.up.chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        if #available(iOS 15.0, *) {
            button.changesSelectionAsPrimaryAction = true
        }
        button.menu = pageZoomMenu(for: mode)
        button.sizeToFit()
        return button
    }
    
    @available(iOS 14.0, *)
    private func pageZoomMenu(for mode: PageZoomLevelPreferencesViewController.Mode) -> UIMenu {
        let selectedLevel = selectedPageZoomLevel(for: mode)
        let actions = PageZoomLevels.all.map { level in
            UIAction(title: PageZoomLevels.displayText(for: level), state: level == selectedLevel ? .on : .off) { [weak self] _ in
                self?.applyPageZoomLevel(level, mode: mode)
            }
        }
        
        if #available(iOS 15.0, *) {
            return UIMenu(title: "", options: .singleSelection, children: actions)
        }
        return UIMenu(title: "", children: actions)
    }
    
    private func selectedPageZoomLevel(for mode: PageZoomLevelPreferencesViewController.Mode) -> Int {
        switch mode {
        case .defaultZoom:
            return Prefs.AppearanceSettings.defaultPageZoomLevel
        case .site(_, let pageZoom):
            return pageZoom
        }
    }
}
