//
//  DownloadImageDecodePolicy.swift
//  Reynard
//

import Foundation

enum DownloadImageDecodePolicy {
    nonisolated static let maximumPixelCount = 24 * 1024 * 1024
    nonisolated static let maximumDimension = 32_760
    nonisolated static let maximumFileBytes: Int64 = 256 * 1024 * 1024

    nonisolated static func acceptsFileByteCount(_ byteCount: Int64) -> Bool {
        byteCount > 0 && byteCount <= maximumFileBytes
    }

    nonisolated static func boundedDimensions(width: Int, height: Int) -> (width: Int, height: Int)? {
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

    nonisolated static func allowsPanning(contentLength: CGFloat, viewportLength: CGFloat) -> Bool {
        contentLength > viewportLength + 0.5
    }
}
