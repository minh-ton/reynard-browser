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

final class WebsiteModePolicy {
    // MARK: - State

    private var desktopOverridesByTab: [UUID: [String: Bool]] = [:]

    // MARK: - Mode Resolution

    func prefersDesktopMode(for url: String, tabID: UUID?) -> Bool {
        guard let tabID else {
            return Prefs.BrowsingSettings.requestDesktopWebsite
        }
        return isDesktopMode(for: url, tabID: tabID) ?? Prefs.BrowsingSettings.requestDesktopWebsite
    }

    func isDesktopMode(for url: String, tabID: UUID) -> Bool? {
        guard let host = DomainMatcher.host(from: url),
              !url.starts(with: "moz-extension://"),
              host != "addons.mozilla.org" else {
            return nil
        }

        let overrides = desktopOverridesByTab[tabID]
        return overrides?[host] ?? overrides?.first(where: {
            DomainMatcher.matches(host: host, domain: $0.key) || DomainMatcher.matches(host: $0.key, domain: host)
        })?.value ?? Prefs.BrowsingSettings.requestDesktopWebsite
    }

    // MARK: - Overrides

    func toggle(for url: String, tabID: UUID) -> WebsiteModeAction? {
        guard let host = DomainMatcher.host(from: url),
              let isDesktop = isDesktopMode(for: url, tabID: tabID) else {
            return nil
        }

        let enablesDesktopMode = !isDesktop
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

        if enablesDesktopMode == Prefs.BrowsingSettings.requestDesktopWebsite {
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

    func clearOverrides(for tabID: UUID) {
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
            DomainMatcher.matches(host: existingHost, domain: $0) || DomainMatcher.matches(host: $0, domain: existingHost)
        }) {
            relatedHosts.insert(existingHost)
        }
        return relatedHosts
    }
}
