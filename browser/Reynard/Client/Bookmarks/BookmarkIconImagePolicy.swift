//
//  BookmarkIconImagePolicy.swift
//  Reynard
//

import Foundation

struct BookmarkIconNormalizedCrop: Equatable {
    let x: Double
    let y: Double
    let side: Double
}

enum BookmarkIconImagePolicy {
    nonisolated static let maximumInputBytes = 16 * 1024 * 1024
    nonisolated static let maximumPixelCount = 40 * 1024 * 1024
    nonisolated static let maximumDimension = 32_760
    nonisolated static let outputPixelSize = 256

    nonisolated static func acceptsInputByteCount(_ byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= maximumInputBytes
    }

    nonisolated static func acceptsPixelDimensions(width: Int, height: Int) -> Bool {
        guard width > 0,
              height > 0,
              width <= maximumDimension,
              height <= maximumDimension else {
            return false
        }

        return Double(width) * Double(height) <= Double(maximumPixelCount)
    }

    nonisolated static func clampedSquareCrop(
        x: Double,
        y: Double,
        side: Double
    ) -> BookmarkIconNormalizedCrop? {
        guard x.isFinite, y.isFinite, side.isFinite, side > 0 else {
            return nil
        }

        let boundedSide = min(side, 1)
        let maximumOrigin = 1 - boundedSide
        return BookmarkIconNormalizedCrop(
            x: min(max(x, 0), maximumOrigin),
            y: min(max(y, 0), maximumOrigin),
            side: boundedSide
        )
    }
}
