import Foundation

@main
struct ExternalAppLinkPolicyTests {
    static func main() {
        let redditUniversalLink = ExternalAppLinkPolicy.route(
            uri: "https://www.reddit.com/r/firefox/",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        )
        precondition(redditUniversalLink?.kind == .universalLink)

        let redditScheme = ExternalAppLinkPolicy.route(
            uri: "reddit://r/firefox/",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        )
        precondition(redditScheme?.kind == .externalScheme)

        precondition(ExternalAppLinkPolicy.route(
            uri: "https://www.reddit.com/r/firefox/",
            triggerUri: nil,
            hasUserGesture: true
        ) == nil)
        precondition(ExternalAppLinkPolicy.route(
            uri: "reddit://r/firefox/",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: false
        ) == nil)
        precondition(ExternalAppLinkPolicy.route(
            uri: "about:blank",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == nil)
        precondition(ExternalAppLinkPolicy.route(
            uri: "blob:https://www.reddit.com/id",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == nil)
        precondition(ExternalAppLinkPolicy.decision(
            uri: "https://www.reddit.com/r/firefox/",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true,
            isRedirect: true
        ) == .reject(.redirect))
        precondition(ExternalAppLinkPolicy.decision(
            uri: "https://www.reddit.com/r/firefox/",
            triggerUri: "about:blank",
            hasUserGesture: true
        ) == .reject(.invalidSource))
        precondition(ExternalAppLinkPolicy.decision(
            uri: "https:///missing-host",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == .reject(.invalidDestination))
        precondition(ExternalAppLinkPolicy.decision(
            uri: "file:///private/etc/passwd",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == .reject(.internalScheme))
        precondition(ExternalAppLinkPolicy.decision(
            uri: "tel:+15555550123",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == .reject(.unsupportedExternalScheme))
        precondition(ExternalAppLinkPolicy.decision(
            uri: "sms:+15555550123",
            triggerUri: "https://www.reddit.com/",
            hasUserGesture: true
        ) == .reject(.unsupportedExternalScheme))

        print("ExternalAppLinkPolicyTests passed")
    }
}
