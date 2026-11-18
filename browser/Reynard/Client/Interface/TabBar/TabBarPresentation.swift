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
        
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: UX.visibilityAnimationDuration,
                animations: {
                    self.tabBar.superview?.layoutIfNeeded()
                },
                completion: { [weak self] _ in
                    self?.finishVisibilityChange(to: visibility)
                }
            )
        } else {
            tabBar.superview?.layoutIfNeeded()
            finishVisibilityChange(to: visibility)
        }
    }
    
    func setAlpha(_ alpha: CGFloat) {
        tabBar.alpha = alpha
    }
    
    private func finishVisibilityChange(to visibility: TabBar.Visibility) {
        guard tabBar.visibility == visibility else {
            return
        }
        tabBar.isHidden = visibility != .visible
    }
}
