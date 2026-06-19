//
//  AddonRuntimeEvents.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

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
