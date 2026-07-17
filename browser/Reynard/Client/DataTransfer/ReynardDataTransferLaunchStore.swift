//
//  ReynardDataTransferLaunchStore.swift
//  Reynard
//

import Foundation

struct ReynardDataTransferLaunchStore {
    private struct Descriptor: Codable {
        enum Kind: String, Codable {
            case export
            case importBackup
        }

        static let currentVersion = 1

        let version: Int
        let kind: Kind
        let bookmarkData: Data?
    }

    static let shared = ReynardDataTransferLaunchStore()

    let storageKey = "Reynard.PendingDataTransfer"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pendingOperation() -> ReynardDataTransferOperation? {
        guard let storedValue = defaults.object(forKey: storageKey) else {
            return nil
        }
        guard let data = storedValue as? Data,
              let descriptor = try? JSONDecoder().decode(Descriptor.self, from: data),
              descriptor.version == Descriptor.currentVersion,
              let operation = operation(from: descriptor) else {
            clear()
            return nil
        }
        return operation
    }

    @discardableResult
    func schedule(_ operation: ReynardDataTransferOperation) -> Bool {
        guard pendingOperation() == nil else {
            return false
        }
        let descriptor: Descriptor
        switch operation {
        case .export:
            descriptor = Descriptor(
                version: Descriptor.currentVersion,
                kind: .export,
                bookmarkData: nil
            )
        case let .importBackup(bookmarkData):
            guard !bookmarkData.isEmpty else {
                return false
            }
            descriptor = Descriptor(
                version: Descriptor.currentVersion,
                kind: .importBackup,
                bookmarkData: bookmarkData
            )
        }

        guard let data = try? JSONEncoder().encode(descriptor) else {
            return false
        }
        defaults.set(data, forKey: storageKey)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private func operation(from descriptor: Descriptor) -> ReynardDataTransferOperation? {
        switch descriptor.kind {
        case .export:
            guard descriptor.bookmarkData == nil else { return nil }
            return .export
        case .importBackup:
            guard let bookmarkData = descriptor.bookmarkData,
                  !bookmarkData.isEmpty else {
                return nil
            }
            return .importBackup(bookmarkData: bookmarkData)
        }
    }
}
