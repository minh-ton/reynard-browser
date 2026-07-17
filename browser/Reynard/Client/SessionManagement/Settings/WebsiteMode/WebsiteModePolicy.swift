//
//  WebsiteModePolicy.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation

// MARK: - Website Mode Action

enum WebsiteModeAction {
    case reload
    case load(String)
}

struct WebsiteModeReset {
    let navigationAction: WebsiteModeAction?
}

final class WebsiteModePolicy {
    // MARK: - State

    private var desktopOverridesByTab: [UUID: [String: Bool]] = [:]
    private let siteSettings: SiteSettingsStore
    private let stateLock = NSRecursiveLock()

    init(siteSettings: SiteSettingsStore = .shared) {
        self.siteSettings = siteSettings
    }

    // MARK: - Mode Resolution

    func prefersDesktopMode(for url: String, tabID: UUID?) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let tabID else {
            return Prefs.BrowsingSettings.requestDesktopWebsite
        }
        return isDesktopMode(for: url, tabID: tabID) ?? Prefs.BrowsingSettings.requestDesktopWebsite
    }

    func isDesktopMode(for url: String, tabID: UUID) -> Bool? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let host = DomainMatcher.host(from: url),
              !url.starts(with: "moz-extension://"),
              host != "addons.mozilla.org" else {
            return nil
        }

        let overrides = desktopOverridesByTab[tabID]
        if let override = overrides?[host] ?? overrides?.first(where: {
            WebsiteModeHost.areRelated($0.key, host)
        })?.value {
            return override
        }

        if let storedMode = storedWebsiteMode(for: host) {
            return storedMode == .desktop
        }

        return Prefs.BrowsingSettings.requestDesktopWebsite
    }

    // MARK: - Overrides

    func toggle(for url: String, tabID: UUID) -> WebsiteModeAction? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let host = DomainMatcher.host(from: url),
              let isDesktop = isDesktopMode(for: url, tabID: tabID) else {
            return nil
        }

        let enablesDesktopMode = !isDesktop
        let persistentDefault = storedWebsiteMode(for: host).map { $0 == .desktop }
            ?? Prefs.BrowsingSettings.requestDesktopWebsite
        let desktopURL = enablesDesktopMode ? desktopURL(from: url) : nil
        let desktopHost = desktopURL.flatMap(DomainMatcher.host)
        var tabOverrides = desktopOverridesByTab[tabID] ?? [:]

        for relatedHost in relatedOverrideHosts(
            for: host,
            desktopHost: desktopHost,
            existingOverrides: tabOverrides
        ) {
            tabOverrides.removeValue(forKey: relatedHost)
        }

        if enablesDesktopMode == persistentDefault {
            if tabOverrides.isEmpty {
                desktopOverridesByTab.removeValue(forKey: tabID)
            } else {
                desktopOverridesByTab[tabID] = tabOverrides
            }
        } else {
            tabOverrides[desktopHost ?? host] = enablesDesktopMode
            desktopOverridesByTab[tabID] = tabOverrides
        }

        return desktopURL.map(WebsiteModeAction.load) ?? .reload
    }

    func setPersistentMode(_ mode: SiteWebsiteMode, for url: String, tabID: UUID) -> WebsiteModeAction? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let host = DomainMatcher.host(from: url),
              !url.starts(with: "moz-extension://"),
              host != "addons.mozilla.org" else {
            return nil
        }

        let desktopURL = mode == .desktop ? desktopURL(from: url) : nil
        let desktopHost = desktopURL.flatMap(DomainMatcher.host)
        guard siteSettings.replaceWebsiteMode(
            mode,
            forHost: host,
            additionalHost: desktopHost
        ) else {
            return nil
        }

        var tabOverrides = desktopOverridesByTab[tabID] ?? [:]
        for relatedHost in relatedOverrideHosts(
            for: host,
            desktopHost: desktopHost,
            existingOverrides: tabOverrides
        ) {
            tabOverrides.removeValue(forKey: relatedHost)
        }
        if tabOverrides.isEmpty {
            desktopOverridesByTab.removeValue(forKey: tabID)
        } else {
            desktopOverridesByTab[tabID] = tabOverrides
        }

        return desktopURL.map(WebsiteModeAction.load) ?? .reload
    }

    func resetPersistentMode(for url: String, tabID: UUID) -> WebsiteModeReset? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let host = DomainMatcher.host(from: url),
              let previousMode = isDesktopMode(for: url, tabID: tabID),
              siteSettings.clearSettingsForRelatedHosts(of: host) else {
            return nil
        }

        var tabOverrides = desktopOverridesByTab[tabID] ?? [:]
        for relatedHost in Array(tabOverrides.keys) where WebsiteModeHost.areRelated(relatedHost, host) {
            tabOverrides.removeValue(forKey: relatedHost)
        }
        if tabOverrides.isEmpty {
            desktopOverridesByTab.removeValue(forKey: tabID)
        } else {
            desktopOverridesByTab[tabID] = tabOverrides
        }

        guard let currentMode = isDesktopMode(for: url, tabID: tabID),
              currentMode != previousMode else {
            return WebsiteModeReset(navigationAction: nil)
        }
        if currentMode, let desktopURL = desktopURL(from: url) {
            return WebsiteModeReset(navigationAction: .load(desktopURL))
        }
        return WebsiteModeReset(navigationAction: .reload)
    }

    func clearOverrides(for tabID: UUID) {
        stateLock.lock()
        defer { stateLock.unlock() }
        desktopOverridesByTab.removeValue(forKey: tabID)
    }

    // MARK: - URL Resolution

    private func desktopURL(from url: String) -> String? {
        guard var components = URLComponents(string: url),
              let host = components.host else {
            return nil
        }

        let normalizedHost = host.lowercased()
        let prefixes = ["m.", "mobile."]
        guard let prefix = prefixes.first(where: { normalizedHost.hasPrefix($0) }) else {
            return nil
        }

        components.host = String(normalizedHost.dropFirst(prefix.count))
        return components.url?.absoluteString
    }

    private func relatedOverrideHosts(
        for host: String,
        desktopHost: String?,
        existingOverrides: [String: Bool]
    ) -> Set<String> {
        var relatedHosts: Set<String> = [host]
        if let desktopHost {
            relatedHosts.insert(desktopHost)
        }

        for existingHost in existingOverrides.keys where relatedHosts.contains(where: {
            WebsiteModeHost.areRelated(existingHost, $0)
        }) {
            relatedHosts.insert(existingHost)
        }
        return relatedHosts
    }

    private func storedWebsiteMode(for host: String) -> SiteWebsiteMode? {
        if let exactMode = siteSettings.websiteMode(forHost: host) {
            return exactMode
        }
        for alias in WebsiteModeHost.orderedAliases(for: host) where alias != host {
            if let mode = siteSettings.websiteMode(forHost: alias) {
                return mode
            }
        }
        return nil
    }
}
