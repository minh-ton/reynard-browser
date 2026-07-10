//
//  PageZoomLevelPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import UIKit

final class PageZoomLevelPreferencesViewController: SettingsTableViewController {
    enum Mode {
        case defaultZoom
        case site(host: String, pageZoom: Int)
    }
    
    private enum Section: CaseIterable {
        case zoomLevels
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private var mode: Mode
    
    init(mode: Mode) {
        self.mode = mode
        super.init(style: .insetGrouped)
        title = "Zoom Level"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        return PageZoomLevels.all.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard PageZoomLevels.all.indices.contains(indexPath.row) else {
            return cell
        }
        
        let level = PageZoomLevels.all[indexPath.row]
        cell.textLabel?.text = PageZoomLevels.displayText(for: level)
        cell.accessoryType = level == selectedPageZoomLevel ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard PageZoomLevels.all.indices.contains(indexPath.row) else {
            return
        }
        
        let level = PageZoomLevels.all[indexPath.row]
        switch mode {
        case .defaultZoom:
            Prefs.AppearanceSettings.defaultPageZoomLevel = level
        case .site(let host, _):
            _ = SiteSettingsStore.shared.setPageZoom(level, forHost: host)
            mode = .site(host: host, pageZoom: level)
        }
        tableView.reloadData()
    }
    
    private var selectedPageZoomLevel: Int {
        switch mode {
        case .defaultZoom:
            return Prefs.AppearanceSettings.defaultPageZoomLevel
        case .site(_, let pageZoom):
            return pageZoom
        }
    }
}
