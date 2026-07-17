import Foundation

@main
enum SitePermissionDecisionPolicyTests {
    static func main() {
        precondition(SitePermissionDecisionPolicy.decision(forStoredAction: "allowed") == .allow)
        precondition(SitePermissionDecisionPolicy.decision(forStoredAction: "blocked") == .deny)
        precondition(SitePermissionDecisionPolicy.decision(forStoredAction: "ask_to_allow") == .prompt)
        precondition(SitePermissionDecisionPolicy.decision(forStoredAction: "invalid") == .prompt)
        precondition(SitePermissionDecisionPolicy.storageScope(isPrivate: false) == .persistent)
        precondition(SitePermissionDecisionPolicy.storageScope(isPrivate: true) == .sessionOnly)

        precondition(
            SitePermissionDecisionPolicy.normalizedHTTPHost(
                fromRawURI: "https://WWW.Example.com:8443/path"
            ) == "www.example.com"
        )
        precondition(
            SitePermissionDecisionPolicy.normalizedHTTPHost(
                fromRawURI: "https://sensors.example.com./"
            ) == "sensors.example.com"
        )
        precondition(SitePermissionDecisionPolicy.normalizedHTTPHost(fromRawURI: "not a URL") == nil)
        precondition(SitePermissionDecisionPolicy.normalizedHTTPHost(fromRawURI: "file:///tmp/test") == nil)
        precondition(SitePermissionDecisionPolicy.normalizedHTTPHost(fromRawURI: "javascript:alert(1)") == nil)
        print("SitePermissionDecisionPolicyTests passed")
    }
}
