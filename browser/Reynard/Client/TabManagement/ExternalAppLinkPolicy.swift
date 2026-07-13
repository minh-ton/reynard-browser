//
//  ExternalAppLinkPolicy.swift
//  Reynard
//

import Foundation

enum ExternalAppLinkKind: Hashable {
    case universalLink
    case externalScheme
}

struct ExternalAppLinkRoute: Equatable {
    let url: URL
    let kind: ExternalAppLinkKind
}

enum ExternalAppLinkRejection: Equatable {
    case noUserGesture
    case redirect
    case invalidSource
    case invalidDestination
    case internalScheme
    case unsupportedExternalScheme
}

enum ExternalAppLinkDecision: Equatable {
    case route(ExternalAppLinkRoute)
    case reject(ExternalAppLinkRejection)
}

enum ExternalAppLinkPolicy {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let internalSchemes: Set<String> = [
        "about",
        "blob",
        "data",
        "file",
        "javascript",
        "moz-extension",
        "resource",
        "view-source",
    ]
    private static let allowedExternalSchemes: Set<String> = [
        "comgooglemaps",
        "comgooglemapsurl",
        "reddit",
    ]

    static func route(
        uri: String,
        triggerUri: String?,
        hasUserGesture: Bool,
        isRedirect: Bool = false
    ) -> ExternalAppLinkRoute? {
        guard case let .route(route) = decision(
            uri: uri,
            triggerUri: triggerUri,
            hasUserGesture: hasUserGesture,
            isRedirect: isRedirect
        ) else {
            return nil
        }
        return route
    }

    static func decision(
        uri: String,
        triggerUri: String?,
        hasUserGesture: Bool,
        isRedirect: Bool = false
    ) -> ExternalAppLinkDecision {
        guard hasUserGesture else {
            return .reject(.noUserGesture)
        }
        guard !isRedirect else {
            return .reject(.redirect)
        }
        guard let triggerUri,
              let sourceURL = URL(string: triggerUri),
              let sourceScheme = sourceURL.scheme?.lowercased(),
              webSchemes.contains(sourceScheme),
              sourceURL.host?.isEmpty == false else {
            return .reject(.invalidSource)
        }
        guard let url = URL(string: uri),
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return .reject(.invalidDestination)
        }

        if webSchemes.contains(scheme) {
            guard url.host?.isEmpty == false else {
                return .reject(.invalidDestination)
            }
            return .route(ExternalAppLinkRoute(url: url, kind: .universalLink))
        }

        guard !internalSchemes.contains(scheme) else {
            return .reject(.internalScheme)
        }
        guard allowedExternalSchemes.contains(scheme) else {
            return .reject(.unsupportedExternalScheme)
        }
        return .route(ExternalAppLinkRoute(url: url, kind: .externalScheme))
    }
}
