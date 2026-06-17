//
//  PrivacySettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

struct PrivacySettingsSection {
    // MARK: - Rows

    enum Row: CaseIterable {
        case sitePermissions
    }

    // MARK: - State

    var rowCount: Int {
        Row.allCases.count
    }

    // MARK: - Cells

    func cell(at index: Int) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }

        switch Row.allCases[index] {
        case .sitePermissions:
            return SettingsViewUtils.disclosureCell(title: "Site Permissions")
        }
    }

    // MARK: - Selection

    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index) else {
            return
        }

        switch Row.allCases[index] {
        case .sitePermissions:
            let destination = SitePermissionsViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        }
    }
}
