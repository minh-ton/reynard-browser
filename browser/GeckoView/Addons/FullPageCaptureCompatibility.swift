//
//  FullPageCaptureCompatibility.swift
//  Reynard
//

import Foundation

enum FullPageCaptureCompatibility {
    static let extensionID = "fullpage-capture@mosfor"
    static let supportedVersion = "0.5.0"

    enum Capability {
        case localizedStrings
        case clipboardImage
        case regionSelection

        var requiredPermission: String? {
            switch self {
            case .localizedStrings:
                return nil
            case .clipboardImage, .regionSelection:
                return "downloads"
            }
        }
    }
}

extension AddonRuntime {
    func requireFullPageCaptureAddon(
        from message: [String: Any?]?,
        capability: FullPageCaptureCompatibility.Capability
    ) async throws -> Addon {
        guard let extensionID = message?["extensionId"] as? String,
              extensionID == FullPageCaptureCompatibility.extensionID,
              let addon = try await addon(byID: extensionID),
              addon.metaData.version == FullPageCaptureCompatibility.supportedVersion,
              addon.metaData.enabled else {
            throw GeckoHandlerError("FullPage Capture compatibility is unavailable")
        }

        if let permission = capability.requiredPermission,
           !addon.metaData.requiredPermissions.contains(permission) {
            throw GeckoHandlerError("FullPage Capture lacks the required permission")
        }
        return addon
    }
}
