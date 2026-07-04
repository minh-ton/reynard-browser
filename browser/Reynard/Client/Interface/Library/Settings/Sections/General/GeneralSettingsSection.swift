//
//  GeneralSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

struct GeneralSettingsSection {
    enum Row: CaseIterable {
        case addons
        case browsing
        case search
        case newTab
        case homepage
        case appearance
        case compatibility
    }
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    func cell(at index: Int) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .addons:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Add-ons", comment: ""))
        case .browsing:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Browsing", comment: ""))
        case .search:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Search", comment: ""))
        case .newTab:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("New Tab", comment: ""))
        case .homepage:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Homepage", comment: ""))
        case .appearance:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Appearance", comment: ""))
        case .compatibility:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Compatibility", comment: ""))
        }
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index) else {
            return
        }
        
        let destination: UIViewController
        switch Row.allCases[index] {
        case .addons:
            destination = AddonsPreferencesViewController()
        case .browsing:
            destination = BrowsingPreferencesViewController()
        case .search:
            destination = SearchPreferencesViewController()
        case .newTab:
            destination = NewTabPreferencesViewController()
        case .homepage:
            destination = HomepagePreferencesViewController()
        case .appearance:
            destination = AppearancePreferencesViewController()
        case .compatibility:
            destination = CompatibilityPreferencesViewController()
        }
        viewController.navigationController?.pushViewController(destination, animated: true)
    }
}
