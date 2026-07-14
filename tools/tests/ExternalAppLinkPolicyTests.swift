import Foundation

@main
struct ExternalAppLinkPolicyTests {
    static func main() {
        expectRoute(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .trustedLink
            ),
            mode: .universalLink
        )
        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .navigation
            ),
            .sourceMismatch
        )
        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .externalProtocol
            ),
            .sourceMismatch
        )

        for uri in [
            "reddit://r/firefox/",
            "comgooglemaps://?q=Total%20Wine",
            "comgooglemapsurl://google/link?deep_link_id=example",
        ] {
            expectRoute(request(uri: uri, source: .externalProtocol), mode: .externalScheme)
            expectRoute(request(uri: uri, source: .navigation), mode: .externalScheme)
            expectRejection(request(uri: uri, source: .trustedLink), .sourceMismatch)
        }

        let googleIntent = "intent://www.google.com/maps/dir/?api=1#Intent;scheme=https;package=com.google.android.apps.maps;end"
        guard case let .route(googleRoute) = ExternalAppLinkPolicy.decision(
            for: request(uri: googleIntent, source: .externalProtocol)
        ) else {
            preconditionFailure("Expected a Google Maps intent route")
        }
        precondition(googleRoute.primary.mode == .externalScheme)
        precondition(googleRoute.primary.url.scheme == "comgooglemapsurl")
        precondition(googleRoute.primary.url.absoluteString.contains("deep_link_id="))

        expectRejection(
            request(
                uri: "intent://example.com/#Intent;scheme=https;package=com.example.app;end",
                source: .externalProtocol
            ),
            .unsupportedExternalScheme
        )

        guard case let .route(redditRoute) = ExternalAppLinkPolicy.decision(for: request(
            uri: "market://details?id=com.reddit.frontpage",
            source: .externalProtocol
        )) else {
            preconditionFailure("Expected a Reddit market fallback route")
        }
        precondition(redditRoute.primary.mode == .universalLink)
        precondition(redditRoute.primary.url.host == "www.reddit.com")
        precondition(redditRoute.fallback?.url.scheme == "reddit")

        guard case let .route(untrustedRedditRoute) = ExternalAppLinkPolicy.decision(for: request(
            uri: "market://details?id=com.reddit.frontpage",
            triggerUri: "https://notreddit.com/",
            source: .externalProtocol
        )) else {
            preconditionFailure("Expected a direct Reddit fallback route")
        }
        precondition(untrustedRedditRoute.primary.url.scheme == "reddit")
        precondition(untrustedRedditRoute.fallback == nil)

        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .trustedLink,
                hasUserGesture: false
            ),
            .noUserGesture
        )
        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .trustedLink,
                isRedirect: true
            ),
            .redirect
        )
        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                source: .trustedLink,
                isDefaultPrevented: true
            ),
            .defaultPrevented
        )
        expectRejection(
            request(
                uri: "https://www.reddit.com/r/firefox/",
                triggerUri: nil,
                source: .trustedLink
            ),
            .invalidSource
        )
        expectRejection(request(uri: "about:blank", source: .navigation), .internalScheme)
        expectRejection(request(uri: "blob:https://www.reddit.com/id", source: .navigation), .internalScheme)
        expectRejection(request(uri: "https:///missing-host", source: .trustedLink), .invalidDestination)
        expectRejection(request(uri: "tel:+15555550123", source: .externalProtocol), .unsupportedExternalScheme)

        print("ExternalAppLinkPolicyTests passed")
    }

    private static func request(
        uri: String,
        triggerUri: String? = "https://www.reddit.com/",
        source: ExternalAppLinkRequestSource,
        hasUserGesture: Bool = true,
        isRedirect: Bool = false,
        isDefaultPrevented: Bool = false
    ) -> ExternalAppLinkRequest {
        ExternalAppLinkRequest(
            uri: uri,
            triggerUri: triggerUri,
            source: source,
            hasUserGesture: hasUserGesture,
            isRedirect: isRedirect,
            isDefaultPrevented: isDefaultPrevented
        )
    }

    private static func expectRoute(
        _ request: ExternalAppLinkRequest,
        mode: ExternalAppLinkOpeningMode
    ) {
        guard case let .route(route) = ExternalAppLinkPolicy.decision(for: request) else {
            preconditionFailure("Expected route for \(request.uri)")
        }
        precondition(route.primary.mode == mode)
    }

    private static func expectRejection(
        _ request: ExternalAppLinkRequest,
        _ expected: ExternalAppLinkRejection
    ) {
        precondition(ExternalAppLinkPolicy.decision(for: request) == .reject(expected))
    }
}
