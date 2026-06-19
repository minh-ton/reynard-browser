//
//  LibraryTabBarStyle.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum LibraryTabBarStyle {
    private enum UX {
        static let itemTitleFontSize: CGFloat = 10
    }
    
    static func apply(to tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: UX.itemTitleFontSize, weight: .regular)]
        
        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = .secondaryLabel
            itemAppearance.normal.titleTextAttributes = titleAttributes.merging([.foregroundColor: UIColor.secondaryLabel]) { _, new in new }
            itemAppearance.selected.iconColor = .label
            itemAppearance.selected.titleTextAttributes = titleAttributes.merging([.foregroundColor: UIColor.label]) { _, new in new }
        }
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
    }
}
