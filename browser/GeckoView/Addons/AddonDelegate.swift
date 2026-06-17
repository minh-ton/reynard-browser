//
//  AddonDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

public struct AddonInstallFailure: Error {
    public let code: String?
    public let extensionID: String?
    public let extensionName: String?
    public let extensionVersion: String?
}

public protocol AddonEmbedderDelegate: AnyObject {
    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon)
    func addonController(_ controller: AddonRuntime, didFailInstall failure: AddonInstallFailure)
    @MainActor
    func addonController(_ controller: AddonRuntime, promptFor prompt: AddonPermissionPrompt) async -> AddonPermissionPromptResponse
    func addonController(_ controller: AddonRuntime, didUpdate action: AddonAction, for addon: Addon, session: GeckoSession?)
    func addonController(_ controller: AddonRuntime, didRequestOpenPopup popupURL: String, for addon: Addon, action: AddonAction, session: GeckoSession?)
    func addonController(_ controller: AddonRuntime, didRequestOpenOptionsPageFor addon: Addon)
    func addonController(_ controller: AddonRuntime, createNewTabFor addon: Addon, details: AddonCreateTabDetails, newSessionID: String) -> Bool
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny
}

public extension AddonEmbedderDelegate {
    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon) {}
    func addonController(_ controller: AddonRuntime, didFailInstall failure: AddonInstallFailure) {}
    @MainActor
    func addonController(_ controller: AddonRuntime, promptFor prompt: AddonPermissionPrompt) async -> AddonPermissionPromptResponse { .deny }
    func addonController(_ controller: AddonRuntime, didUpdate action: AddonAction, for addon: Addon, session: GeckoSession?) {}
    func addonController(_ controller: AddonRuntime, didRequestOpenPopup popupURL: String, for addon: Addon, action: AddonAction, session: GeckoSession?) {}
    func addonController(_ controller: AddonRuntime, didRequestOpenOptionsPageFor addon: Addon) {}
    func addonController(_ controller: AddonRuntime, createNewTabFor addon: Addon, details: AddonCreateTabDetails, newSessionID: String) -> Bool { false }
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny { .deny }
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny { .deny }
}
