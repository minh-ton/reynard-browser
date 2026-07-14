import Foundation

@main
struct ExternalAppLinkRouterTests {
    @MainActor
    static func main() async {
        await verifiesAutomaticRoutingSetting()
        await verifiesExplicitExternalProtocolStillOpens()
        await verifiesFailedOpenPreservesFallback()
        await verifiesRedditFallbackOrder()
        print("ExternalAppLinkRouterTests passed")
    }

    @MainActor
    private static func verifiesAutomaticRoutingSetting() async {
        var openCount = 0
        let router = ExternalAppLinkRouter(
            isAutomaticRoutingEnabled: { false },
            open: { _ in
                openCount += 1
                return true
            }
        )
        let disposition = await router.handle(request(
            uri: "https://www.reddit.com/r/firefox/",
            source: .trustedLink
        ))
        precondition(disposition == .automaticRoutingDisabled)
        precondition(openCount == 0)
    }

    @MainActor
    private static func verifiesExplicitExternalProtocolStillOpens() async {
        var openedURL: URL?
        let router = ExternalAppLinkRouter(
            isAutomaticRoutingEnabled: { false },
            open: { attempt in
                openedURL = attempt.url
                return true
            }
        )
        let disposition = await router.handle(request(
            uri: "comgooglemaps://?q=Minneapolis",
            source: .externalProtocol
        ))
        precondition(disposition == .opened)
        precondition(openedURL?.scheme == "comgooglemaps")
    }

    @MainActor
    private static func verifiesFailedOpenPreservesFallback() async {
        let router = ExternalAppLinkRouter(
            isAutomaticRoutingEnabled: { true },
            open: { _ in false }
        )
        let disposition = await router.handle(request(
            uri: "https://www.reddit.com/r/firefox/",
            source: .trustedLink
        ))
        precondition(disposition == .notOpened)
    }

    @MainActor
    private static func verifiesRedditFallbackOrder() async {
        var attempts: [ExternalAppLinkAttempt] = []
        let router = ExternalAppLinkRouter(
            isAutomaticRoutingEnabled: { true },
            open: { attempt in
                attempts.append(attempt)
                return attempts.count == 2
            }
        )
        let disposition = await router.handle(request(
            uri: "market://details?id=com.reddit.frontpage",
            source: .externalProtocol
        ))
        precondition(disposition == .opened)
        precondition(attempts.map(\.mode) == [.universalLink, .externalScheme])
        precondition(attempts.last?.url.scheme == "reddit")
    }

    private static func request(
        uri: String,
        source: ExternalAppLinkRequestSource
    ) -> ExternalAppLinkRequest {
        ExternalAppLinkRequest(
            uri: uri,
            triggerUri: "https://www.reddit.com/r/firefox/",
            source: source,
            hasUserGesture: true
        )
    }
}
