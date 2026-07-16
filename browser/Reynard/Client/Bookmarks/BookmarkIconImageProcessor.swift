//
//  BookmarkIconImageProcessor.swift
//  Reynard
//

import ImageIO
import UIKit

enum BookmarkIconImageProcessingError: Error {
    case invalidImage
    case inputTooLarge
}

enum BookmarkIconImageProcessor {
    static func validatedImage(from data: Data) throws -> UIImage {
        guard BookmarkIconImagePolicy.acceptsInputByteCount(data.count),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw BookmarkIconImageProcessingError.invalidImage
        }

        guard BookmarkIconImagePolicy.acceptsPixelDimensions(width: width, height: height) else {
            throw BookmarkIconImageProcessingError.inputTooLarge
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw BookmarkIconImageProcessingError.invalidImage
        }
        return UIImage(cgImage: image)
    }

    static func normalizedPNG(
        from image: UIImage,
        crop normalizedCrop: BookmarkIconNormalizedCrop
    ) throws -> Data {
        guard let crop = BookmarkIconImagePolicy.clampedSquareCrop(
            x: normalizedCrop.x,
            y: normalizedCrop.y,
            side: normalizedCrop.side
        ), let cgImage = image.cgImage else {
            throw BookmarkIconImageProcessingError.invalidImage
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let cropSide = CGFloat(crop.side) * min(sourceWidth, sourceHeight)
        let availableX = sourceWidth - cropSide
        let availableY = sourceHeight - cropSide
        let cropRect = CGRect(
            x: CGFloat(crop.x) * availableX,
            y: CGFloat(crop.y) * availableY,
            width: cropSide,
            height: cropSide
        ).integral

        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            throw BookmarkIconImageProcessingError.invalidImage
        }

        let size = CGSize(
            width: BookmarkIconImagePolicy.outputPixelSize,
            height: BookmarkIconImagePolicy.outputPixelSize
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: croppedImage).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.pngData(), !data.isEmpty else {
            throw BookmarkIconImageProcessingError.invalidImage
        }
        return data
    }
}
