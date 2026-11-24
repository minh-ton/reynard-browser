//
//  WebsiteModeSettingManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView

final class WebsiteModeSettingManager {
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
    
    func setting(for url: String, tabID: UUID?) -> WebsiteModeSetting {
        let prefersDesktopMode = websiteMode.prefersDesktopMode(for: url, tabID: tabID)
        let userAgent = userAgentPolicy.configuration(
            for: url,
            prefersDesktopMode: prefersDesktopMode
        )
        let usesDesktopMode = prefersDesktopMode && !userAgent.forcesMobileMode
        let mode = usesDesktopMode ? BrowsingMode.desktop : BrowsingMode.mobile
        return WebsiteModeSetting(
            userAgentOverride: userAgent.override,
            platformOverride: userAgent.platformOverride,
            appVersionOverride: userAgent.appVersionOverride,
            oscpuOverride: userAgent.oscpuOverride,
            buildIDOverride: userAgent.buildIDOverride,
            userAgentMode: mode,
            viewportMode: mode
        )
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
    
    func takeWebsiteOverrides(for tabID: UUID) -> [String: Bool]? {
        return websiteMode.takeOverrides(for: tabID)
    }
    
    func restoreWebsiteOverrides(_ overrides: [String: Bool]?, for tabID: UUID) {
        websiteMode.restoreOverrides(overrides, for: tabID)
    }
}
