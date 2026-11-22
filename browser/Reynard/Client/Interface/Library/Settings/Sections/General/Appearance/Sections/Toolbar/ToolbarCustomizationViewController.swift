//
//  ToolbarCustomizationViewController.swift
//  Reynard
//

import UIKit

/// Lets the user choose which buttons appear in the bottom toolbar and in which order.
final class ToolbarCustomizationViewController: SettingsTableViewController {
    private enum Section: Int, CaseIterable {
        case included
        case available
        case reset

        var text: SettingsSectionText {
            switch self {
            case .included:
                return SettingsSectionText(
                    headerTitle: NSLocalizedString("Toolbar Buttons", comment: ""),
                    footerTitle: String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Drag to change the order of the buttons. The toolbar can hold up to %d buttons. The Menu button can be moved but not removed. The Downloads button appears automatically while files are downloading.",
                            comment: "Maximum toolbar button count"
                        ),
                        BottomToolbarItem.maximumItemCount
                    )
                )
            case .available:
                return SettingsSectionText(headerTitle: NSLocalizedString("More Buttons", comment: ""))
            case .reset:
                return SettingsSectionText()
            }
        }
    }

    private var includedItems: [BottomToolbarItem] = []

    private var availableItems: [BottomToolbarItem] {
        return BottomToolbarItem.allCases.filter { !includedItems.contains($0) }
    }

    private var canAddItems: Bool {
        return includedItems.count < BottomToolbarItem.maximumItemCount
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
        tableView.allowsSelectionDuringEditing = true
        includedItems = Prefs.AppearanceSettings.bottomToolbarItems
        super.setEditing(true, animated: false)
        tableView.setEditing(true, animated: false)
    }

    // MARK: - Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .included:
            return includedItems.count
        case .available:
            return availableItems.count
        case .reset:
            return 1
        case nil:
            return 0
        }
    }

    override func sectionText(for section: Int) -> SettingsSectionText {
        return Section(rawValue: section)?.text ?? SettingsSectionText()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
        switch Section(rawValue: indexPath.section) {
        case .included:
            configure(cell, with: includedItems[indexPath.row])
            cell.selectionStyle = .none
        case .available:
            configure(cell, with: availableItems[indexPath.row])
            cell.selectionStyle = canAddItems ? .default : .none
            cell.textLabel?.textColor = canAddItems ? .label : .secondaryLabel
        case .reset:
            cell.textLabel?.text = NSLocalizedString("Reset to Default", comment: "")
            cell.textLabel?.textColor = tableView.tintColor
            cell.shouldIndentWhileEditing = false
        case nil:
            break
        }
        return cell
    }

    private func configure(_ cell: UITableViewCell, with item: BottomToolbarItem) {
        cell.textLabel?.text = item.title
        cell.imageView?.image = item.image?.withRenderingMode(.alwaysTemplate)
        cell.imageView?.tintColor = .label
    }

    // MARK: - Editing

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .included:
            return includedItems[indexPath.row].isRemovable
        case .available:
            return canAddItems
        default:
            return false
        }
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        switch Section(rawValue: indexPath.section) {
        case .included:
            return includedItems[indexPath.row].isRemovable ? .delete : .none
        case .available:
            return canAddItems ? .insert : .none
        default:
            return .none
        }
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) != .reset
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch (Section(rawValue: indexPath.section), editingStyle) {
        case (.included, .delete):
            removeItem(at: indexPath.row)
        case (.available, .insert):
            addItem(availableItems[indexPath.row])
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .included && includedItems.count > 1
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        let includedSection = Section.included.rawValue
        if proposedDestinationIndexPath.section < includedSection {
            return IndexPath(row: 0, section: includedSection)
        }
        if proposedDestinationIndexPath.section > includedSection {
            return IndexPath(row: includedItems.count - 1, section: includedSection)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard includedItems.indices.contains(sourceIndexPath.row),
              includedItems.indices.contains(destinationIndexPath.row) else {
            tableView.reloadData()
            return
        }
        let item = includedItems.remove(at: sourceIndexPath.row)
        includedItems.insert(item, at: destinationIndexPath.row)
        save()
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        switch Section(rawValue: indexPath.section) {
        case .available:
            guard canAddItems else { return }
            addItem(availableItems[indexPath.row])
        case .reset:
            includedItems = BottomToolbarItem.defaultItems
            save()
            tableView.reloadData()
        default:
            break
        }
    }

    // MARK: - Changes

    private func addItem(_ item: BottomToolbarItem) {
        guard canAddItems, !includedItems.contains(item) else { return }
        includedItems.append(item)
        save()
        reloadEditableSections()
    }

    private func removeItem(at index: Int) {
        guard includedItems.indices.contains(index), includedItems[index].isRemovable else { return }
        includedItems.remove(at: index)
        save()
        reloadEditableSections()
    }

    private func reloadEditableSections() {
        // Reload both sections together so the add/remove controls reflect the new capacity.
        tableView.reloadSections(
            IndexSet([Section.included.rawValue, Section.available.rawValue]),
            with: .automatic
        )
    }

    private func save() {
        Prefs.AppearanceSettings.bottomToolbarItems = includedItems
        includedItems = Prefs.AppearanceSettings.bottomToolbarItems
    }
}
