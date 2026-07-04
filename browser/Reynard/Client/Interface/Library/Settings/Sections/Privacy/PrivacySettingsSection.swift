//
//  PrivacySettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

struct PrivacySettingsSection {
    enum Row: CaseIterable {
        case sitePermissions
        case clearBrowsingData
    }
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    func cell(at index: Int) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .sitePermissions:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Site Permissions", comment: ""))
        case .clearBrowsingData:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Clear Browsing Data", comment: ""))
        }
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index) else {
            return
        }
        
        switch Row.allCases[index] {
        case .sitePermissions:
            let destination = SitePermissionsViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        case .clearBrowsingData:
            let destination = ClearBrowsingDataViewController()
            viewController.navigationController?.pushViewController(destination, animated: true)
        }
    }
}
