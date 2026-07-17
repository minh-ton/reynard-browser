//
//  AddonStagedFile.swift
//  Reynard
//

import Foundation
import ImageIO

enum AddonStagedFile {
    nonisolated static let prefix = "reynard-webextension"
    nonisolated static let clipboardFileName = "reynard-native-clipboard.png"
    nonisolated static let clipboardMimeType = "image/png"
    nonisolated static let clipboardPasteboardType = "public.png"
    nonisolated static let maximumClipboardImageSize = 64 * 1024 * 1024
    nonisolated static let maximumImagePixels = 32 * 1024 * 1024
    nonisolated static let maximumImageDimension = 32_760

    nonisolated static func validatedURL(path: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let fileURL = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let temporaryPrefix = temporaryDirectory.path.hasSuffix("/")
            ? temporaryDirectory.path
            : temporaryDirectory.path + "/"
        guard fileURL.path.hasPrefix(temporaryPrefix),
              fileURL.lastPathComponent.hasPrefix(prefix),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GeckoHandlerError("The staged add-on file path is invalid")
        }
        return fileURL
    }

    nonisolated static func loadValidatedPNG(at fileURL: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            } catch {
                throw GeckoHandlerError("Could not read the staged clipboard image")
            }
            guard data.count <= maximumClipboardImageSize else {
                throw GeckoHandlerError("The staged clipboard image is too large")
            }
            try validatePNG(data)
            return data
        }.value
    }

    nonisolated static func validatePNG(_ data: Data) throws {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == clipboardPasteboardType,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= maximumImageDimension,
              height <= maximumImageDimension,
              width <= maximumImagePixels / height else {
            throw GeckoHandlerError("The staged clipboard image exceeds the safe image limits")
        }
    }
}
