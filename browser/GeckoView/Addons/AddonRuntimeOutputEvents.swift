//
//  AddonRuntimeOutputEvents.swift
//  Reynard
//

import Foundation

private struct AddonStagedOutputRequest {
    let fileURL: URL
    let fileName: String?
    let mimeType: String?

    init(message: [String: Any?]?) throws {
        guard let options = message?["options"] as? [String: Any?],
              let localFilePath = options["localFilePath"] as? String,
              !localFilePath.isEmpty else {
            throw GeckoHandlerError("A staged add-on file is required")
        }
        fileURL = try AddonStagedFile.validatedURL(path: localFilePath)
        fileName = options["filename"] as? String
        mimeType = (options["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

extension AddonRuntime {
    @MainActor
    func handleDownload(message: [String: Any?]?) throws -> [String: Any] {
        let output = try AddonStagedOutputRequest(message: message)
        defer { try? FileManager.default.removeItem(at: output.fileURL) }

        let request = AddonDownloadRequest(
            sourceURL: output.fileURL,
            suggestedFileName: output.fileName,
            mimeType: output.mimeType
        )
        guard let result = delegate?.addonController(self, download: request) else {
            throw GeckoHandlerError("downloads.download could not import the staged file")
        }
        return [
            "id": result.id,
            "filename": result.fileName,
            "referrer": "",
            "mime": result.mimeType ?? "application/octet-stream",
            "startTime": ISO8601DateFormatter().string(from: Date()),
            "state": 2,
            "paused": false,
            "canResume": false,
            "bytesReceived": result.fileSize,
            "totalBytes": result.fileSize,
            "fileSize": result.fileSize,
            "exists": true,
        ]
    }

    @MainActor
    func handleClipboardImage(message: [String: Any?]?) async throws -> [String: Any] {
        _ = try await requireFullPageCaptureAddon(from: message, capability: .clipboardImage)
        let output = try AddonStagedOutputRequest(message: message)
        guard output.fileName == AddonStagedFile.clipboardFileName,
              output.mimeType == AddonStagedFile.clipboardMimeType else {
            throw GeckoHandlerError("Clipboard image write requires the expected staged PNG file")
        }
        defer { try? FileManager.default.removeItem(at: output.fileURL) }

        let data = try await AddonStagedFile.loadValidatedPNG(at: output.fileURL)
        let changeCount = try AddonClipboardOutputService.shared.writePNG(data)
        return [
            "success": true,
            "bytes": data.count,
            "changeCount": changeCount,
        ]
    }

    @MainActor
    func handleBeginRegionSelection(message: [String: Any?]?) async throws -> [String: Bool] {
        _ = try await requireFullPageCaptureAddon(from: message, capability: .regionSelection)
        NotificationCenter.default.post(
            name: Notification.Name("GeckoView.WebExtension.BeginRegionSelection"),
            object: nil
        )
        return ["success": true]
    }

    @MainActor
    func fullPageCaptureStrings(message: [String: Any?]?) async throws -> [String: String] {
        _ = try await requireFullPageCaptureAddon(from: message, capability: .localizedStrings)
        return [
            "cancel": NSLocalizedString("Cancel", comment: ""),
            "capture": NSLocalizedString("Capture", comment: ""),
            "dragRegion": NSLocalizedString("Drag to select an area", comment: ""),
            "extendRegion": NSLocalizedString(
                "Drag a region, then extend with the blue handle",
                comment: ""
            ),
            "redraw": NSLocalizedString("Redraw", comment: ""),
        ]
    }
}
