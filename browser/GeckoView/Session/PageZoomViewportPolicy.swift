//
//  PageZoomViewportPolicy.swift
//  GeckoView
//
//  Created by Minh Ton on 17/7/26.
//

import Foundation

public enum PageZoomViewportPolicy {
    public static let defaultLevel = 100
    public static let supportedLevels = [50, 75, 90, 100, 110, 125, 150, 175, 200, 250, 300]

    public static func maximumLevel(
        viewportWidth: Double?,
        minimumLayoutWidth: Double? = nil
    ) -> Int {
        return effectiveLevel(
            requestedLevel: supportedLevels.last!,
            viewportWidth: viewportWidth,
            minimumLayoutWidth: minimumLayoutWidth
        )
    }

    public static func effectiveLevel(
        requestedLevel: Int,
        viewportWidth: Double?,
        minimumLayoutWidth: Double? = nil
    ) -> Int {
        guard supportedLevels.contains(requestedLevel) else {
            return defaultLevel
        }
        guard let minimumLayoutWidth else {
            return requestedLevel
        }
        guard let viewportWidth,
              viewportWidth.isFinite,
              viewportWidth > 0,
              minimumLayoutWidth.isFinite,
              minimumLayoutWidth > 0 else {
            return defaultLevel
        }

        return supportedLevels.last {
            $0 <= requestedLevel &&
                viewportWidth / (Double($0) / 100) >= minimumLayoutWidth
        } ?? supportedLevels.first!
    }
}
