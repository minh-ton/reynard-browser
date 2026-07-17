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

public struct AddonDownloadRequest {
    public let sourceURL: URL
    public let suggestedFileName: String?
    public let mimeType: String?

    public init(sourceURL: URL, suggestedFileName: String?, mimeType: String?) {
        self.sourceURL = sourceURL
        self.suggestedFileName = suggestedFileName
        self.mimeType = mimeType
    }
}

public struct AddonDownloadResult {
    public let id: Int
    public let fileName: String
    public let mimeType: String?
    public let fileSize: Int64

    public init(id: Int, fileName: String, mimeType: String?, fileSize: Int64) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
    }
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
    func addonController(_ controller: AddonRuntime, download request: AddonDownloadRequest) -> AddonDownloadResult?
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
    func addonController(_ controller: AddonRuntime, download request: AddonDownloadRequest) -> AddonDownloadResult? { nil }
}
