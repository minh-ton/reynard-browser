//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit

enum AddressBarMenu {
    private struct Identifier {
        static let addressBarMenu = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu")
        static let manageAddonsMenu = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu.manage-addons")
    }

    struct AddonItem {
        let menuItem: AddonMenuItem
        let image: UIImage?
    }

    // MARK: - Menu Construction
    
    static func makeMenu(
        selectedTab: Tab?,
        selectedURL: String?,
        addonItems: [AddonItem],
        onAddonSelected: @escaping (AddonMenuItem) -> Void,
        onChangeWebsiteMode: @escaping () -> Void,
        onWebsiteSettings: @escaping () -> Void,
        onBookmark: @escaping (Bool) -> Void
    ) -> UIMenu {
        var tabActions: [UIMenuElement] = []
        
        let url = selectedURL.flatMap(URL.init(string:))
        if let url,
           url.host != nil {
            let title = BookmarkStore.shared.bookmark(for: url) == nil ? "Add Bookmark" : "Edit Bookmark"
            tabActions.append(UIAction(title: title, image: UIImage(systemName: "book")) { _ in
                onBookmark(false)
            })
            
            if !BookmarkStore.shared.containsBookmarkInFavoritesHierarchy(for: url) {
                tabActions.append(UIAction(title: "Add to Favorites", image: UIImage(systemName: "star")) { _ in
                    onBookmark(true)
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
                    onAddonSelected(item.menuItem)
                }
            }
        }
        
        var pageActions: [UIMenuElement] = [
            UIMenu(
                title: "Manage Add-ons",
                image: UIImage(systemName: "puzzlepiece.extension"),
                identifier: Identifier.manageAddonsMenu,
                children: addonsChildren
            )
        ]
        
        if let selectedTab,
           let selectedURL,
           let isDesktop = GeckoSessionController.shared.isDesktopMode(for: selectedURL, tabID: selectedTab.id) {
            let title = isDesktop ? "Request Mobile Website" : "Request Desktop Website"
            let imageName = isDesktop ? "iphone" : "desktopcomputer"
            pageActions.append(UIAction(title: title, image: UIImage(systemName: imageName)) { _ in
                onChangeWebsiteMode()
            })
        }
        
        var settingsActions: [UIMenuElement] = []
        if url?.host != nil {
            settingsActions.append(UIAction(title: "Website Settings", image: UIImage(systemName: "gear")) { _ in
                onWebsiteSettings()
            })
        }
        
        let children = tabActions + [UIMenu(options: .displayInline, children: pageActions)] + [UIMenu(options: .displayInline, children: settingsActions)]
        
        return UIMenu(title: "", image: nil, identifier: Identifier.addressBarMenu, options: [], children: children)
    }
}
