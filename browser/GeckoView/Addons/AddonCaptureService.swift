//
//  AddonCaptureService.swift
//  Reynard
//

import Foundation
import ImageIO
import UIKit

private struct SendableCGImage: @unchecked Sendable {
    let value: CGImage
}

@MainActor
enum AddonCaptureService {
    private static let compositorDelayNanoseconds: UInt64 = 100_000_000
    private static let encodingTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static var isCaptureInProgress = false

    static func captureVisibleContent(
        view: UIView,
        requestedWidth: CGFloat,
        requestedHeight: CGFloat,
        requestedPixelScale: CGFloat
    ) async throws -> String {
        guard !isCaptureInProgress else {
            throw GeckoHandlerError("Another web content capture is already running")
        }
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: compositorDelayNanoseconds)

        let widthScale = requestedWidth > 0 ? requestedWidth / view.bounds.width : 1
        let heightScale = requestedHeight > 0 ? requestedHeight / view.bounds.height : widthScale
        let outputScale = max(
            0.1,
            min(widthScale, heightScale) * max(1, requestedPixelScale)
        )
        let outputWidth = view.bounds.width * outputScale
        let outputHeight = view.bounds.height * outputScale
        guard outputScale.isFinite,
              outputWidth.isFinite,
              outputHeight.isFinite,
              outputWidth > 0,
              outputHeight > 0,
              outputWidth <= CGFloat(AddonStagedFile.maximumImageDimension),
              outputHeight <= CGFloat(AddonStagedFile.maximumImageDimension),
              outputWidth * outputHeight <= CGFloat(AddonStagedFile.maximumImagePixels) else {
            throw GeckoHandlerError("The requested web content capture is too large")
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = outputScale
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else {
            throw GeckoHandlerError("Could not render the web content image")
        }

        return try await encodePNGDataURL(SendableCGImage(value: cgImage))
    }

    private static func encodePNGDataURL(_ image: SendableCGImage) async throws -> String {
        let timeoutNanoseconds = encodingTimeoutNanoseconds
        let maximumEncodedSize = AddonStagedFile.maximumClipboardImageSize
        let pngType = AddonStagedFile.clipboardPasteboardType as CFString
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask(priority: .userInitiated) {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    data,
                    pngType,
                    1,
                    nil
                ) else {
                    throw GeckoHandlerError("Could not create the PNG encoder")
                }
                CGImageDestinationAddImage(destination, image.value, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw GeckoHandlerError("Could not encode the web content image")
                }
                guard data.length <= maximumEncodedSize else {
                    throw GeckoHandlerError("The encoded web content image is too large")
                }
                try Task.checkCancellation()
                return "data:image/png;base64,\((data as Data).base64EncodedString())"
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw GeckoHandlerError("Web content image encoding timed out")
            }

            guard let result = try await group.next() else {
                throw GeckoHandlerError("Web content image encoding failed")
            }
            group.cancelAll()
            return result
        }
    }
}
