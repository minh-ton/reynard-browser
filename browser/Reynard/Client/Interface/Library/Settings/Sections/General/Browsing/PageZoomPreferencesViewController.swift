//
//  PageZoomPreferencesViewController.swift
//  Reynard
//
//  Created by Reynard on 23/6/26.
//

import UIKit

final class PageZoomPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case defaultZoom

        var text: SettingsSectionText {
            return SettingsSectionText(
                headerTitle: "Default Zoom",
                footerTitle: "Sites use this zoom unless a site-specific Page Zoom value is set from the page menu."
            )
        }
    }

    init() {
        super.init(style: .insetGrouped)
        title = "Page Zoom"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        return PageZoomLevel.allowedPercents.count
    }

    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard PageZoomLevel.allowedPercents.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        let percent = PageZoomLevel.allowedPercents[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = PageZoomLevel.displayTitle(for: percent)
        cell.accessoryType = percent == PageZoomStore.shared.defaultPercent ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard PageZoomLevel.allowedPercents.indices.contains(indexPath.row) else {
            return
        }

        PageZoomStore.shared.defaultPercent = PageZoomLevel.allowedPercents[indexPath.row]
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
    }
}
