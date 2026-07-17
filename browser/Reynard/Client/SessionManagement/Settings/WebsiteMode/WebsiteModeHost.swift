//
//  WebsiteModeHost.swift
//  Reynard
//

import Foundation

enum WebsiteModeHost {
    // Mobile host aliases share one website-mode preference. Other subdomains,
    // including www, remain independent sites.
    static func normalized(_ host: String) -> String {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for prefix in ["m.", "mobile."] where normalizedHost.hasPrefix(prefix) {
            return String(normalizedHost.dropFirst(prefix.count))
        }
        return normalizedHost
    }

    static func areRelated(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    static func relatedAliases(for host: String) -> Set<String> {
        Set(orderedAliases(for: host))
    }

    static func orderedAliases(for host: String) -> [String] {
        let canonicalHost = normalized(host)
        guard !canonicalHost.isEmpty else {
            return []
        }
        return [canonicalHost, "m.\(canonicalHost)", "mobile.\(canonicalHost)"]
    }
}
