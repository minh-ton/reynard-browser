//
//  PageZoomLevels.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import Foundation
import GeckoView

enum PageZoomLevels {
    static let defaultLevel = PageZoomViewportPolicy.defaultLevel
    static let all = PageZoomViewportPolicy.supportedLevels
    
    static func displayText(for level: Int) -> String {
        return "\(level)%"
    }
}
