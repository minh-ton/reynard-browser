import Foundation

@main
struct ReynardPreferencesSnapshotTests {
    static func main() {
        testRegisteredDefaultsAreIncluded()
        testPersistentValuesOverrideRegisteredDefaults()
        testDynamicPersistentKeysAreIncluded()
        testUnrelatedDomainsAreExcluded()
        print("ReynardPreferencesSnapshotTests passed")
    }

    private static func testRegisteredDefaultsAreIncluded() {
        withDefaults { defaults, suiteName in
            let snapshot = ReynardPreferencesSnapshot(
                defaults: defaults,
                bundleIdentifier: suiteName,
                registeredDefaults: [
                    "default.NewTabSettings.automaticallyOpensKeyboard": false,
                    "default.ToolbarSettings.bottomToolbarActions": ["back", "forward"],
                ]
            ).effectiveDomain()
            precondition(snapshot["default.NewTabSettings.automaticallyOpensKeyboard"] as? Bool == false)
            precondition(
                snapshot["default.ToolbarSettings.bottomToolbarActions"] as? [String]
                    == ["back", "forward"]
            )
        }
    }

    private static func testPersistentValuesOverrideRegisteredDefaults() {
        withDefaults { defaults, suiteName in
            defaults.set(true, forKey: "default.NewTabSettings.automaticallyOpensKeyboard")
            let snapshot = ReynardPreferencesSnapshot(
                defaults: defaults,
                bundleIdentifier: suiteName,
                registeredDefaults: ["default.NewTabSettings.automaticallyOpensKeyboard": false]
            ).effectiveDomain()
            precondition(snapshot["default.NewTabSettings.automaticallyOpensKeyboard"] as? Bool == true)
        }
    }

    private static func testDynamicPersistentKeysAreIncluded() {
        withDefaults { defaults, suiteName in
            defaults.set("dynamic", forKey: "default.Runtime.generatedValue")
            let snapshot = ReynardPreferencesSnapshot(
                defaults: defaults,
                bundleIdentifier: suiteName,
                registeredDefaults: [:]
            ).effectiveDomain()
            precondition(snapshot["default.Runtime.generatedValue"] as? String == "dynamic")
        }
    }

    private static func testUnrelatedDomainsAreExcluded() {
        withDefaults { defaults, suiteName in
            defaults.setVolatileDomain(
                ["AppleLanguages": ["unrelated"]],
                forName: UserDefaults.argumentDomain
            )
            defaults.setVolatileDomain(
                ["AppleLocale": "unrelated"],
                forName: UserDefaults.registrationDomain
            )
            let snapshot = ReynardPreferencesSnapshot(
                defaults: defaults,
                bundleIdentifier: suiteName,
                registeredDefaults: ["default.SearchSettings.searchEngine": "google"]
            ).effectiveDomain()
            precondition(snapshot["default.SearchSettings.searchEngine"] as? String == "google")
            precondition(snapshot["AppleLanguages"] == nil)
            precondition(snapshot["AppleLocale"] == nil)
        }
    }

    private static func withDefaults(
        _ body: (UserDefaults, String) -> Void
    ) {
        let suiteName = "ReynardPreferencesSnapshotTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults, suiteName)
    }
}
