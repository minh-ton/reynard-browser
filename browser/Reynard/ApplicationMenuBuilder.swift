//
//  ApplicationMenuBuilder.swift
//  Reynard
//
//  Created by Minh Ton on 16/8/26.
//

import UIKit

enum ApplicationMenuBuilder {
    static func build(with builder: UIMenuBuilder) {
        guard builder.system == UIMenuSystem.main else {
            return
        }
        
        builder.remove(menu: .close)
        builder.remove(menu: .find)
        builder.remove(menu: .textSize)
        if #available(iOS 15.0, *) {
            builder.remove(menu: .sidebar)
        }
        
        let fileMenu = UIMenu(title: "", options: .displayInline, children: [
            UIKeyCommand(title: NSLocalizedString("New Tab", comment: ""), action: #selector(BrowserViewController.newTabKeyCommand(_:)), input: "t", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("New Private Tab", comment: ""), action: #selector(BrowserViewController.newPrivateTabKeyCommand(_:)), input: "n", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: NSLocalizedString("Open Location", comment: ""), action: #selector(BrowserViewController.focusAddressBarKeyCommand(_:)), input: "l", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Close Tab", comment: ""), action: #selector(BrowserViewController.closeTabKeyCommand(_:)), input: "w", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Downloads", comment: ""), action: #selector(BrowserViewController.showDownloadsKeyCommand(_:)), input: "j", modifierFlags: .command),
        ])
        builder.insertChild(fileMenu, atEndOfMenu: .file)
        
        let editMenu = UIMenu(title: "", options: .displayInline, children: [
            UIKeyCommand(title: NSLocalizedString("Find in Page", comment: ""), action: #selector(BrowserViewController.findInPageKeyCommand(_:)), input: "f", modifierFlags: .command),
        ])
        builder.insertChild(editMenu, atEndOfMenu: .edit)
        
        let viewMenu = UIMenu(title: "", options: .displayInline, children: [
            UIKeyCommand(title: NSLocalizedString("Reload Page", comment: ""), action: #selector(BrowserViewController.reloadPageKeyCommand(_:)), input: "r", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Hard Reload Page", comment: ""), action: #selector(BrowserViewController.hardReloadPageKeyCommand(_:)), input: "r", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: NSLocalizedString("Zoom In", comment: ""), action: #selector(BrowserViewController.zoomInKeyCommand(_:)), input: "+", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Zoom Out", comment: ""), action: #selector(BrowserViewController.zoomOutKeyCommand(_:)), input: "-", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Actual Size", comment: ""), action: #selector(BrowserViewController.actualSizeKeyCommand(_:)), input: "0", modifierFlags: .command),
            UIKeyCommand(title: NSLocalizedString("Show Tab Overview", comment: ""), action: #selector(BrowserViewController.showTabOverviewKeyCommand(_:)), input: "\\", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: NSLocalizedString("Show or Hide Sidebar", comment: ""), action: #selector(BrowserViewController.toggleSidebarKeyCommand(_:)), input: "l", modifierFlags: [.command, .shift]),
        ])
        builder.insertChild(viewMenu, atEndOfMenu: .view)
        
        let historyMenu = UIMenu(
            title: NSLocalizedString("History", comment: ""),
            identifier: .reynardHistory,
            children: [
                UIKeyCommand(title: NSLocalizedString("Back", comment: ""), action: #selector(BrowserViewController.goBackKeyCommand(_:)), input: "[", modifierFlags: .command),
                UIKeyCommand(title: NSLocalizedString("Forward", comment: ""), action: #selector(BrowserViewController.goForwardKeyCommand(_:)), input: "]", modifierFlags: .command),
                UIKeyCommand(title: NSLocalizedString("Show History", comment: ""), action: #selector(BrowserViewController.showHistoryKeyCommand(_:)), input: "y", modifierFlags: .command),
                UIKeyCommand(title: NSLocalizedString("Reopen Last Closed Tab", comment: ""), action: #selector(BrowserViewController.reopenLastClosedTabKeyCommand(_:)), input: "t", modifierFlags: [.command, .shift]),
            ]
        )
        builder.insertSibling(historyMenu, beforeMenu: .window)
        
        let bookmarksMenu = UIMenu(
            title: NSLocalizedString("Bookmarks", comment: ""),
            identifier: .reynardBookmarks,
            children: [
                UIKeyCommand(title: NSLocalizedString("Show Bookmarks", comment: ""), action: #selector(BrowserViewController.showBookmarksKeyCommand(_:)), input: "o", modifierFlags: [.command, .shift]),
                UIKeyCommand(title: NSLocalizedString("Add Bookmark", comment: ""), action: #selector(BrowserViewController.addBookmarkKeyCommand(_:)), input: "d", modifierFlags: .command),
                UIKeyCommand(title: NSLocalizedString("Edit Bookmarks", comment: ""), action: #selector(BrowserViewController.editBookmarksKeyCommand(_:)), input: "b", modifierFlags: [.alternate, .command]),
            ]
        )
        builder.insertSibling(bookmarksMenu, afterMenu: .reynardHistory)
        
        let tabCommands = (1...9).map { number in
            UIKeyCommand(
                title: String(format: NSLocalizedString("Show Tab %d", comment: ""), number),
                image: nil,
                action: #selector(BrowserViewController.selectTabKeyCommand(_:)),
                input: String(number),
                modifierFlags: .command,
                propertyList: NSNumber(value: number),
                alternates: [],
                discoverabilityTitle: nil,
                attributes: [],
                state: .off
            )
        }
        let windowMenu = UIMenu(title: "", options: .displayInline, children: [
            UIKeyCommand(title: NSLocalizedString("Previous Tab", comment: ""), action: #selector(BrowserViewController.previousTabKeyCommand(_:)), input: "[", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: NSLocalizedString("Next Tab", comment: ""), action: #selector(BrowserViewController.nextTabKeyCommand(_:)), input: "]", modifierFlags: [.command, .shift]),
        ] + tabCommands + [
            UIKeyCommand(title: NSLocalizedString("Close Other Tabs", comment: ""), action: #selector(BrowserViewController.closeOtherTabsKeyCommand(_:)), input: "w", modifierFlags: [.alternate, .command]),
        ])
        builder.insertChild(windowMenu, atEndOfMenu: .window)
    }
}

private extension UIMenu.Identifier {
    static let reynardHistory = UIMenu.Identifier("com.reynard.menu.history")
    static let reynardBookmarks = UIMenu.Identifier("com.reynard.menu.bookmarks")
}
