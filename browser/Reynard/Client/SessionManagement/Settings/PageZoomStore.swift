//
//  PageZoomStore.swift
//  Reynard
//
//  Created by Reynard on 23/6/26.
//

import Foundation

final class PageZoomStore {
    static let shared = PageZoomStore()

    private init() {}

    var defaultPercent: Int {
        get {
            PageZoomLevel.normalizedPercent(Prefs.BrowsingSettings.defaultPageZoomPercent)
        }
        set {
            Prefs.BrowsingSettings.defaultPageZoomPercent = PageZoomLevel.normalizedPercent(newValue)
        }
    }

    func zoomPercent(for url: String?) -> Int {
        guard let url,
              let host = DomainMatcher.host(from: url),
              let override = overrideMatch(for: host)?.percent else {
            return defaultPercent
        }
        return override
    }

    func zoomScale(for url: String?) -> Double {
        PageZoomLevel.scale(for: zoomPercent(for: url))
    }

    func hasOverride(for url: String?) -> Bool {
        guard let url,
              let host = DomainMatcher.host(from: url) else {
            return false
        }
        return overrideMatch(for: host) != nil
    }

    func setOverridePercent(_ percent: Int, for url: String) {
        guard let host = DomainMatcher.host(from: url) else {
            return
        }

        var overrides = Prefs.BrowsingSettings.pageZoomOverrides
        overrides[host] = PageZoomLevel.normalizedPercent(percent)
        Prefs.BrowsingSettings.pageZoomOverrides = overrides
    }

    func resetOverride(for url: String) {
        guard let host = DomainMatcher.host(from: url),
              let matchedDomain = overrideMatch(for: host)?.domain else {
            return
        }

        var overrides = Prefs.BrowsingSettings.pageZoomOverrides
        overrides.removeValue(forKey: matchedDomain)
        Prefs.BrowsingSettings.pageZoomOverrides = overrides
    }

    func lowerPercent(for url: String?) -> Int? {
        PageZoomLevel.lowerPercent(than: zoomPercent(for: url))
    }

    func higherPercent(for url: String?) -> Int? {
        PageZoomLevel.higherPercent(than: zoomPercent(for: url))
    }

    private func overrideMatch(for host: String) -> (domain: String, percent: Int)? {
        let overrides = Prefs.BrowsingSettings.pageZoomOverrides
        if let exact = overrides[host] {
            return (host, PageZoomLevel.normalizedPercent(exact))
        }

        return overrides
            .sorted { $0.key.count > $1.key.count }
            .first { DomainMatcher.matches(host: host, domain: $0.key) }
            .map { ($0.key, PageZoomLevel.normalizedPercent($0.value)) }
    }
}
