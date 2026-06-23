//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit

enum AddressBarMenu {
    private struct Identifier {
        static let addressBarMenu = UIMenu.Identifier("com.minh-ton.Reynard.AddressBarMenu")
        static let manageAddonsMenu = UIMenu.Identifier("com.minh-ton.Reynard.AddressBarMenu.ManageAddons")
    }
    
    struct AddonItem {
        let menuItem: AddonMenuItem
        let image: UIImage?
    }
    
    struct PageZoomState {
        let percent: Int
        let defaultPercent: Int
        let hasSiteOverride: Bool
        let canZoomOut: Bool
        let canZoomIn: Bool
    }

    static func makeMenu(
        selectedURL: String?,
        usesDesktopWebsite: Bool?,
        pageZoom: PageZoomState?,
        addonItems: [AddonItem],
        onAddonSelected: @escaping (AddonMenuItem) -> Void,
        onChangeWebsiteMode: @escaping () -> Void,
        onWebsiteSettings: @escaping () -> Void,
        onPageZoomOut: @escaping () -> Void,
        onPageZoomIn: @escaping () -> Void,
        onPageZoomReset: @escaping () -> Void,
        onBookmark: @escaping (Bool) -> Void
    ) -> UIMenu {
        var tabActions: [UIMenuElement] = []
        
        let url = selectedURL.flatMap(URL.init(string:))
        if let url,
           url.host != nil {
            let title = BookmarkStore.shared.bookmark(savedFor: url) == nil ? "Add Bookmark" : "Edit Bookmark"
            tabActions.append(UIAction(title: title, image: UIImage(named: "reynard.book")) { _ in
                onBookmark(false)
            })
            
            if !BookmarkStore.shared.isSavedInFavorites(url) {
                tabActions.append(UIAction(title: "Add to Favorites", image: UIImage(named: "reynard.star")) { _ in
                    onBookmark(true)
                })
            }
        }
        
        let addonsChildren: [UIMenuElement]
        if addonItems.isEmpty {
            addonsChildren = [
                UIAction(
                    title: "No Add-ons",
                    image: UIImage(named: "reynard.puzzlepiece.extension"),
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
                image: UIImage(named: "reynard.puzzlepiece.extension"),
                identifier: Identifier.manageAddonsMenu,
                children: addonsChildren
            )
        ]
        
        if let isDesktop = usesDesktopWebsite {
            let title = isDesktop ? "Request Mobile Website" : "Request Desktop Website"
            let imageName = isDesktop ? "reynard.smartphone" : "reynard.desktopcomputer"
            pageActions.append(UIAction(title: title, image: UIImage(named: imageName)) { _ in
                onChangeWebsiteMode()
            })
        }
        
        if let pageZoom {
            pageActions.append(pageZoomMenu(
                state: pageZoom,
                onZoomOut: onPageZoomOut,
                onZoomIn: onPageZoomIn,
                onReset: onPageZoomReset
            ))
        }

        var settingsActions: [UIMenuElement] = []
        if url?.host != nil {
            settingsActions.append(UIAction(title: "Website Settings", image: UIImage(named: "reynard.gear")) { _ in
                onWebsiteSettings()
            })
        }
        
        let children = tabActions + [UIMenu(options: .displayInline, children: pageActions)] + [UIMenu(options: .displayInline, children: settingsActions)]
        
        return UIMenu(title: "", image: nil, identifier: Identifier.addressBarMenu, options: [], children: children)
    }

    private static func pageZoomMenu(
        state: PageZoomState,
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> UIMenu {
        let zoomOutAttributes: UIMenuElement.Attributes = state.canZoomOut ? [] : .disabled
        let zoomInAttributes: UIMenuElement.Attributes = state.canZoomIn ? [] : .disabled
        let resetAttributes: UIMenuElement.Attributes = state.hasSiteOverride ? [] : .disabled
        let defaultTitle = PageZoomLevel.displayTitle(for: state.defaultPercent)

        return UIMenu(
            title: "Page Zoom",
            image: UIImage(systemName: "textformat.size"),
            children: [
                UIAction(
                    title: "Zoom Out",
                    image: UIImage(systemName: "minus.magnifyingglass"),
                    attributes: zoomOutAttributes
                ) { _ in
                    onZoomOut()
                },
                UIAction(
                    title: PageZoomLevel.displayTitle(for: state.percent),
                    attributes: .disabled
                ) { _ in },
                UIAction(
                    title: "Zoom In",
                    image: UIImage(systemName: "plus.magnifyingglass"),
                    attributes: zoomInAttributes
                ) { _ in
                    onZoomIn()
                },
                UIAction(
                    title: "Reset to Default (\(defaultTitle))",
                    image: UIImage(named: "reynard.arrow.clockwise"),
                    attributes: resetAttributes
                ) { _ in
                    onReset()
                },
            ]
        )
    }
}
