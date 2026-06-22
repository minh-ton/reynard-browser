//
//  BrowsingPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import UIKit

final class BrowsingPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case links
        case media
        case desktopWebsite
        
        var text: SettingsSectionText {
            switch self {
            case .links:
                return SettingsSectionText(headerTitle: "Links")
            case .media:
                return SettingsSectionText(headerTitle: "Media")
            case .desktopWebsite:
                return SettingsSectionText(headerTitle: "Request Desktop Website On")
            }
        }
    }
    
    private enum LinksRow: CaseIterable {
        case showLinkPreviews
    }
    
    private enum MediaRow: CaseIterable {
        case autoplay
        case showImagePreviews
    }
    
    private enum DesktopWebsiteRow: CaseIterable {
        case allWebsites
    }
    
    private let showLinkPreviewsSwitch = UISwitch()
    private let showImagePreviewsSwitch = UISwitch()
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
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .links:
            return LinksRow.allCases.count
        case .media:
            return MediaRow.allCases.count
        case .desktopWebsite:
            return DesktopWebsiteRow.allCases.count
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
        case .links:
            guard LinksRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = "Show Link Previews"
            cell.detailTextLabel?.text = "When long-pressing links"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryView = showLinkPreviewsSwitch
            return cell
        case .media:
            guard MediaRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            switch MediaRow.allCases[indexPath.row] {
            case .autoplay:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = "Autoplay"
                cell.detailTextLabel?.text = SiteSettingsUtils.actionTitle(
                    for: SiteSettingsUtils.defaultAction(for: .autoplay),
                    permission: .autoplay
                )
                cell.accessoryType = .disclosureIndicator
                return cell
            case .showImagePreviews:
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.selectionStyle = .none
                cell.textLabel?.text = "Show Image Previews"
                cell.detailTextLabel?.text = "When long-pressing images"
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryView = showImagePreviewsSwitch
                return cell
            }
        case .desktopWebsite:
            guard DesktopWebsiteRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = "All Website"
            cell.accessoryView = requestDesktopWebsiteSwitch
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .links:
            return
        case .media:
            guard MediaRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            switch MediaRow.allCases[indexPath.row] {
            case .autoplay:
                navigationController?.pushViewController(
                    SitePermissionDetailsViewController(permission: .autoplay, title: "Autoplay"),
                    animated: true
                )
            case .showImagePreviews:
                return
            }
        case .desktopWebsite:
            return
        }
    }
    
    private func configureSwitch() {
        showLinkPreviewsSwitch.addTarget(self, action: #selector(showLinkPreviewsSwitchDidChange(_:)), for: .valueChanged)
        showImagePreviewsSwitch.addTarget(self, action: #selector(showImagePreviewsSwitchDidChange(_:)), for: .valueChanged)
        requestDesktopWebsiteSwitch.addTarget(self, action: #selector(requestDesktopWebsiteSwitchDidChange(_:)), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        showLinkPreviewsSwitch.isOn = Prefs.BrowsingSettings.showLinkPreviews
        showImagePreviewsSwitch.isOn = Prefs.BrowsingSettings.showImagePreviews
        requestDesktopWebsiteSwitch.isOn = Prefs.BrowsingSettings.requestDesktopWebsite
    }
    
    @objc private func showLinkPreviewsSwitchDidChange(_ sender: UISwitch) {
        Prefs.BrowsingSettings.showLinkPreviews = sender.isOn
    }
    
    @objc private func showImagePreviewsSwitchDidChange(_ sender: UISwitch) {
        Prefs.BrowsingSettings.showImagePreviews = sender.isOn
    }
    
    @objc private func requestDesktopWebsiteSwitchDidChange(_ sender: UISwitch) {
        Prefs.BrowsingSettings.requestDesktopWebsite = sender.isOn
    }
}
