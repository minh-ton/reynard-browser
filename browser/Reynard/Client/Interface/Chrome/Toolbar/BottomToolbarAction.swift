//
//  BottomToolbarAction.swift
//  Reynard
//

import Foundation

enum BottomToolbarAction: String, CaseIterable {
    case back
    case forward
    case reload
    case share
    case pageZoom
    case bookmarks
    case history
    case downloads
    case settings
    case newTab
    case closeTab
    case tabOverview

    static let defaultActions: [BottomToolbarAction] = [
        .back, .forward, .share, .bookmarks, .downloads, .tabOverview, .settings,
    ]

    static let optionalActions = allCases.filter { $0 != .settings }

    static func normalized(_ actions: [BottomToolbarAction]) -> [BottomToolbarAction] {
        var seen = Set<BottomToolbarAction>()
        let uniqueActions = actions.filter { seen.insert($0).inserted }
        let settingsIndex = uniqueActions.firstIndex(of: .settings)
        var normalizedActions = Array(uniqueActions
            .filter { $0 != .settings }
            .prefix(BottomToolbarLayoutPolicy.maximumConfiguredActions - 1))
        normalizedActions.insert(
            .settings,
            at: min(settingsIndex ?? normalizedActions.count, normalizedActions.count)
        )
        return normalizedActions
    }

    static func displayedActions(from configuredActions: [BottomToolbarAction]) -> [BottomToolbarAction] {
        normalized(configuredActions)
    }

    var isRemovableFromToolbar: Bool {
        self != .settings
    }

    var title: String {
        switch self {
        case .back: return NSLocalizedString("Back", comment: "")
        case .forward: return NSLocalizedString("Forward", comment: "")
        case .reload: return NSLocalizedString("Reload", comment: "")
        case .share: return NSLocalizedString("Share", comment: "")
        case .pageZoom: return NSLocalizedString("Page Zoom", comment: "")
        case .bookmarks: return NSLocalizedString("Bookmarks", comment: "")
        case .history: return NSLocalizedString("History", comment: "")
        case .downloads: return NSLocalizedString("Downloads", comment: "")
        case .settings: return NSLocalizedString("Settings", comment: "")
        case .newTab: return NSLocalizedString("New Tab", comment: "")
        case .closeTab: return NSLocalizedString("Close Tab", comment: "")
        case .tabOverview: return NSLocalizedString("Tabs", comment: "")
        }
    }

    var imageName: String {
        switch self {
        case .back: return "reynard.chevron.backward"
        case .forward: return "reynard.chevron.forward"
        case .reload: return "reynard.arrow.clockwise"
        case .share: return "reynard.square.and.arrow.up"
        case .pageZoom: return "reynard.textformat.size"
        case .bookmarks: return "reynard.book"
        case .history: return "reynard.clock"
        case .downloads: return "reynard.arrow.down.circle"
        case .settings: return "reynard.gearshape"
        case .newTab: return "reynard.plus"
        case .closeTab: return "reynard.xmark"
        case .tabOverview: return "reynard.square.on.square"
        }
    }
}

enum BottomToolbarShortcutPolicy {
    enum Button {
        case closeTab
        case newTab
    }

    static func longPressAction(
        for button: Button,
        closeTabOpensNewTab: Bool,
        newTabClosesTab: Bool
    ) -> BottomToolbarAction? {
        switch button {
        case .closeTab:
            return closeTabOpensNewTab ? .newTab : nil
        case .newTab:
            return newTabClosesTab ? .closeTab : nil
        }
    }
}
