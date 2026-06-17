//
//  SettingsTableViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

class SettingsTableViewController: UITableViewController {
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionText(for: section).headerTitle
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sectionText(for: section).footerTitle
    }

    // MARK: - Section Text

    func sectionText(for section: Int) -> SettingsSectionText {
        SettingsSectionText()
    }

    // MARK: - View Setup

    private func configureTableView() {
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .interactive

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
    }
}
