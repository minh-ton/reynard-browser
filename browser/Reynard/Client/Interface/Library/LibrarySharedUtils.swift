//
//  LibrarySharedUtils.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum LibrarySharedUtils {
    // MARK: - UX

    enum UX {
        static let groupedSectionHeaderHeight: CGFloat = 34
        static let groupedSectionHeaderLeadingInset: CGFloat = 24
        static let groupedSectionHeaderTrailingInset: CGFloat = 16
        static let groupedSectionHeaderTopInset: CGFloat = 10
        static let groupedSectionHeaderBottomInset: CGFloat = 6
    }

    // MARK: - Section Headers

    static func makeGroupedSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemGroupedBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = title

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UX.groupedSectionHeaderLeadingInset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UX.groupedSectionHeaderTrailingInset),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -UX.groupedSectionHeaderBottomInset),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: UX.groupedSectionHeaderTopInset),
        ])

        return container
    }

    // MARK: - Table Headers

    static func syncTableHeaderWidth(_ headerView: UIView, in tableView: UITableView) {
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else {
            return
        }

        var frame = headerView.frame
        guard frame.width != targetWidth else {
            return
        }

        frame.size.width = targetWidth
        headerView.frame = frame
        updateTableHeaderHeight(headerView, in: tableView)
    }

    static func updateTableHeaderHeight(_ headerView: UIView, in tableView: UITableView) {
        headerView.setNeedsLayout()
        headerView.layoutIfNeeded()

        let targetSize = CGSize(width: headerView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = headerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        var frame = headerView.frame
        if frame.height != height {
            frame.size.height = height
            headerView.frame = frame
            tableView.tableHeaderView = headerView
        }
    }

    // MARK: - Gestures

    static func isTapOutsideSearchBar(_ touch: UITouch, in tableView: UITableView, ignoring searchBar: UISearchBar) -> Bool {
        var view = touch.view
        while let currentView = view {
            if currentView === searchBar {
                return false
            }
            view = currentView.superview
        }

        return true
    }

    // MARK: - Separators

    static func alignSeparatorWithReadableContent(in cell: UITableViewCell) {
        cell.contentView.layoutIfNeeded()
        let guideFrame = cell.convert(cell.contentView.layoutMarginsGuide.layoutFrame, from: cell.contentView)
        cell.separatorInset.right = cell.bounds.width - guideFrame.maxX
    }

    // MARK: - Legacy Menus

    @available(iOS 13.0, *)
    static func presentLegacyContextMenu(from button: UIButton) {
        guard let interaction = button.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }

        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }

        let center = NSValue(cgPoint: CGPoint(x: button.bounds.midX, y: button.bounds.midY))
        _ = interaction.perform(selector, with: center)
    }
}

@available(iOS 13.0, *)
final class LibraryLegacyMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    // MARK: - State

    private let makeMenu: () -> UIMenu?

    // MARK: - Lifecycle

    init(makeMenu: @escaping () -> UIMenu?) {
        self.makeMenu = makeMenu
    }

    // MARK: - UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu = makeMenu() else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            menu
        }
    }
}
