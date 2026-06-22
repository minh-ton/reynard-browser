//
//  TabOverviewCardCloseTabButton.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

import UIKit

final class TabOverviewCardCloseTabButton: UIButton {
    var touchTargetScale: CGFloat = 1
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0 else {
            return false
        }
        
        return containsHitTarget(point)
    }
    
    func containsHitTarget(_ point: CGPoint) -> Bool {
        let widthIncrease = bounds.width * (touchTargetScale - 1) / 2
        let heightIncrease = bounds.height * (touchTargetScale - 1) / 2
        let hitFrame = bounds.insetBy(dx: -widthIncrease, dy: -heightIncrease)
        
        return hitFrame.contains(point)
    }
}
