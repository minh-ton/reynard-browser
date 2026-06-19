//
//  TabBarPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabBarPresentation {
    private enum UX {
        static let visibilityAnimationDuration: TimeInterval = 0.22
    }
    
    private unowned let tabBar: TabBar
    
    init(tabBar: TabBar) {
        self.tabBar = tabBar
    }
    
    func setVisibility(_ visibility: TabBar.Visibility, animated: Bool) {
        guard visibility != tabBar.visibility else {
            return
        }
        
        if visibility == .visible {
            tabBar.isHidden = false
        }
        tabBar.applyVisibility(visibility)
        
        let layoutChanges = {
            self.tabBar.superview?.layoutIfNeeded()
            return
        }
        let hideCompletion: (Bool) -> Void = { _ in
            self.tabBar.isHidden = visibility != .visible
        }
        
        if animated {
            UIView.animate(
                withDuration: UX.visibilityAnimationDuration,
                animations: layoutChanges,
                completion: hideCompletion
            )
        } else {
            layoutChanges()
            hideCompletion(true)
        }
    }
    
    func setAlpha(_ alpha: CGFloat) {
        tabBar.alpha = alpha
    }
}
