//
//  AddonRuntimeEvents.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation
import UIKit

private enum AddonFileDiagnostics {
    private static let maximumSize = 1024 * 1024
    private static let queue = DispatchQueue(
        label: "com.minh-ton.Reynard.AddonFileDiagnostics",
        qos: .utility
    )

    static func record(fileName: String, event: String, details: String) {
        guard let line = "\(Date().timeIntervalSince1970) | \(event) | \(details)\n".data(using: .utf8) else {
            return
        }
        queue.async {
            guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return
            }
            let fileURL = cachesURL.appendingPathComponent(fileName)
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
               size.intValue >= maximumSize {
                try? Data().write(to: fileURL, options: .atomic)
            }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(line)
            handle.closeFile()
        }
    }
}

private enum AddonStagedFile {
    static let prefix = "reynard-webextension"
    static let clipboardFileName = "reynard-native-clipboard.png"
    static let clipboardMimeType = "image/png"
    static let maximumClipboardImageSize = 128 * 1024 * 1024

    static func validatedURL(path: String) throws -> URL {
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
}

private enum AddonClipboardDiagnostics {
    static func record(_ event: String, _ details: String = "") {
        AddonFileDiagnostics.record(
            fileName: "Reynard-ClipboardDebug.log",
            event: event,
            details: details
        )
    }
}

private enum AddonSelectionDiagnostics {
    static func record(_ event: String, _ details: String = "") {
        AddonFileDiagnostics.record(
            fileName: "Reynard-AddonSelectionDebug.log",
            event: event,
            details: details
        )
    }
}

extension AddonRuntime {
    @MainActor
    func handleSessionEvent(type: String, message: [String: Any?]?, session: GeckoSession) async throws -> Any? {
        switch type {
        case "GeckoView:BrowserAction:Update":
            try await handleActionUpdate(kind: .browser, message: message, session: session)
            return nil
        case "GeckoView:PageAction:Update":
            try await handleActionUpdate(kind: .page, message: message, session: session)
            return nil
        case "GeckoView:BrowserAction:OpenPopup":
            try await handleOpenPopup(kind: .browser, message: message, session: session)
            return nil
        case "GeckoView:PageAction:OpenPopup":
            try await handleOpenPopup(kind: .page, message: message, session: session)
            return nil
        case "GeckoView:WebExtension:OpenOptionsPage":
            try await handleOpenOptionsPage(message: message)
            return nil
        case "GeckoView:WebExtension:NewTab":
            return try await handleNewTab(message: message)
        case "GeckoView:WebExtension:UpdateTab":
            guard let extensionID = message?["extensionId"] as? String,
                  let addon = try await addon(byID: extensionID) else {
                throw GeckoHandlerError("tabs.update is not supported")
            }
            let details = AddonUpdateTabDetails(
                dictionary: message?["updateProperties"] as? [String: Any?] ?? [:]
            )
            if delegate?.addonController(self, updateTab: session, for: addon, details: details) == .allow {
                return nil
            }
            throw GeckoHandlerError("tabs.update is not supported")
        case "GeckoView:WebExtension:CloseTab":
            guard let extensionID = message?["extensionId"] as? String,
                  let addon = try await addon(byID: extensionID) else {
                throw GeckoHandlerError("tabs.remove is not supported")
            }
            if delegate?.addonController(self, closeTab: session, for: addon) == .allow {
                return nil
            }
            throw GeckoHandlerError("tabs.remove is not supported")
        case "GeckoView:WebExtension:CaptureVisibleTab":
            guard let view = session.window?.view(), !view.bounds.isEmpty else {
                throw GeckoHandlerError("The web content view is unavailable")
            }
            // Content scripts scroll immediately before capture. Give the Gecko
            // compositor one frame to present the new position.
            try await Task.sleep(nanoseconds: 100_000_000)
            let requestedWidth = CGFloat(PayloadValue.double(message?["width"] ?? nil) ?? 0)
            let requestedHeight = CGFloat(PayloadValue.double(message?["height"] ?? nil) ?? 0)
            let requestedPixelScale = CGFloat(
                PayloadValue.double(message?["pixelScale"] ?? nil) ?? 1
            )
            let captureBounds = view.bounds
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            // WebExtension captureVisibleTab consumers stitch in CSS pixels.
            // Returning Retina pixels makes source coordinates select only the
            // top-left portion of each frame on high-density iOS displays.
            let widthScale = requestedWidth > 0 ? requestedWidth / view.bounds.width : 1
            let heightScale = requestedHeight > 0 ? requestedHeight / view.bounds.height : widthScale
            format.scale = max(
                0.1,
                min(widthScale, heightScale) * max(1, requestedPixelScale)
            )
            let image = UIGraphicsImageRenderer(bounds: captureBounds, format: format).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            guard let data = image.pngData() else {
                throw GeckoHandlerError("Could not encode the web content image")
            }
            return "data:image/png;base64,\(data.base64EncodedString())"
        default:
            throw GeckoHandlerError("Unhandled WebExtension session event \(type)")
        }
    }
    
    @MainActor
    public func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        guard let event = AddonRuntimeEvent(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        switch event {
        case .browserActionUpdate:
            try await handleActionUpdate(kind: .browser, message: message, session: nil)
            return nil
        case .pageActionUpdate:
            try await handleActionUpdate(kind: .page, message: message, session: nil)
            return nil
        case .browserActionOpenPopup:
            try await handleOpenPopup(kind: .browser, message: message, session: nil)
            return nil
        case .pageActionOpenPopup:
            try await handleOpenPopup(kind: .page, message: message, session: nil)
            return nil
        case .openOptionsPage:
            try await handleOpenOptionsPage(message: message)
            return nil
        case .newTab:
            return try await handleNewTab(message: message)
        case .download:
            return try handleDownload(message: message)
        case .clipboardImage:
            return try handleClipboardImage(message: message)
        case .beginRegionSelection:
            return try handleBeginRegionSelection(message: message)
        case .installPrompt:
            return try await installPromptResponse(message: message)
        case .optionalPrompt:
            return try await permissionPromptResponse(for: .optionalPrompt, message: message)
        case .updatePrompt:
            return try await permissionPromptResponse(for: .updatePrompt, message: message)
        case .installationFailed:
            let failure = AddonInstallFailure(
                code: PayloadValue.string(message?["error"]),
                extensionID: PayloadValue.string(message?["addonId"]),
                extensionName: PayloadValue.string(message?["addonName"]),
                extensionVersion: PayloadValue.string(message?["addonVersion"])
            )
            delegate?.addonController(self, didFailInstall: failure)
            return nil
        case .uninstalled:
            if let removedAddon = removeAddon(from: message) {
                delegate?.addonController(self, didUpdate: removedAddon)
            }
            return nil
        case .optionalPermissionsChanged, .ready, .disabling, .disabled, .enabling, .enabled, .uninstalling, .installing, .installed:
            if let extensionDictionary = message?["extension"] as? [String: Any?] {
                let addon = upsertAddon(from: extensionDictionary)
                delegate?.addonController(self, didUpdate: addon)
            }
            return nil
        }
    }

    private func handleDownload(message: [String: Any?]?) throws -> [String: Any] {
        guard let options = message?["options"] as? [String: Any?],
              let localFilePath = options["localFilePath"] as? String,
              !localFilePath.isEmpty else {
            throw GeckoHandlerError("downloads.download requires a staged file URL")
        }
        let fileURL = try AddonStagedFile.validatedURL(path: localFilePath)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let mimeType = (options["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let request = AddonDownloadRequest(
            sourceURL: fileURL,
            suggestedFileName: options["filename"] as? String,
            mimeType: mimeType
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

    private func handleClipboardImage(message: [String: Any?]?) throws -> [String: Any] {
        let extensionID = message?["extensionId"] as? String
        guard extensionID == "fullpage-capture@mosfor" else {
            AddonClipboardDiagnostics.record("reject", "extension=\(extensionID ?? "none")")
            throw GeckoHandlerError("Clipboard image writes are not supported for this extension")
        }
        guard let options = message?["options"] as? [String: Any?],
              let localFilePath = options["localFilePath"] as? String,
              !localFilePath.isEmpty,
              options["filename"] as? String == AddonStagedFile.clipboardFileName,
              options["mimeType"] as? String == AddonStagedFile.clipboardMimeType else {
            AddonClipboardDiagnostics.record("reject", "reason=missing-file")
            throw GeckoHandlerError("Clipboard image write requires the expected staged PNG file")
        }

        let fileURL = try AddonStagedFile.validatedURL(path: localFilePath)
        AddonClipboardDiagnostics.record("begin", "path=\(fileURL.lastPathComponent)")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            AddonClipboardDiagnostics.record("read.error", "\(error)")
            throw GeckoHandlerError("Could not read the staged clipboard image")
        }
        guard data.count <= AddonStagedFile.maximumClipboardImageSize else {
            AddonClipboardDiagnostics.record("reject", "reason=file-too-large bytes=\(data.count)")
            throw GeckoHandlerError("The staged clipboard image is too large")
        }
        guard !data.isEmpty, UIImage(data: data) != nil else {
            AddonClipboardDiagnostics.record("decode.error", "bytes=\(data.count)")
            throw GeckoHandlerError("The staged clipboard image is not a valid PNG")
        }

        let pasteboard = UIPasteboard.general
        let beforeChangeCount = pasteboard.changeCount
        pasteboard.setItems([["public.png": data]])
        let copiedData = pasteboard.data(forPasteboardType: "public.png")
        let verified = pasteboard.hasImages && copiedData?.count == data.count
        AddonClipboardDiagnostics.record(
            "verify",
            "bytes=\(data.count) copiedBytes=\(copiedData?.count ?? 0) hasImages=\(pasteboard.hasImages) before=\(beforeChangeCount) after=\(pasteboard.changeCount)"
        )
        guard verified else {
            throw GeckoHandlerError("iOS did not retain the PNG on the pasteboard")
        }

        AddonClipboardDiagnostics.record("success", "bytes=\(data.count)")
        return [
            "success": true,
            "bytes": data.count,
            "changeCount": pasteboard.changeCount,
        ]
    }

    private func handleBeginRegionSelection(message: [String: Any?]?) throws -> [String: Bool] {
        let extensionID = message?["extensionId"] as? String
        guard extensionID == "fullpage-capture@mosfor" else {
            throw GeckoHandlerError("Region selection is not supported for this extension")
        }
        AddonSelectionDiagnostics.record("dismiss.request", "extension=\(extensionID ?? "none")")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("GeckoView.WebExtension.BeginRegionSelection"),
                object: nil
            )
        }
        return ["success": true]
    }
    
    private func handleOpenOptionsPage(message: [String: Any?]?) async throws {
        guard let extensionID = message?["extensionId"] as? String,
              let addon = try await addon(byID: extensionID) else {
            throw GeckoHandlerError("runtime.openOptionsPage is not supported")
        }
        delegate?.addonController(self, didRequestOpenOptionsPageFor: addon)
    }
    
    private func handleNewTab(message: [String: Any?]?) async throws -> Bool {
        guard let extensionID = message?["extensionId"] as? String,
              let newSessionID = message?["newSessionId"] as? String,
              let addon = try await addon(byID: extensionID) else {
            return false
        }
        let details = AddonCreateTabDetails(
            dictionary: message?["createProperties"] as? [String: Any?] ?? [:]
        )
        return delegate?.addonController(
            self,
            createNewTabFor: addon,
            details: details,
            newSessionID: newSessionID
        ) ?? false
    }
    
    private func installPromptResponse(message: [String: Any?]?) async throws -> [String: Any] {
        guard let prompt = try await permissionPrompt(for: .installPrompt, message: message) else {
            return [
                "allow": false,
                "privateBrowsingAllowed": false,
                "isTechnicalAndInteractionDataGranted": false,
            ]
        }
        let response = await delegate?.addonController(self, promptFor: prompt) ?? .deny
        return [
            "allow": response.allow,
            "privateBrowsingAllowed": response.privateBrowsingAllowed,
            "isTechnicalAndInteractionDataGranted": response.technicalAndInteractionDataGranted,
        ]
    }
    
    private func permissionPromptResponse(
        for event: AddonRuntimeEvent,
        message: [String: Any?]?
    ) async throws -> [String: Bool] {
        guard let prompt = try await permissionPrompt(for: event, message: message) else {
            return ["allow": false]
        }
        let response = await delegate?.addonController(self, promptFor: prompt) ?? .deny
        return ["allow": response.allow]
    }
    
    private func addonForPrompt(from message: [String: Any?]?) async throws -> Addon? {
        if let extensionDictionary = message?["extension"] as? [String: Any?] {
            return Addon(dictionary: extensionDictionary)
        }
        
        guard let extensionID = addonID(from: message) else {
            return nil
        }
        
        if let cachedAddon = addonsByID[extensionID] {
            return cachedAddon
        }
        
        return try await addon(byID: extensionID)
    }
    
    private func permissionPrompt(
        for event: AddonRuntimeEvent,
        message: [String: Any?]?
    ) async throws -> AddonPermissionPrompt? {
        guard let addon = try await addonForPrompt(from: message) else {
            return nil
        }
        
        switch event {
        case .installPrompt:
            return AddonPermissionPrompt(
                kind: .install,
                addon: addon,
                permissions: PayloadValue.strings(message?["permissions"]),
                origins: PayloadValue.strings(message?["origins"]),
                dataCollectionPermissions: PayloadValue.strings(message?["dataCollectionPermissions"])
            )
        case .optionalPrompt:
            let permissionDictionary = message?["permissions"] as? [String: Any?]
            return AddonPermissionPrompt(
                kind: .optional,
                addon: addon,
                permissions: PayloadValue.strings(permissionDictionary?["permissions"]),
                origins: PayloadValue.strings(permissionDictionary?["origins"]),
                dataCollectionPermissions: PayloadValue.strings(permissionDictionary?["data_collection"])
            )
        case .updatePrompt:
            return AddonPermissionPrompt(
                kind: .update,
                addon: addon,
                permissions: PayloadValue.strings(message?["newPermissions"]),
                origins: PayloadValue.strings(message?["newOrigins"]),
                dataCollectionPermissions: PayloadValue.strings(message?["newDataCollectionPermissions"])
            )
        default:
            return nil
        }
    }
    
    private func action(kind: AddonActionKind, from message: [String: Any?]?) -> AddonAction? {
        guard let dictionary = message?["action"] as? [String: Any?] else {
            return nil
        }
        return AddonAction(kind: kind, dictionary: dictionary)
    }
    
    private func handleActionUpdate(
        kind: AddonActionKind,
        message: [String: Any?]?,
        session: GeckoSession?
    ) async throws {
        guard let extensionID = message?["extensionId"] as? String,
              let action = action(kind: kind, from: message),
              let addon = try await addon(byID: extensionID) else {
            return
        }
        
        if session == nil {
            if kind == .browser {
                addon.browserAction = action
            } else {
                addon.pageAction = action
            }
        }
        delegate?.addonController(self, didUpdate: action, for: addon, session: session)
    }
    
    private func handleOpenPopup(
        kind: AddonActionKind,
        message: [String: Any?]?,
        session: GeckoSession?
    ) async throws {
        guard let extensionID = message?["extensionId"] as? String,
              let addon = try await addon(byID: extensionID),
              let action = action(kind: kind, from: message),
              let popupURL = message?["popupUri"] as? String,
              !popupURL.isEmpty else {
            return
        }
        delegate?.addonController(
            self,
            didRequestOpenPopup: popupURL,
            for: addon,
            action: action,
            session: session
        )
    }
}
