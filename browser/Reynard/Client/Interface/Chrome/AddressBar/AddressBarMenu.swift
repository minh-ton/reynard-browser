//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit

enum AddressBarMenu {
    struct AddonItem {
        let menuItem: AddonMenuItem
        let image: UIImage?
    }
    
    private static let rootIdentifier = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu")
    private static let manageAddonsIdentifier = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu.manage-addons")
    static let presentAddonSettingsNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.present-addon-settings")
    static let presentWebsiteSettingsNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.present-website-settings")
    static let changeWebsiteModeNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.toggle-website-mode")
    static let addBookmarkNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.add-bookmark")
    
    static func makeMenu(
        selectedTab: Tab?,
        selectedURL: String?,
        addonItems: [AddonItem]
    ) -> UIMenu? {
        var tabActions: [UIMenuElement] = []
        
        let url = selectedURL.flatMap(URL.init(string:))
        if let url,
           url.host != nil {
            let title = BookmarkStore.shared.bookmark(for: url) == nil ? "Add Bookmark" : "Edit Bookmark"
            tabActions.append(UIAction(title: title, image: UIImage(systemName: "book")) { _ in
                NotificationCenter.default.post(name: addBookmarkNotification, object: nil)
            })
            
            if !BookmarkStore.shared.containsBookmarkInFavoritesHierarchy(for: url) {
                tabActions.append(UIAction(title: "Add to Favorites", image: UIImage(systemName: "star")) { _ in
                    NotificationCenter.default.post(
                        name: addBookmarkNotification,
                        object: nil,
                        userInfo: ["addToFavorites": true]
                    )
                })
            }
        }
        
        let addonsChildren: [UIMenuElement]
        if addonItems.isEmpty {
            addonsChildren = [
                UIAction(
                    title: "No Add-ons",
                    image: UIImage(systemName: "puzzlepiece.extension"),
                    attributes: .disabled
                ) { _ in }
            ]
        } else {
            addonsChildren = addonItems.map { item in
                UIAction(title: item.menuItem.title, image: item.image) { _ in
                    NotificationCenter.default.post(
                        name: presentAddonSettingsNotification,
                        object: nil,
                        userInfo: ["addonItem": item.menuItem]
                    )
                }
            }
        }
        
        var pageActions: [UIMenuElement] = [
            UIMenu(
                title: "Manage Add-ons",
                image: UIImage(systemName: "puzzlepiece.extension"),
                identifier: manageAddonsIdentifier,
                children: addonsChildren
            )
        ]
        
        if let selectedTab,
           let selectedURL,
           let isDesktop = GeckoSessionController.shared.isDesktopMode(for: selectedURL, tabID: selectedTab.id) {
            let title = isDesktop ? "Request Mobile Website" : "Request Desktop Website"
            let imageName = isDesktop ? "iphone" : "desktopcomputer"
            pageActions.append(UIAction(title: title, image: UIImage(systemName: imageName)) { _ in
                NotificationCenter.default.post(name: changeWebsiteModeNotification, object: nil)
            })
        }
        
        var settingsActions: [UIMenuElement] = []
        if url?.host != nil {
            settingsActions.append(UIAction(title: "Website Settings", image: UIImage(systemName: "gear")) { _ in
                NotificationCenter.default.post(name: presentWebsiteSettingsNotification, object: nil)
            })
        }
        
        let children = tabActions + [UIMenu(options: .displayInline, children: pageActions)] + [UIMenu(options: .displayInline, children: settingsActions)]
        
        guard !children.isEmpty else {
            return nil
        }
        
        return UIMenu(title: "", image: nil, identifier: rootIdentifier, options: [], children: children)
    }
}
