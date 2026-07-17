//
//  BottomToolbarLayoutPolicy.swift
//  Reynard
//

import Foundation

enum BottomToolbarLayoutPolicy {
    struct Layout: Equatable {
        let rowActionCounts: [Int]
        let targetWidth: CGFloat

        var rowCount: Int { rowActionCounts.count }
        var actionCount: Int { rowActionCounts.reduce(0, +) }
        var requiredHeight: CGFloat {
            guard rowCount > 0 else {
                return 0
            }
            return CGFloat(rowCount) * minimumTargetSize +
                CGFloat(rowCount - 1) * verticalSpacing
        }
    }

    static let minimumTargetSize: CGFloat = 44
    static let horizontalInset: CGFloat = 8
    static let spacing: CGFloat = 0
    static let verticalSpacing: CGFloat = 0
    static let maximumConfiguredActions = 10

    static func visibleActionCount(configuredCount: Int) -> Int {
        min(max(0, configuredCount), maximumConfiguredActions)
    }

    static func layout(
        containerWidth: CGFloat,
        safeAreaLeft: CGFloat = 0,
        safeAreaRight: CGFloat = 0,
        configuredCount: Int
    ) -> Layout {
        let actionCount = visibleActionCount(configuredCount: configuredCount)
        guard actionCount > 0 else {
            return Layout(rowActionCounts: [], targetWidth: 0)
        }

        let availableWidth = max(
            0,
            containerWidth - safeAreaLeft - safeAreaRight - (2 * horizontalInset)
        )
        let maximumColumnCount = max(
            1,
            Int(floor((availableWidth + spacing) / (minimumTargetSize + spacing)))
        )
        let rowCount = Int(ceil(Double(actionCount) / Double(maximumColumnCount)))
        let columnCount = Int(ceil(Double(actionCount) / Double(rowCount)))
        var remainingActionCount = actionCount
        let rowActionCounts = (0..<rowCount).map { _ -> Int in
            let count = min(columnCount, remainingActionCount)
            remainingActionCount -= count
            return count
        }
        let targetWidth = (
            availableWidth - CGFloat(max(0, columnCount - 1)) * spacing
        ) / CGFloat(columnCount)
        return Layout(rowActionCounts: rowActionCounts, targetWidth: targetWidth)
    }
}
