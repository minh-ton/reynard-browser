//
//  AddonRuntimeEventRouter.swift
//  Reynard
//

import Foundation

@MainActor
struct AddonRuntimeEventRouter {
    let runtime: AddonRuntime

    func route(type: String, message: [String: Any?]?) async throws -> Any? {
        guard let event = AddonRuntimeEvent(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }

        switch event {
        case .browserActionUpdate:
            try await runtime.handleActionUpdate(kind: .browser, message: message, session: nil)
            return nil
        case .pageActionUpdate:
            try await runtime.handleActionUpdate(kind: .page, message: message, session: nil)
            return nil
        case .browserActionOpenPopup:
            try await runtime.handleOpenPopup(kind: .browser, message: message, session: nil)
            return nil
        case .pageActionOpenPopup:
            try await runtime.handleOpenPopup(kind: .page, message: message, session: nil)
            return nil
        case .openOptionsPage:
            try await runtime.handleOpenOptionsPage(message: message)
            return nil
        case .newTab:
            return try await runtime.handleNewTab(message: message)
        case .download:
            return try runtime.handleDownload(message: message)
        case .clipboardImage:
            return try await runtime.handleClipboardImage(message: message)
        case .beginRegionSelection:
            return try await runtime.handleBeginRegionSelection(message: message)
        case .fullPageCaptureStrings:
            return try await runtime.fullPageCaptureStrings(message: message)
        case .installPrompt:
            return try await runtime.installPromptResponse(message: message)
        case .optionalPrompt:
            return try await runtime.permissionPromptResponse(for: .optionalPrompt, message: message)
        case .updatePrompt:
            return try await runtime.permissionPromptResponse(for: .updatePrompt, message: message)
        case .installationFailed:
            runtime.handleInstallationFailed(message: message)
            return nil
        case .uninstalled:
            runtime.handleUninstalled(message: message)
            return nil
        case .optionalPermissionsChanged, .ready, .disabling, .disabled,
             .enabling, .enabled, .uninstalling, .installing, .installed:
            runtime.handleLifecycleUpdate(message: message)
            return nil
        }
    }
}

extension AddonRuntime {
    @MainActor
    public func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        try await AddonRuntimeEventRouter(runtime: self).route(type: type, message: message)
    }
}
