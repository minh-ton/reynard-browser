//
//  ClearBrowsingDataViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/6/26.
//

import GeckoView
import UIKit

final class ClearBrowsingDataViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case data
        case action
    }
    
    private enum BrowsingDataCategory: CaseIterable {
        case browsingHistory
        case cookiesAndSiteData
        case cachedImagesAndFiles
        case downloadsHistory
        case downloadedFiles
        case sitePermissions
        case openedTabs
        
        var title: String {
            switch self {
            case .browsingHistory:
                return NSLocalizedString("Browsing History", comment: "")
            case .cookiesAndSiteData:
                return NSLocalizedString("Cookies and Site Data", comment: "")
            case .cachedImagesAndFiles:
                return NSLocalizedString("Cached Images and Files", comment: "")
            case .downloadsHistory:
                return NSLocalizedString("Downloads History", comment: "")
            case .downloadedFiles:
                return NSLocalizedString("Downloaded Files", comment: "")
            case .sitePermissions:
                return NSLocalizedString("Site Permissions", comment: "")
            case .openedTabs:
                return NSLocalizedString("Opened Tabs", comment: "")
            }
        }
        
        var subtitle: String? {
            switch self {
            case .browsingHistory:
                let count = HistoryStore.shared.currentSnapshot().items.count
//                return "\(count) \(count == 1 ? NSLocalizedString("", comment: "")"address" : NSLocalizedString("", comment: "")"addresses")"
                return "\(count) \(count == 1 ? "address" : "addresses")"
            case .cookiesAndSiteData:
                return NSLocalizedString("You'll be logged out of most sites", comment: "")
            case .cachedImagesAndFiles:
                return NSLocalizedString("Frees up storage space", comment: "")
            case .downloadsHistory:
                return nil
            case .downloadedFiles:
                return nil
            case .sitePermissions:
                return nil
            case .openedTabs:
                return nil
            }
        }
        
        var isSelected: Bool {
            switch self {
            case .browsingHistory:
                return Prefs.ClearBrowsingData.clearsBrowsingHistory
            case .cookiesAndSiteData:
                return Prefs.ClearBrowsingData.clearsCookiesAndSiteData
            case .cachedImagesAndFiles:
                return Prefs.ClearBrowsingData.clearsCachedImagesAndFiles
            case .downloadsHistory:
                return Prefs.ClearBrowsingData.clearsDownloadsHistory
            case .downloadedFiles:
                return Prefs.ClearBrowsingData.clearsDownloadedFiles
            case .sitePermissions:
                return Prefs.ClearBrowsingData.clearsSitePermissions
            case .openedTabs:
                return Prefs.ClearBrowsingData.clearsOpenedTabs
            }
        }
        
        func setSelected(_ isSelected: Bool) {
            switch self {
            case .browsingHistory:
                Prefs.ClearBrowsingData.clearsBrowsingHistory = isSelected
            case .cookiesAndSiteData:
                Prefs.ClearBrowsingData.clearsCookiesAndSiteData = isSelected
            case .cachedImagesAndFiles:
                Prefs.ClearBrowsingData.clearsCachedImagesAndFiles = isSelected
            case .downloadsHistory:
                Prefs.ClearBrowsingData.clearsDownloadsHistory = isSelected
            case .downloadedFiles:
                Prefs.ClearBrowsingData.clearsDownloadedFiles = isSelected
            case .sitePermissions:
                Prefs.ClearBrowsingData.clearsSitePermissions = isSelected
            case .openedTabs:
                Prefs.ClearBrowsingData.clearsOpenedTabs = isSelected
            }
        }
    }
    
    private let browsingDataCategorySwitches = BrowsingDataCategory.allCases.reduce(into: [BrowsingDataCategory: UISwitch]()) { result, category in
        let toggle = UISwitch()
        toggle.isOn = category.isSelected
        result[category] = toggle
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Clear Browsing Data", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        for category in BrowsingDataCategory.allCases {
            browsingDataCategorySwitches[category]?.addTarget(self, action: #selector(categorySwitchChanged), for: .valueChanged)
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .data:
            return BrowsingDataCategory.allCases.count
        case .action:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch Section.allCases[indexPath.section] {
        case .data:
            guard BrowsingDataCategory.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            return categoryCell(for: BrowsingDataCategory.allCases[indexPath.row])
        case .action:
            return clearActionCell()
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .data:
            guard BrowsingDataCategory.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            let category = BrowsingDataCategory.allCases[indexPath.row]
            setSelected(!category.isSelected, for: category)
        case .action:
            confirmClearBrowsingData()
        }
    }
    
    private func categoryCell(for category: BrowsingDataCategory) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = category.title
        cell.detailTextLabel?.text = category.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        browsingDataCategorySwitches[category]?.isOn = category.isSelected
        cell.accessoryView = browsingDataCategorySwitches[category]
        cell.selectionStyle = .default
        return cell
    }
    
    private func clearActionCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString("Clear Browsing Data", comment: "")
        cell.textLabel?.textColor = .systemRed
        cell.accessoryType = .none
        return cell
    }
    
    private func setSelected(_ isSelected: Bool, for category: BrowsingDataCategory) {
        category.setSelected(isSelected)
        browsingDataCategorySwitches[category]?.setOn(isSelected, animated: true)
    }
    
    @objc private func categorySwitchChanged(_ sender: UISwitch) {
        guard let category = browsingDataCategorySwitches.first(where: { $0.value === sender })?.key else {
            return
        }
        
        setSelected(sender.isOn, for: category)
    }
    
    @objc private func confirmClearBrowsingData() {
        AlertPresenter.show(
            title: nil,
            message: NSLocalizedString("This action will clear all of your browsing data. It cannot be undone.", comment: ""),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("OK", comment: ""), style: .destructive) { [weak self] in
                    self?.clearSelectedData()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
    
    private func clearSelectedData() {
        let selectedCategories = Set(BrowsingDataCategory.allCases.filter(\.isSelected))
        
        if selectedCategories.contains(.browsingHistory) {
            HistoryStore.shared.clearVisits(since: nil)
        }
        
        if selectedCategories.contains(.downloadsHistory) {
            DownloadStore.shared.clearCompletedDownloads(since: nil)
        }
        
        if selectedCategories.contains(.downloadedFiles) {
            DownloadStore.shared.clearCompletedDownloadFiles()
        }
        
        if selectedCategories.contains(.cachedImagesAndFiles) {
            FaviconStore.shared.clearCache()
        }
        
        if selectedCategories.contains(.sitePermissions) {
            SiteSettingsUtils.resetStoredSitePermissions()
        }
        
        if selectedCategories.contains(.openedTabs) {
            clearOpenedTabs()
        }
        
        Task {
            await clearSelectedEngineData(for: selectedCategories)
        }
    }
    
    private func clearOpenedTabs() {
        guard let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self) else {
            return
        }
        
        browserViewController.tabManager.removeAllTabs(mode: .regular)
        browserViewController.tabManager.removeAllTabs(mode: .private)
        browserViewController.tabManager.createTab(selecting: true, mode: .regular)
    }
    
    private func clearSelectedEngineData(for selectedCategories: Set<BrowsingDataCategory>) async {
        do {
            if selectedCategories.contains(.cookiesAndSiteData) {
                try await GeckoStorageController.clearData(
                    flags: GeckoStorageClearFlags.cookies | GeckoStorageClearFlags.authSessions
                )
                try await GeckoStorageController.clearData(flags: GeckoStorageClearFlags.domStorages)
            }
            
            if selectedCategories.contains(.cachedImagesAndFiles) {
                await GeckoStorageController.clearTranslationModelCache()
                try await GeckoStorageController.clearData(flags: GeckoStorageClearFlags.allCaches)
            }
        } catch {
            AlertPresenter.show(title: NSLocalizedString("Failed to clear browsing data", comment: ""), message: "\(error)")
        }
    }
}
