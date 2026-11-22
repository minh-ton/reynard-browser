//
//  BottomToolbarItem.swift
//  Reynard
//

import UIKit

/// A button that can be placed in the customizable bottom toolbar.
enum BottomToolbarItem: String, CaseIterable, Codable {
    case back
    case forward
    case share
    case newTab
    case menu
    case tabOverview
    case bookmarks
    case history
    case reload
    case findInPage
    case readerMode

    static let defaultItems: [BottomToolbarItem] = [.back, .forward, .share, .menu, .tabOverview]

    /// The toolbar has room for this many configurable buttons on the narrowest supported iPhone,
    /// leaving space for the automatically shown downloads button.
    static let maximumItemCount = 6

    /// The menu button is the only way to reach the library and settings, so it can't be removed.
    var isRemovable: Bool {
        return self != .menu
    }

    var title: String {
        switch self {
        case .back:
            return NSLocalizedString("Back", comment: "")
        case .forward:
            return NSLocalizedString("Forward", comment: "")
        case .share:
            return NSLocalizedString("Share", comment: "")
        case .newTab:
            return NSLocalizedString("New Tab", comment: "")
        case .menu:
            return NSLocalizedString("Menu", comment: "")
        case .tabOverview:
            return NSLocalizedString("Tabs", comment: "")
        case .bookmarks:
            return NSLocalizedString("Bookmarks", comment: "")
        case .history:
            return NSLocalizedString("History", comment: "")
        case .reload:
            return NSLocalizedString("Reload", comment: "")
        case .findInPage:
            return NSLocalizedString("Find on Page", comment: "")
        case .readerMode:
            return NSLocalizedString("Reader", comment: "")
        }
    }

    var buttonType: ToolbarButton.ButtonType {
        switch self {
        case .back: return .back
        case .forward: return .forward
        case .share: return .share
        case .newTab: return .newTab
        case .menu: return .library
        case .tabOverview: return .tabOverview
        case .bookmarks: return .bookmarks
        case .history: return .history
        case .reload: return .reload
        case .findInPage: return .findInPage
        case .readerMode: return .readerMode
        }
    }

    var image: UIImage? {
        return UIImage(named: buttonType.symbolName)
    }

    /// Removes duplicates and unknown entries, and guarantees the menu button is present.
    static func sanitized(_ items: [BottomToolbarItem]) -> [BottomToolbarItem] {
        var seen = Set<BottomToolbarItem>()
        var result = items.filter { seen.insert($0).inserted }
        if !result.contains(.menu) {
            result.append(.menu)
        }
        if result.count > maximumItemCount {
            let removable = result.filter { $0.isRemovable }
            let overflow = Set(removable.suffix(result.count - maximumItemCount))
            result.removeAll { overflow.contains($0) }
        }
        return result
    }
}
