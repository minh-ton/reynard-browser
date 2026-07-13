import Foundation

@main
struct ExternalAppLinkCoordinatorTests {
    @MainActor
    static func main() async {
        let coordinator = ExternalAppLinkCoordinator(duplicateWindow: 10)
        let session = NSObject()
        let route = ExternalAppLinkRoute(
            url: URL(string: "https://www.reddit.com/r/firefox/")!,
            kind: .universalLink
        )
        var openCount = 0

        async let first = coordinator.open(route, for: session) { _ in
            openCount += 1
            try? await Task.sleep(for: .milliseconds(25))
            return true
        }
        async let second = coordinator.open(route, for: session) { _ in
            openCount += 1
            return true
        }
        let results = await (first, second)
        precondition(results.0 && results.1)
        precondition(openCount == 1)

        let repeated = await coordinator.open(route, for: session) { _ in
            openCount += 1
            return false
        }
        precondition(repeated)
        precondition(openCount == 1)

        let otherSessionResult = await coordinator.open(route, for: NSObject()) { _ in
            openCount += 1
            return false
        }
        precondition(!otherSessionResult)
        precondition(openCount == 2)

        print("ExternalAppLinkCoordinatorTests passed")
    }
}
