//
//  LibrarySection.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum LibrarySection: Int, CaseIterable {
    // MARK: - Cases

    case bookmarks
    case history
    case downloads
    case settings

    // MARK: - Display

    var title: String {
        switch self {
        case .bookmarks:
            return "Bookmarks"
        case .history:
            return "History"
        case .downloads:
            return "Downloads"
        case .settings:
            return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .bookmarks:
            return "book"
        case .history:
            return "clock"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gearshape"
        }
    }

    private var selectedSymbolName: String {
        switch self {
        case .bookmarks:
            return "book.fill"
        case .history:
            return "clock.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    // MARK: - Tab Bar

    var tabBarItem: UITabBarItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: LibraryTabBarStyle.UX.itemSymbolPointSize, weight: .regular)
        let item = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbolName, withConfiguration: configuration),
            selectedImage: UIImage(systemName: selectedSymbolName, withConfiguration: configuration)
        )
        item.tag = rawValue
        return item
    }
}
