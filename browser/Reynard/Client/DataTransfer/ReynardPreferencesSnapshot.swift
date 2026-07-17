//
//  ReynardPreferencesSnapshot.swift
//  Reynard
//

import Foundation

struct ReynardPreferencesSnapshot {
    private let defaults: UserDefaults
    private let bundleIdentifier: String
    private let registeredDefaults: [String: Any]

    init(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.minh-ton.Reynard",
        registeredDefaults: [String: Any]
    ) {
        self.defaults = defaults
        self.bundleIdentifier = bundleIdentifier
        self.registeredDefaults = registeredDefaults
    }

    func effectiveDomain() -> [String: Any] {
        registeredDefaults.merging(
            defaults.persistentDomain(forName: bundleIdentifier) ?? [:]
        ) { _, persistentValue in
            persistentValue
        }
    }
}
