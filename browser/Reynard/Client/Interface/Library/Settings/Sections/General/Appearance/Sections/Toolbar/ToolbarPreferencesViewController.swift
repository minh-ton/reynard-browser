//
//  ToolbarPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit

final class ToolbarPreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let iconSize = CGSize(width: 28, height: 28)
        static let iconSymbolPointSize: CGFloat = 20
    }
    
    private enum Section: Int, CaseIterable {
        case reset
        case includedItems
        case moreItems
        
        var text: SettingsSectionText {
            switch self {
            case .reset:
                return SettingsSectionText()
            case .includedItems:
                return SettingsSectionText(headerTitle: NSLocalizedString("Included Items", comment: ""))
            case .moreItems:
                return SettingsSectionText(headerTitle: NSLocalizedString("More Items", comment: ""))
            }
        }
    }
    
    private var placement = ToolbarPlacement.bottomToolbar
    private var includedItems: [ToolbarItem] = []
    
    private var moreItems: [ToolbarItem] {
        return placement.availableItems.filter { !includedItems.contains($0) }
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Customize Toolbar", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        placement = LibrarySharedUtils.resolvedBrowserViewController(from: self).map {
            ToolbarPlacement(chromeMode: $0.browserLayout.chromeMode)
        } ?? .bottomToolbar
        includedItems = placement.items
        tableView.reloadData()
    }
    
    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .reset:
            return 1
        case .includedItems:
            return includedItems.count
        case .moreItems:
            return moreItems.count
        case nil:
            return 0
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        return Section(rawValue: section)?.text ?? SettingsSectionText()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .reset:
            let cell = SettingsViewUtils.actionCell(
                title: NSLocalizedString("Reset Toolbar Layout", comment: ""),
                tintColor: view.tintColor
            )
            cell.textLabel?.textAlignment = .center
            return cell
        case .includedItems:
            return itemCell(for: includedItems[indexPath.row])
        case .moreItems:
            return itemCell(for: moreItems[indexPath.row])
        case nil:
            return UITableViewCell()
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section(rawValue: indexPath.section) == .reset else {
            return
        }
        
        includedItems = placement.defaultItems
        placement.items = includedItems
        tableView.reloadSections(IndexSet([Section.includedItems.rawValue, Section.moreItems.rawValue]), with: .automatic)
    }
    
    // MARK: - Editing
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        switch Section(rawValue: indexPath.section) {
        case .includedItems:
            return includedItems[indexPath.row] == .library ? .none : .delete
        case .moreItems:
            return includedItems.count < placement.maximumItemCount ? .insert : .none
        case .reset, nil:
            return .none
        }
    }
    
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return self.tableView(tableView, editingStyleForRowAt: indexPath) != .none
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            let item = includedItems.remove(at: indexPath.row)
            guard let row = moreItems.firstIndex(of: item) else {
                return
            }
            
            moveItemRow(from: indexPath, to: IndexPath(row: row, section: Section.moreItems.rawValue))
        case .insert:
            includedItems.append(moreItems[indexPath.row])
            moveItemRow(from: indexPath, to: IndexPath(row: includedItems.count - 1, section: Section.includedItems.rawValue))
        default:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .includedItems
    }
    
    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        let section = Section.includedItems.rawValue
        if proposedDestinationIndexPath.section < section {
            return IndexPath(row: 0, section: section)
        }
        
        if proposedDestinationIndexPath.section > section {
            return IndexPath(row: includedItems.count - 1, section: section)
        }
        
        return proposedDestinationIndexPath
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let item = includedItems.remove(at: sourceIndexPath.row)
        includedItems.insert(item, at: destinationIndexPath.row)
        placement.items = includedItems
    }
    
    // MARK: - Items
    
    private func itemCell(for item: ToolbarItem) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = item.title
        cell.imageView?.image = icon(for: item)
        cell.imageView?.tintColor = view.tintColor
        cell.selectionStyle = .none
        return cell
    }
    
    private func icon(for item: ToolbarItem) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.iconSymbolPointSize, weight: .regular)
        guard let symbol = UIImage(named: item.symbolName, in: .main, with: configuration) else {
            return nil
        }
        
        let origin = CGPoint(
            x: (UX.iconSize.width - symbol.size.width) / 2,
            y: (UX.iconSize.height - symbol.size.height) / 2
        )
        return UIGraphicsImageRenderer(size: UX.iconSize).image { _ in
            symbol.draw(at: origin)
        }.withRenderingMode(.alwaysTemplate)
    }
    
    private func moveItemRow(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        placement.items = includedItems
        tableView.performBatchUpdates {
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        } completion: { [weak self] _ in
            self?.tableView.reloadSections(IndexSet([Section.includedItems.rawValue, Section.moreItems.rawValue]), with: .none)
        }
    }
}
