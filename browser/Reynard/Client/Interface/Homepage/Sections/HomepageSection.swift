//
//  HomepageSection.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

enum HomepageRecommendation: CaseIterable, Hashable {
    case performance
    case updateAvailable
    case donation
}

enum HomepageSection: CaseIterable, Hashable {
    case recommendation(HomepageRecommendation)
    case privateBrowsing
    case favorites
    case frequentlyVisited
    case recentlyClosedTabs
    
    static var allCases: [HomepageSection] {
        return HomepageRecommendation.allCases.map { .recommendation($0) } + [
            .privateBrowsing,
            .favorites,
            .frequentlyVisited,
            .recentlyClosedTabs,
        ]
    }
}

protocol HomepageSectionDelegate: AnyObject {
    func homepageSection(_ viewController: UIViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition)
    func homepageSection(
        _ viewController: UIViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    )
    func homepageSection(_ viewController: UIViewController, didRequestHideFromSuggestions siteID: Int64)
    func homepageSection(_ viewController: UIViewController, didSelectRecentlyClosedTab id: UUID)
    func homepageSectionDidSelectSettings(_ viewController: UIViewController)
    func homepageSection(_ viewController: UIViewController, didSelectFolder folder: BookmarkFolderSnapshot)
    func homepageDidStartScrolling()
}
