//
//  AddonRuntimeActionEvents.swift
//  Reynard
//

import Foundation

extension AddonRuntime {
    @MainActor
    func handleOpenOptionsPage(message: [String: Any?]?) async throws {
        guard let extensionID = message?["extensionId"] as? String,
              let addon = try await addon(byID: extensionID) else {
            throw GeckoHandlerError("runtime.openOptionsPage is not supported")
        }
        delegate?.addonController(self, didRequestOpenOptionsPageFor: addon)
    }

    @MainActor
    func handleNewTab(message: [String: Any?]?) async throws -> Bool {
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

    @MainActor
    func handleActionUpdate(
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

    @MainActor
    func handleOpenPopup(
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

    private func action(kind: AddonActionKind, from message: [String: Any?]?) -> AddonAction? {
        guard let dictionary = message?["action"] as? [String: Any?] else {
            return nil
        }
        return AddonAction(kind: kind, dictionary: dictionary)
    }
}
