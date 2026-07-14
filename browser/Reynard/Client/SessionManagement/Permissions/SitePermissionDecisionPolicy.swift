//
//  SitePermissionDecisionPolicy.swift
//  Reynard
//

import Foundation

enum SitePermissionPromptDecision: Equatable {
    case allow
    case deny
    case prompt
}

enum SitePermissionDecisionPolicy {
    enum StorageScope: Equatable {
        case persistent
        case sessionOnly
    }

    static func storageScope(isPrivate: Bool) -> StorageScope {
        isPrivate ? .sessionOnly : .persistent
    }

    static func decision(forStoredAction rawValue: String) -> SitePermissionPromptDecision {
        switch rawValue {
        case "allowed":
            return .allow
        case "blocked":
            return .deny
        default:
            return .prompt
        }
    }

    static func normalizedHTTPHost(fromRawURI rawURI: String) -> String? {
        guard let components = URLComponents(string: rawURI),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            return nil
        }
        return host
    }
}
