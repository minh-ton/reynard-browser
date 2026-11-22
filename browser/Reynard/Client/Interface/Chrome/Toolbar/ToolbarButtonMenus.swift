//
//  ToolbarButtonMenus.swift
//  Reynard
//
//  Created by Minh Ton on 14/8/26.
//

import GeckoView
import UIKit

final class ToolbarButtonMenus {
    enum NavigationDirection {
        case back
        case forward
    }
    
    private final class NavigationMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let direction: NavigationDirection
        private let isReversed: Bool
        private let itemsProvider: (NavigationDirection) -> [GeckoSessionHistoryItem]
        private let onSelect: (NavigationDirection, Int) -> Void
        
        init(
            direction: NavigationDirection,
            isReversed: Bool,
            itemsProvider: @escaping (NavigationDirection) -> [GeckoSessionHistoryItem],
            onSelect: @escaping (NavigationDirection, Int) -> Void
        ) {
            self.direction = direction
            self.isReversed = isReversed
            self.itemsProvider = itemsProvider
            self.onSelect = onSelect
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            let items = itemsProvider(direction)
            guard !items.isEmpty else {
                return nil
            }
            
            let actions: [UIAction]
            if isReversed {
                actions = items.enumerated().reversed().map { index, item in
                    makeAction(for: item, at: index)
                }
            } else {
                actions = items.enumerated().map { index, item in
                    makeAction(for: item, at: index)
                }
            }
            let menu = UIMenu(title: "", children: actions)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
        
        private func makeAction(
            for item: GeckoSessionHistoryItem,
            at index: Int
        ) -> UIAction {
            let url = displayURL(for: item.url)
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasTitle = !title.isEmpty && title != item.url
            let actionTitle: String
            if #available(iOS 15.0, *) {
                actionTitle = hasTitle ? title : url
            } else {
                actionTitle = url
            }
            
            let action = UIAction(title: actionTitle) { [onSelect, direction] _ in
                onSelect(direction, index)
            }
            if #available(iOS 15.0, *) {
                action.subtitle = url
            }
            return action
        }
        
        private func displayURL(for value: String) -> String {
            guard let url = URL(string: value) else {
                return value
            }
            return URLUtils.displayString(for: url)
        }
    }
    
    private final class RecentlyClosedTabsMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let isAvailable: () -> Bool
        private let itemsProvider: () -> [TabManagementStore.RecentlyClosedTabSnapshot]
        private let onSelect: (UUID) -> Void
        
        init(
            isAvailable: @escaping () -> Bool,
            itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
            onSelect: @escaping (UUID) -> Void
        ) {
            self.isAvailable = isAvailable
            self.itemsProvider = itemsProvider
            self.onSelect = onSelect
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard isAvailable() else {
                return nil
            }
            
            let items = itemsProvider()
            guard !items.isEmpty else {
                return nil
            }
            
            let actions = items.map { makeAction(for: $0) }
            let menu = UIMenu(
                title: NSLocalizedString("Recently Closed Tabs", comment: ""),
                children: actions
            )
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
        
        private func makeAction(for item: TabManagementStore.RecentlyClosedTabSnapshot) -> UIAction {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let actionTitle = title.isEmpty
            ? NSLocalizedString("Untitled", comment: "")
            : title
            let action = UIAction(title: actionTitle) { [onSelect] _ in
                onSelect(item.id)
            }
            
            if #available(iOS 15.0, *),
               let value = item.url?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                action.subtitle = displayURL(for: value)
            }
            return action
        }
        
        private func displayURL(for value: String) -> String {
            guard let url = URL(string: value) else {
                return value
            }
            return URLUtils.displayString(for: url)
        }
    }
    
    private final class LibraryMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let onSelect: (LibrarySection) -> Void
        
        init(onSelect: @escaping (LibrarySection) -> Void) {
            self.onSelect = onSelect
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            let actions = LibrarySection.allCases.map { section in
                UIAction(title: section.title, image: section.tabBarItem.image) { [onSelect] _ in
                    onSelect(section)
                }
            }
            let menu = UIMenu(title: "", children: actions)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
    }
    
    private final class TabOverviewMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let tabCountProvider: () -> Int
        private let onCloseAllTabs: () -> Void
        private let onCloseTab: () -> Void
        private let onNewPrivateTab: () -> Void
        private let onNewTab: () -> Void
        
        init(
            tabCountProvider: @escaping () -> Int,
            onCloseAllTabs: @escaping () -> Void,
            onCloseTab: @escaping () -> Void,
            onNewPrivateTab: @escaping () -> Void,
            onNewTab: @escaping () -> Void
        ) {
            self.tabCountProvider = tabCountProvider
            self.onCloseAllTabs = onCloseAllTabs
            self.onCloseTab = onCloseTab
            self.onNewPrivateTab = onNewPrivateTab
            self.onNewTab = onNewTab
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            let tabCount = tabCountProvider()
            let closeAllTabsAction = UIAction(
                title: String.localizedStringWithFormat(
                    NSLocalizedString("Close %d Tabs", comment: "Tab count"),
                    tabCount
                ),
                image: UIImage(named: "reynard.xmark"),
                attributes: .destructive
            ) { [onCloseAllTabs] _ in
                onCloseAllTabs()
            }
            let closeTabAction = UIAction(
                title: NSLocalizedString("Close This Tab", comment: ""),
                image: UIImage(named: "reynard.xmark"),
                attributes: .destructive
            ) { [onCloseTab] _ in
                onCloseTab()
            }
            let newPrivateTabAction = UIAction(
                title: NSLocalizedString("New Private Tab", comment: ""),
                image: UIImage(named: "reynard.plus.square.fill.on.square.fill")
            ) { [onNewPrivateTab] _ in
                onNewPrivateTab()
            }
            let newTabAction = UIAction(
                title: NSLocalizedString("New Tab", comment: ""),
                image: UIImage(named: "reynard.plus.square.on.square")
            ) { [onNewTab] _ in
                onNewTab()
            }
            var menuChildren: [UIMenuElement] = [
                closeTabAction,
                newPrivateTabAction,
                newTabAction,
            ]
            if tabCount > 1 {
                menuChildren.insert(closeAllTabsAction, at: 0)
            }
            let menu = UIMenu(title: "", children: menuChildren)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
    }
    
    private var navigationMenuDelegates: [NavigationMenuDelegate] = []
    private var recentlyClosedTabsMenuDelegates: [RecentlyClosedTabsMenuDelegate] = []
    private var libraryMenuDelegates: [LibraryMenuDelegate] = []
    private var tabOverviewMenuDelegates: [TabOverviewMenuDelegate] = []
    
    func installNavigationMenus(
        on backButton: ToolbarButton,
        forwardButton: ToolbarButton,
        itemsProvider: @escaping (NavigationDirection) -> [GeckoSessionHistoryItem],
        onSelect: @escaping (NavigationDirection, Int) -> Void,
        isReversed: Bool = true
    ) {
        installNavigationMenu(
            on: backButton,
            direction: .back,
            isReversed: isReversed,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        installNavigationMenu(
            on: forwardButton,
            direction: .forward,
            isReversed: isReversed,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func installLibraryMenus(
        on buttons: [ToolbarButton],
        onSelect: @escaping (LibrarySection) -> Void
    ) {
        buttons.forEach { button in
            let delegate = LibraryMenuDelegate(onSelect: onSelect)
            button.addInteraction(UIContextMenuInteraction(delegate: delegate))
            libraryMenuDelegates.append(delegate)
        }
    }
    
    func installTabOverviewMenus(
        on buttons: [ToolbarButton],
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        buttons.forEach { button in
            let delegate = TabOverviewMenuDelegate(
                tabCountProvider: tabCountProvider,
                onCloseAllTabs: onCloseAllTabs,
                onCloseTab: onCloseTab,
                onNewPrivateTab: onNewPrivateTab,
                onNewTab: onNewTab
            )
            button.addInteraction(UIContextMenuInteraction(delegate: delegate))
            tabOverviewMenuDelegates.append(delegate)
        }
    }
    
    private func installNavigationMenu(
        on button: ToolbarButton,
        direction: NavigationDirection,
        isReversed: Bool,
        itemsProvider: @escaping (NavigationDirection) -> [GeckoSessionHistoryItem],
        onSelect: @escaping (NavigationDirection, Int) -> Void
    ) {
        let delegate = NavigationMenuDelegate(
            direction: direction,
            isReversed: isReversed,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        button.addInteraction(UIContextMenuInteraction(delegate: delegate))
        navigationMenuDelegates.append(delegate)
    }
    
    func installRecentlyClosedTabsMenu(
        on button: ToolbarButton,
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        let delegate = RecentlyClosedTabsMenuDelegate(
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        button.addInteraction(UIContextMenuInteraction(delegate: delegate))
        recentlyClosedTabsMenuDelegates.append(delegate)
    }
}
