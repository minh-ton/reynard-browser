//
//  BottomToolbarLayoutPolicy.swift
//  Reynard
//

import Foundation

enum BottomToolbarLayoutPolicy {
    static let minimumTargetSize: CGFloat = 44
    static let horizontalInset: CGFloat = 8
    static let spacing: CGFloat = 4
    static let maximumConfiguredActions = 10

    static func availableSlotCount(
        width: CGFloat,
        maximum: Int = maximumConfiguredActions
    ) -> Int {
        let availableWidth = max(0, width - horizontalInset * 2)
        let count = Int((availableWidth + spacing) / (minimumTargetSize + spacing))
        return min(maximum, max(1, count))
    }

    static func directActionCount(configuredCount: Int, availableSlots: Int) -> Int {
        guard configuredCount > availableSlots else {
            return configuredCount
        }
        return max(0, availableSlots - 1)
    }
}
