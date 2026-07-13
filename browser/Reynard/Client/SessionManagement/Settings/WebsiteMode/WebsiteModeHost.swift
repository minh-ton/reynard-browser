//
//  WebsiteModeHost.swift
//  Reynard
//

import Foundation

enum WebsiteModeHost {
    static func normalized(_ host: String) -> String {
        let normalizedHost = host.lowercased()
        for prefix in ["m.", "mobile."] where normalizedHost.hasPrefix(prefix) {
            return String(normalizedHost.dropFirst(prefix.count))
        }
        return normalizedHost
    }

    static func areRelated(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    static func relatedAliases(for host: String) -> Set<String> {
        let canonicalHost = normalized(host)
        return [canonicalHost, "m.\(canonicalHost)", "mobile.\(canonicalHost)"]
    }
}
