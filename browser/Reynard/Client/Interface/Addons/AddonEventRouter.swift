//
//  AddonEventRouter.swift
//  Reynard
//
//  Created by Minh Ton on 24/11/26.
//

import GeckoView

final class AddonEventRouter: AddonEmbedderDelegate {
    static let shared = AddonEventRouter()
    
    private var coordinators: [AddonCoordinator] {
        return BrowserWindowManager.shared.browsers.map(\.addonCoordinator)
    }
    
    private var activeCoordinator: AddonCoordinator? {
        return coordinators.first
    }
    
    private init() {}
    
    func start() {
        guard AddonRuntime.shared.delegate !== self else {
            return
        }
        AddonRuntime.shared.delegate = self
    }
    
    private func coordinator(owning session: GeckoSession?) -> AddonCoordinator? {
        guard let session,
              let browser = BrowserWindowManager.shared.browsers.first(where: { $0.tabManager.tab(for: session) != nil }) else {
            return activeCoordinator
        }
        return browser.addonCoordinator
    }
    
    // MARK: - AddonEmbedderDelegate
    
    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon) {
        coordinators.forEach { $0.addonController(controller, didUpdate: addon) }
    }
    
    func addonController(_ controller: AddonRuntime, didFailInstall failure: AddonInstallFailure) {
        activeCoordinator?.addonController(controller, didFailInstall: failure)
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, promptFor prompt: AddonPermissionPrompt) async -> AddonPermissionPromptResponse {
        guard let activeCoordinator else {
            return .deny
        }
        return await activeCoordinator.addonController(controller, promptFor: prompt)
    }
    
    func addonController(_ controller: AddonRuntime, didUpdate action: AddonAction, for addon: Addon, session: GeckoSession?) {
        coordinators.forEach { $0.addonController(controller, didUpdate: action, for: addon, session: session) }
    }
    
    func addonController(_ controller: AddonRuntime, didRequestOpenPopup popupURL: String, for addon: Addon, action: AddonAction, session: GeckoSession?) {
        coordinator(owning: session)?.addonController(controller, didRequestOpenPopup: popupURL, for: addon, action: action, session: session)
    }
    
    func addonController(_ controller: AddonRuntime, didRequestOpenOptionsPageFor addon: Addon) {
        activeCoordinator?.addonController(controller, didRequestOpenOptionsPageFor: addon)
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, didRequestDownload options: [String: Any?], for addon: Addon) async -> [String: Any]? {
        return await activeCoordinator?.addonController(controller, didRequestDownload: options, for: addon)
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, didCompleteDownloadAt localFilePath: String, succeeded: Bool) {
        coordinators.forEach { $0.addonController(controller, didCompleteDownloadAt: localFilePath, succeeded: succeeded) }
    }
    
    func addonController(_ controller: AddonRuntime, createNewTabFor addon: Addon, details: AddonCreateTabDetails, newSessionID: String) -> Bool {
        return activeCoordinator?.addonController(controller, createNewTabFor: addon, details: details, newSessionID: newSessionID) ?? false
    }
    
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny {
        return coordinator(owning: session)?.addonController(controller, updateTab: session, for: addon, details: details) ?? .deny
    }
    
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny {
        return coordinator(owning: session)?.addonController(controller, closeTab: session, for: addon) ?? .deny
    }
}
