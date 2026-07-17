//
//  ReynardBackupContentPolicy.swift
//  Reynard
//

import Foundation

struct ReynardBackupContentPolicy {
    private static let excludedMozillaComponents: Set<String> = [
        "cache2",
        "crashes",
        "datareporting",
        "minidumps",
        "offlinecache",
        "pending_pings",
        "saved-telemetry-pings",
        "shader-cache",
        "startupcache",
    ]

    func includes(relativePath: String) -> Bool {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else {
            return false
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return false
        }

        if components.contains(".com.apple.mobile_container_manager.metadata.plist") {
            return false
        }

        if components.starts(with: ["Downloads"]) {
            return components.count > 1
        }

        if components.starts(with: ["ApplicationSupport", "AppData"]) {
            return components.count > 2
        }

        if components.starts(with: ["ApplicationSupport", ".mozilla"]) {
            guard components.count > 2 else {
                return false
            }
            let mozillaComponents = components.dropFirst(2).map { $0.lowercased() }
            return Self.excludedMozillaComponents.isDisjoint(with: mozillaComponents)
        }

        return false
    }
}
