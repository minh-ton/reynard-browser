import Foundation

@main
struct DefaultBrowserSettingsPolicyTests {
    static func main() {
        expect(.applicationSettings, major: 15, minor: 0)
        expect(.applicationSettings, major: 18, minor: 2)
        expect(.defaultApplicationsSettings, major: 18, minor: 3)
        expect(.defaultApplicationsSettings, major: 19, minor: 0)
        print("DefaultBrowserSettingsPolicyTests passed")
    }

    private static func expect(
        _ expected: DefaultBrowserSettingsDestination,
        major: Int,
        minor: Int
    ) {
        let version = OperatingSystemVersion(
            majorVersion: major,
            minorVersion: minor,
            patchVersion: 0
        )
        precondition(DefaultBrowserSettingsPolicy.destination(for: version) == expected)
    }
}
