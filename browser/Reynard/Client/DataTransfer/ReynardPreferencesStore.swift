//
//  ReynardPreferencesStore.swift
//  Reynard
//

import Foundation

protocol ReynardPreferencesStore: AnyObject {
    func persistentDomain() -> [String: Any]
    func replacePersistentDomain(with domain: [String: Any]) throws
    func removePersistentDomain() throws
}

final class DefaultReynardPreferencesStore: ReynardPreferencesStore {
    private let defaults: UserDefaults
    private let bundleIdentifier: String

    init(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.minh-ton.Reynard"
    ) {
        self.defaults = defaults
        self.bundleIdentifier = bundleIdentifier
    }

    func persistentDomain() -> [String: Any] {
        defaults.persistentDomain(forName: bundleIdentifier) ?? [:]
    }

    func replacePersistentDomain(with domain: [String: Any]) throws {
        defaults.setPersistentDomain(domain, forName: bundleIdentifier)
    }

    func removePersistentDomain() throws {
        defaults.removePersistentDomain(forName: bundleIdentifier)
    }
}
