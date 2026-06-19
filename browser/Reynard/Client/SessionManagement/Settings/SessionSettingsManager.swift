//
//  SessionSettingsManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView

final class SessionSettingsManager {
    private enum BrowsingMode {
        static let mobile = 0
        static let desktop = 1
    }
    
    private let websiteMode: WebsiteModePolicy
    private let userAgentPolicy: UserAgentPolicy
    
    init(
        websiteMode: WebsiteModePolicy = WebsiteModePolicy(),
        userAgentPolicy: UserAgentPolicy = UserAgentPolicy()
    ) {
        self.websiteMode = websiteMode
        self.userAgentPolicy = userAgentPolicy
    }
    
    func settings(for url: String, tabID: UUID?) -> GeckoSessionSettings {
        let prefersDesktopMode = websiteMode.prefersDesktopMode(for: url, tabID: tabID)
        let userAgent = userAgentPolicy.configuration(
            for: url,
            prefersDesktopMode: prefersDesktopMode
        )
        let usesDesktopMode = prefersDesktopMode && !userAgent.forcesMobileMode
        let mode = usesDesktopMode ? BrowsingMode.desktop : BrowsingMode.mobile
        return GeckoSessionSettings(
            userAgentOverride: userAgent.override,
            userAgentMode: mode,
            viewportMode: mode
        )
    }
    
    func update(_ session: GeckoSession, for url: String, tabID: UUID?) {
        session.updateSettings(settings(for: url, tabID: tabID))
    }
    
    func isDesktopMode(for url: String, tabID: UUID) -> Bool? {
        return websiteMode.isDesktopMode(for: url, tabID: tabID)
    }
    
    func toggleWebsiteMode(for url: String, tabID: UUID) -> WebsiteModeAction? {
        return websiteMode.toggle(for: url, tabID: tabID)
    }
    
    func clearWebsiteOverrides(for tabID: UUID) {
        websiteMode.clearOverrides(for: tabID)
    }
    
    func needsUpdate(
        to session: GeckoSession,
        currentURL: String?,
        requestedURL: String,
        tabID: UUID
    ) -> Bool {
        guard let currentURL,
              let currentHost = DomainMatcher.host(from: currentURL),
              let requestedHost = DomainMatcher.host(from: requestedURL),
              currentHost != requestedHost else {
            return false
        }
        return session.settings != settings(for: requestedURL, tabID: tabID)
    }
}
