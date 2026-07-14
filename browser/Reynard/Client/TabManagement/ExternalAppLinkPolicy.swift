//
//  ExternalAppLinkPolicy.swift
//  Reynard
//

import Foundation

enum ExternalAppLinkRequestSource: Equatable {
    case navigation
    case trustedLink
    case externalProtocol
}

struct ExternalAppLinkRequest: Equatable {
    let uri: String
    let triggerUri: String?
    let source: ExternalAppLinkRequestSource
    let hasUserGesture: Bool
    var isRedirect = false
    var isDefaultPrevented = false
}

enum ExternalAppLinkOpeningMode: Equatable {
    case universalLink
    case externalScheme
}

struct ExternalAppLinkAttempt: Equatable {
    let url: URL
    let mode: ExternalAppLinkOpeningMode
}

struct ExternalAppLinkRoute: Equatable {
    let primary: ExternalAppLinkAttempt
    let fallback: ExternalAppLinkAttempt?

    init(primary: ExternalAppLinkAttempt, fallback: ExternalAppLinkAttempt? = nil) {
        self.primary = primary
        self.fallback = fallback
    }
}

enum ExternalAppLinkRejection: Equatable {
    case noUserGesture
    case redirect
    case defaultPrevented
    case invalidSource
    case invalidDestination
    case internalScheme
    case unsupportedExternalScheme
    case sourceMismatch
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
    private static let directExternalSchemes: Set<String> = [
        "comgooglemaps",
        "comgooglemapsurl",
        "reddit",
    ]

    static func decision(for request: ExternalAppLinkRequest) -> ExternalAppLinkDecision {
        guard request.hasUserGesture else {
            return .reject(.noUserGesture)
        }
        guard !request.isRedirect else {
            return .reject(.redirect)
        }
        guard !request.isDefaultPrevented else {
            return .reject(.defaultPrevented)
        }
        guard let sourceURL = validWebURL(from: request.triggerUri) else {
            return .reject(.invalidSource)
        }
        guard let destinationURL = URL(string: request.uri),
              let scheme = destinationURL.scheme?.lowercased(),
              !scheme.isEmpty else {
            return .reject(.invalidDestination)
        }

        if webSchemes.contains(scheme) {
            guard validWebURL(from: request.uri) != nil else {
                return .reject(.invalidDestination)
            }
            guard request.source == .trustedLink else {
                return .reject(.sourceMismatch)
            }
            return .route(route(to: destinationURL, mode: .universalLink))
        }

        guard !internalSchemes.contains(scheme) else {
            return .reject(.internalScheme)
        }
        guard request.source != .trustedLink else {
            return .reject(.sourceMismatch)
        }

        if directExternalSchemes.contains(scheme) {
            return .route(route(to: destinationURL, mode: .externalScheme))
        }
        if scheme == "intent", let googleMapsURL = googleMapsURL(fromAndroidIntent: request.uri) {
            return .route(route(to: googleMapsURL, mode: .externalScheme))
        }
        if scheme == "market", isRedditMarketLink(destinationURL) {
            return .route(redditRoute(triggerURL: sourceURL))
        }
        return .reject(.unsupportedExternalScheme)
    }

    private static func route(
        to url: URL,
        mode: ExternalAppLinkOpeningMode
    ) -> ExternalAppLinkRoute {
        ExternalAppLinkRoute(primary: ExternalAppLinkAttempt(url: url, mode: mode))
    }

    private static func validWebURL(from value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              webSchemes.contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func googleMapsURL(fromAndroidIntent value: String) -> URL? {
        let prefix = "intent://"
        guard value.hasPrefix(prefix),
              let marker = value.range(of: "#Intent;", options: .backwards),
              marker.lowerBound > value.index(value.startIndex, offsetBy: prefix.count) else {
            return nil
        }

        let metadataWithTerminator = String(value[marker.upperBound...])
        let metadata: String
        if metadataWithTerminator.hasSuffix(";end;") {
            metadata = String(metadataWithTerminator.dropLast(5))
        } else if metadataWithTerminator.hasSuffix(";end") {
            metadata = String(metadataWithTerminator.dropLast(4))
        } else {
            return nil
        }

        let parameters = metadata.split(separator: ";").reduce(into: [String: String]()) { result, item in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return }
            result[pair[0]] = pair[1]
        }
        guard parameters["package"] == "com.google.android.apps.maps" else {
            return nil
        }

        let webScheme = parameters["scheme"]?.lowercased() ?? "https"
        guard webSchemes.contains(webScheme) else {
            return nil
        }
        let destination = value[value.index(value.startIndex, offsetBy: prefix.count)..<marker.lowerBound]
        guard let webURL = validWebURL(from: "\(webScheme)://\(destination)"),
              isGoogleMapsWebURL(webURL) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "comgooglemapsurl"
        components.host = "google"
        components.path = "/link"
        components.queryItems = [URLQueryItem(name: "deep_link_id", value: webURL.absoluteString)]
        return components.url
    }

    private static func isGoogleMapsWebURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "maps.app.goo.gl" {
            return true
        }
        let isGoogleHost = host == "google.com" || host.hasSuffix(".google.com")
        let path = url.path.lowercased()
        return isGoogleHost && (path == "/maps" || path.hasPrefix("/maps/"))
    }

    private static func isRedditMarketLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains {
            $0.name == "id" && $0.value == "com.reddit.frontpage"
        } == true
    }

    private static func redditRoute(triggerURL: URL) -> ExternalAppLinkRoute {
        let fallback = ExternalAppLinkAttempt(url: URL(string: "reddit://")!, mode: .externalScheme)
        let host = triggerURL.host?.lowercased() ?? ""
        guard host == "reddit.com" || host.hasSuffix(".reddit.com") else {
            return ExternalAppLinkRoute(primary: fallback)
        }
        return ExternalAppLinkRoute(
            primary: ExternalAppLinkAttempt(url: triggerURL, mode: .universalLink),
            fallback: fallback
        )
    }
}
