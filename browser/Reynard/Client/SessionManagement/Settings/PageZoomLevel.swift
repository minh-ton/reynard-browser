//
//  PageZoomLevel.swift
//  Reynard
//
//  Created by Reynard on 23/6/26.
//

import Foundation

enum PageZoomLevel {
    static let defaultPercent = 100
    static let allowedPercents = [50, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]

    static func normalizedPercent(_ percent: Int) -> Int {
        allowedPercents.min { first, second in
            abs(first - percent) < abs(second - percent)
        } ?? defaultPercent
    }

    static func scale(for percent: Int) -> Double {
        Double(normalizedPercent(percent)) / 100
    }

    static func displayTitle(for percent: Int) -> String {
        "\(normalizedPercent(percent))%"
    }

    static func lowerPercent(than percent: Int) -> Int? {
        allowedPercents.last { $0 < normalizedPercent(percent) }
    }

    static func higherPercent(than percent: Int) -> Int? {
        allowedPercents.first { $0 > normalizedPercent(percent) }
    }
}
