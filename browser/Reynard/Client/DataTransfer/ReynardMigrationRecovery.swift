//
//  ReynardMigrationRecovery.swift
//  Reynard
//

import Foundation

struct ReynardMigrationJournal: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let applicationSupportExisted: Bool
    let downloadsExisted: Bool
}

struct ReynardMigrationRecovery {
    private let directories: ReynardDirectories
    private let preferences: ReynardPreferencesStore
    private let fileSystem: ReynardMigrationFileSystem

    init(
        directories: ReynardDirectories = .shared,
        preferences: ReynardPreferencesStore = DefaultReynardPreferencesStore(),
        fileSystem: ReynardMigrationFileSystem = DefaultReynardMigrationFileSystem()
    ) {
        self.directories = directories
        self.preferences = preferences
        self.fileSystem = fileSystem
    }

    func recoverPendingTransactions() throws {
        let recoveryRoot = directories.migrationRecovery
        guard fileSystem.fileExists(at: recoveryRoot) else { return }
        guard fileSystem.isDirectory(at: recoveryRoot) else {
            throw ReynardDataTransferError.rollbackFailure
        }

        let operations: [URL]
        do {
            operations = try fileSystem.contentsOfDirectory(at: recoveryRoot)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw ReynardDataTransferError.rollbackFailure
        }
        for operation in operations {
            try recoverOperation(at: operation)
        }
        try removeRecoveryRootIfEmpty()
    }

    func recoverOperation(at operationURL: URL) throws {
        do {
            try recoverOperationContents(at: operationURL)
        } catch {
            throw ReynardDataTransferError.rollbackFailure
        }
    }

    private func recoverOperationContents(at operationURL: URL) throws {
        let recoveryRoot = directories.migrationRecovery.standardizedFileURL
        let operation = operationURL.standardizedFileURL
        guard operation.deletingLastPathComponent() == recoveryRoot,
              fileSystem.isDirectory(at: operation) else {
            throw ReynardDataTransferError.rollbackFailure
        }

        let journalURL = operation.appendingPathComponent("journal.json", isDirectory: false)
        guard fileSystem.fileExists(at: journalURL) else {
            try fileSystem.removeItem(at: operation)
            try removeRecoveryRootIfEmpty()
            return
        }
        guard fileSystem.isRegularFile(at: journalURL) else {
            throw ReynardDataTransferError.rollbackFailure
        }

        let journal = try decodeJournal(fileSystem.readData(at: journalURL))
        let rollbackRoot = operation.appendingPathComponent("rollback", isDirectory: true)
        let rollbackPreferences = rollbackRoot.appendingPathComponent(
            "preferences.plist",
            isDirectory: false
        )
        guard fileSystem.isRegularFile(at: rollbackPreferences) else {
            throw ReynardDataTransferError.rollbackFailure
        }

        try restoreRoot(
            live: directories.applicationSupport,
            rollback: rollbackRoot.appendingPathComponent("ApplicationSupport", isDirectory: true),
            originallyExisted: journal.applicationSupportExisted
        )
        try restoreRoot(
            live: directories.downloads,
            rollback: rollbackRoot.appendingPathComponent("Downloads", isDirectory: true),
            originallyExisted: journal.downloadsExisted
        )

        let oldPreferences = try decodePreferences(fileSystem.readData(at: rollbackPreferences))
        try preferences.replacePersistentDomain(with: oldPreferences)
        guard preferencesEqual(preferences.persistentDomain(), oldPreferences) else {
            throw ReynardDataTransferError.rollbackFailure
        }

        try fileSystem.removeItem(at: operation)
        try removeRecoveryRootIfEmpty()
    }

    private func restoreRoot(
        live: URL,
        rollback: URL,
        originallyExisted: Bool
    ) throws {
        if fileSystem.fileExists(at: rollback) {
            guard originallyExisted, fileSystem.isDirectory(at: rollback) else {
                throw ReynardDataTransferError.rollbackFailure
            }
            if fileSystem.fileExists(at: live) {
                try fileSystem.removeItem(at: live)
            }
            try fileSystem.createDirectory(at: live.deletingLastPathComponent())
            try fileSystem.moveItem(at: rollback, to: live)
            return
        }

        if originallyExisted {
            guard fileSystem.isDirectory(at: live) else {
                throw ReynardDataTransferError.rollbackFailure
            }
        } else if fileSystem.fileExists(at: live) {
            try fileSystem.removeItem(at: live)
        }
    }

    private func decodeJournal(_ data: Data) throws -> ReynardMigrationJournal {
        let journal = try JSONDecoder().decode(ReynardMigrationJournal.self, from: data)
        guard journal.version == ReynardMigrationJournal.currentVersion else {
            throw ReynardDataTransferError.rollbackFailure
        }
        return journal
    }

    private func decodePreferences(_ data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let domain = value as? [String: Any] else {
            throw ReynardDataTransferError.rollbackFailure
        }
        return domain
    }

    private func preferencesEqual(_ first: [String: Any], _ second: [String: Any]) -> Bool {
        NSDictionary(dictionary: first).isEqual(to: second)
    }

    private func removeRecoveryRootIfEmpty() throws {
        try fileSystem.removeDirectoryIfEmpty(at: directories.migrationRecovery)
    }
}
