//
//  LibrarySharedUtils.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum LibrarySharedUtils {
    private enum UX {
        static let groupedSectionHeaderLeadingInset: CGFloat = 24
        static let groupedSectionHeaderTrailingInset: CGFloat = 16
        static let groupedSectionHeaderTopInset: CGFloat = 10
        static let groupedSectionHeaderBottomInset: CGFloat = 6
        static let groupedSectionHeaderFontSize: CGFloat = 15
    }
    
    static func makeGroupedSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemGroupedBackground
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UX.groupedSectionHeaderFontSize, weight: .semibold)
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
    
    static func alignSeparatorWithReadableContent(in cell: UITableViewCell) {
        cell.contentView.layoutIfNeeded()
        let guideFrame = cell.convert(cell.contentView.layoutMarginsGuide.layoutFrame, from: cell.contentView)
        cell.separatorInset.right = cell.bounds.width - guideFrame.maxX
    }
    
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
    
    static func openLinkInBrowser(_ urlString: String, from viewController: UIViewController) {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty,
              let browserViewController = resolvedBrowserViewController(from: viewController) else {
            return
        }
        
        let openTab = {
            browserViewController.loadViewIfNeeded()
            guard browserViewController.tabManager.createRegularTab(
                selecting: true,
                target: .end,
                url: trimmedURLString,
                loadImmediately: true
            ) != nil else {
                return
            }
            browserViewController.refreshAddressBar()
        }
        
        if viewController.navigationController?.presentingViewController is BrowserViewController {
            viewController.navigationController?.dismiss(animated: true, completion: openTab)
        } else {
            openTab()
        }
    }
    
    static func resolvedBrowserViewController(from viewController: UIViewController) -> BrowserViewController? {
        if let sidebarViewController = viewController.splitViewController as? SidebarViewController {
            return sidebarViewController.contentBrowser.sidebarContentViewController as? BrowserViewController
        }
        
        if let browserViewController = viewController.navigationController?.presentingViewController as? BrowserViewController {
            return browserViewController
        }
        
        return viewController.view.window?.rootViewController.flatMap { resolvedBrowserViewController(in: $0) }
    }
    
    static func resolvedBrowserViewController(in controller: UIViewController) -> BrowserViewController? {
        if let browserViewController = controller as? BrowserViewController {
            return browserViewController
        }
        
        if let navigationController = controller as? UINavigationController {
            return navigationController.viewControllers.compactMap { resolvedBrowserViewController(in: $0) }.first
        }
        
        if let tabBarController = controller as? UITabBarController,
           let viewControllers = tabBarController.viewControllers {
            return viewControllers.compactMap { resolvedBrowserViewController(in: $0) }.first
        }
        
        if let sidebarViewController = controller as? SidebarViewController {
            return sidebarViewController.contentBrowser.sidebarContentViewController as? BrowserViewController
        }
        
        if let presentedViewController = controller.presentedViewController,
           let browserViewController = resolvedBrowserViewController(in: presentedViewController) {
            return browserViewController
        }
        
        return controller.children.compactMap { resolvedBrowserViewController(in: $0) }.first
    }
}

@available(iOS 13.0, *)
final class LibraryLegacyMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    private let makeMenu: () -> UIMenu?
    
    init(makeMenu: @escaping () -> UIMenu?) {
        self.makeMenu = makeMenu
    }
    
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
