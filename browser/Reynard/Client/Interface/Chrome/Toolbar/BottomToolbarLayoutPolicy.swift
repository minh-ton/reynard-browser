//
//  BottomToolbarLayoutPolicy.swift
//  Reynard
//

import Foundation

enum BottomToolbarLayoutPolicy {
    static let minimumTargetSize: CGFloat = 44
    static let horizontalInset: CGFloat = 8
    static let spacing: CGFloat = 0
    static let maximumConfiguredActions = 10

    static func visibleActionCount(configuredCount: Int) -> Int {
        min(max(0, configuredCount), maximumConfiguredActions)
    }
}
