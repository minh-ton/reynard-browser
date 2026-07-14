//
//  DownloadImageDecoder.swift
//  Reynard
//

import ImageIO
import UIKit

enum DownloadImageDecodingError: Error, Equatable {
    case missingFile
    case oversizedFile
    case unsupportedOrCorruptFile
}

struct DecodedDownloadImage: @unchecked Sendable {
    let image: UIImage

    nonisolated init(image: UIImage) {
        self.image = image
    }
}

final class DownloadImageDecoder: @unchecked Sendable {
    nonisolated init() {}

    nonisolated func decode(fileURL: URL) async throws -> DecodedDownloadImage {
        let decodeTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard fileURL.isFileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                throw DownloadImageDecodingError.missingFile
            }
            let resourceValues: URLResourceValues
            do {
                resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            } catch {
                throw DownloadImageDecodingError.missingFile
            }
            guard resourceValues.isRegularFile == true else {
                throw DownloadImageDecodingError.missingFile
            }
            guard let fileSize = resourceValues.fileSize,
                  DownloadImageDecodePolicy.acceptsFileByteCount(Int64(fileSize)) else {
                throw DownloadImageDecodingError.oversizedFile
            }

            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
                  let properties = CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    sourceOptions
                  ) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let bounded = DownloadImageDecodePolicy.boundedDimensions(
                    width: width,
                    height: height
                  ) else {
                throw DownloadImageDecodingError.unsupportedOrCorruptFile
            }
            try Task.checkCancellation()

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(bounded.width, bounded.height),
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                throw DownloadImageDecodingError.unsupportedOrCorruptFile
            }
            try Task.checkCancellation()
            return DecodedDownloadImage(
                image: UIImage(cgImage: image, scale: 1, orientation: .up)
            )
        }
        return try await withTaskCancellationHandler {
            try await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }
}
