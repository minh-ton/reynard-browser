//
//  DownloadImageDecodePolicy.swift
//  Reynard
//

import Foundation

enum DownloadImageDecodePolicy {
    static let maximumPixelCount = 24 * 1024 * 1024
    static let maximumDimension = 32_760

    static func boundedDimensions(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else {
            return nil
        }
        let scale = min(
            1,
            sqrt(Double(maximumPixelCount) / (Double(width) * Double(height))),
            Double(maximumDimension) / Double(width),
            Double(maximumDimension) / Double(height)
        )
        guard scale.isFinite, scale > 0 else {
            return nil
        }
        let boundedWidth = max(1, Int(floor(Double(width) * scale)))
        let boundedHeight = max(1, Int(floor(Double(height) * scale)))
        guard boundedWidth <= maximumDimension,
              boundedHeight <= maximumDimension,
              boundedWidth * boundedHeight <= maximumPixelCount else {
            return nil
        }
        return (boundedWidth, boundedHeight)
    }
}
