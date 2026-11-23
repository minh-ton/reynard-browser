//
//  ToolbarItem.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import Foundation

enum ToolbarItem: String, CaseIterable, Codable {
    case back
    case forward
    case share
    case library
    case tabOverview
    case newTab
    case history
    case bookmarks
    case addBookmark
    case downloads
    case settings
    case reader
    case findInPage
    case pageZoom
    case hideToolbar
    
    var title: String {
        switch self {
        case .back: return NSLocalizedString("Back", comment: "")
        case .forward: return NSLocalizedString("Forward", comment: "")
        case .share: return NSLocalizedString("Share", comment: "")
        case .library: return NSLocalizedString("Menu", comment: "")
        case .tabOverview: return NSLocalizedString("Tabs", comment: "")
        case .newTab: return NSLocalizedString("New Tab", comment: "")
        case .history: return NSLocalizedString("History", comment: "")
        case .bookmarks: return NSLocalizedString("Bookmarks", comment: "")
        case .addBookmark: return NSLocalizedString("Add Bookmark", comment: "")
        case .downloads: return NSLocalizedString("Downloads", comment: "")
        case .settings: return NSLocalizedString("Settings", comment: "")
        case .reader: return NSLocalizedString("Show Reader", comment: "")
        case .findInPage: return NSLocalizedString("Find in Page", comment: "")
        case .pageZoom: return NSLocalizedString("Page Zoom", comment: "")
        case .hideToolbar: return NSLocalizedString("Hide Toolbar", comment: "")
        }
    }
    
    var symbolName: String {
        switch self {
        case .back: return "reynard.chevron.backward"
        case .forward: return "reynard.chevron.forward"
        case .share: return "reynard.square.and.arrow.up"
        case .library: return "reynard.ellipsis.circle"
        case .tabOverview: return "reynard.square.on.square"
        case .newTab: return "reynard.plus"
        case .history: return "reynard.clock"
        case .bookmarks: return "reynard.book"
        case .addBookmark: return "reynard.bookmark"
        case .downloads: return "reynard.arrow.down.circle"
        case .settings: return "reynard.gearshape"
        case .reader: return "reynard.text.page"
        case .findInPage: return "reynard.text.page.badge.magnifyingglass"
        case .pageZoom: return "reynard.textformat.size"
        case .hideToolbar: return "reynard.arrow.up.left.and.arrow.down.right"
        }
    }
}

enum ToolbarPlacement {
    case bottomToolbar
    case topToolbar
    
    init(chromeMode: BrowserChromeMode) {
        self = chromeMode == .pad ? .topToolbar : .bottomToolbar
    }
    
    var defaultItems: [ToolbarItem] {
        switch self {
        case .bottomToolbar: return [.back, .forward, .share, .library, .tabOverview]
        case .topToolbar: return [.share, .newTab, .tabOverview]
        }
    }
    
    var maximumItemCount: Int {
        switch self {
        case .bottomToolbar: return 6
        case .topToolbar: return 4
        }
    }
    
    var availableItems: [ToolbarItem] {
        switch self {
        case .bottomToolbar:
            return ToolbarItem.allCases
        case .topToolbar:
            return ToolbarItem.allCases.filter { ![.back, .forward, .library].contains($0) }
        }
    }
    
    var items: [ToolbarItem] {
        get {
            switch self {
            case .bottomToolbar: return Prefs.AppearanceSettings.bottomToolbarItems
            case .topToolbar: return Prefs.AppearanceSettings.topToolbarItems
            }
        }
        nonmutating set {
            switch self {
            case .bottomToolbar: Prefs.AppearanceSettings.bottomToolbarItems = newValue
            case .topToolbar: Prefs.AppearanceSettings.topToolbarItems = newValue
            }
        }
    }
}
