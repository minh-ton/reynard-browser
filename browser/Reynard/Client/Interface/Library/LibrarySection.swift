//
//  LibrarySection.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum LibrarySection: Int, CaseIterable {
    private enum UX {
        static let itemSymbolPointSize: CGFloat = 18
    }
    
    case bookmarks
    case history
    case downloads
    case settings
    
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
            return "reynard.book"
        case .history:
            return "reynard.clock"
        case .downloads:
            return "reynard.arrow.down.circle"
        case .settings:
            return "reynard.gearshape"
        }
    }
    
    private var selectedSymbolName: String {
        switch self {
        case .bookmarks:
            return "reynard.book.fill"
        case .history:
            return "reynard.clock.fill"
        case .downloads:
            return "reynard.arrow.down.circle.fill"
        case .settings:
            return "reynard.gearshape.fill"
        }
    }
    
    var tabBarItem: UITabBarItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.itemSymbolPointSize, weight: .regular)
        let item = UITabBarItem(
            title: title,
            image: UIImage(named: symbolName, in: .main, with: configuration),
            selectedImage: UIImage(named: selectedSymbolName, in: .main, with: configuration)
        )
        item.tag = rawValue
        return item
    }
}
