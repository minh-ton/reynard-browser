//
//  BlockedTrackersViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/7/26.
//

import GeckoView
import UIKit

final class BlockedTrackersViewController: UITableViewController {
    private let trackers: [BlockedTracker]
    
    private var categories: [BlockedTrackerCategory] {
        return BlockedTrackerCategory.allCases.filter { category in
            trackers.contains { $0.categories.contains(category) }
        }
    }
    
    init(trackers: [BlockedTracker]) {
        self.trackers = trackers
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Blocked Trackers", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return categories.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard categories.indices.contains(section) else {
            return 0
        }
        let category = categories[section]
        return trackers.filter { $0.categories.contains(category) }.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let category = categories[safe: section] else {
            return nil
        }
        return title(for: category)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard categories.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        let category = categories[indexPath.section]
        let categoryTrackers = trackers.filter { $0.categories.contains(category) }
        guard categoryTrackers.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        let tracker = categoryTrackers[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = URL(string: tracker.url)?.host ?? tracker.url
        cell.selectionStyle = .none
        return cell
    }
    
    private func title(for category: BlockedTrackerCategory) -> String {
        switch category {
        case .crossSiteTrackingCookies:
            return NSLocalizedString("Cross-Site Tracking Cookies", tableName: "SettingsLocalizable", comment: "")
        case .cryptominers:
            return NSLocalizedString("Cryptominers", tableName: "SettingsLocalizable", comment: "")
        case .fingerprinters:
            return NSLocalizedString("Fingerprinters", tableName: "SettingsLocalizable", comment: "")
        case .socialMediaTrackers:
            return NSLocalizedString("Social Media Trackers", tableName: "SettingsLocalizable", comment: "")
        case .trackingContent:
            return NSLocalizedString("Tracking Content", tableName: "SettingsLocalizable", comment: "")
        }
    }
}
