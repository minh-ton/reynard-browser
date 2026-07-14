//
//  AddonRuntimePermissionEvents.swift
//  Reynard
//

import Foundation

extension AddonRuntime {
    @MainActor
    func installPromptResponse(message: [String: Any?]?) async throws -> [String: Any] {
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

    @MainActor
    func permissionPromptResponse(
        for event: AddonRuntimeEvent,
        message: [String: Any?]?
    ) async throws -> [String: Bool] {
        guard let prompt = try await permissionPrompt(for: event, message: message) else {
            return ["allow": false]
        }
        let response = await delegate?.addonController(self, promptFor: prompt) ?? .deny
        return ["allow": response.allow]
    }

    @MainActor
    func handleInstallationFailed(message: [String: Any?]?) {
        let failure = AddonInstallFailure(
            code: PayloadValue.string(message?["error"] ?? nil),
            extensionID: PayloadValue.string(message?["addonId"] ?? nil),
            extensionName: PayloadValue.string(message?["addonName"] ?? nil),
            extensionVersion: PayloadValue.string(message?["addonVersion"] ?? nil)
        )
        delegate?.addonController(self, didFailInstall: failure)
    }

    @MainActor
    func handleUninstalled(message: [String: Any?]?) {
        if let removedAddon = removeAddon(from: message) {
            delegate?.addonController(self, didUpdate: removedAddon)
        }
    }

    @MainActor
    func handleLifecycleUpdate(message: [String: Any?]?) {
        guard let extensionDictionary = message?["extension"] as? [String: Any?] else {
            return
        }
        let addon = upsertAddon(from: extensionDictionary)
        delegate?.addonController(self, didUpdate: addon)
    }

    @MainActor
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

    @MainActor
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
                permissions: PayloadValue.strings(message?["permissions"] ?? nil),
                origins: PayloadValue.strings(message?["origins"] ?? nil),
                dataCollectionPermissions: PayloadValue.strings(message?["dataCollectionPermissions"] ?? nil)
            )
        case .optionalPrompt:
            let permissions = message?["permissions"] as? [String: Any?]
            return AddonPermissionPrompt(
                kind: .optional,
                addon: addon,
                permissions: PayloadValue.strings(permissions?["permissions"] ?? nil),
                origins: PayloadValue.strings(permissions?["origins"] ?? nil),
                dataCollectionPermissions: PayloadValue.strings(permissions?["data_collection"] ?? nil)
            )
        case .updatePrompt:
            return AddonPermissionPrompt(
                kind: .update,
                addon: addon,
                permissions: PayloadValue.strings(message?["newPermissions"] ?? nil),
                origins: PayloadValue.strings(message?["newOrigins"] ?? nil),
                dataCollectionPermissions: PayloadValue.strings(message?["newDataCollectionPermissions"] ?? nil)
            )
        default:
            return nil
        }
    }
}
