//
//  ReynardMigrationTransaction.swift
//  Reynard
//

import Foundation

struct ReynardMigrationTransaction {
    private let directories: ReynardDirectories
    private let preferences: ReynardPreferencesStore
    private let fileSystem: ReynardMigrationFileSystem
    private let validator: ReynardBackupValidator
    private let identifier: () -> UUID

    init(
        directories: ReynardDirectories = .shared,
        preferences: ReynardPreferencesStore = DefaultReynardPreferencesStore(),
        fileSystem: ReynardMigrationFileSystem = DefaultReynardMigrationFileSystem(),
        validator: ReynardBackupValidator = ReynardBackupValidator(),
        identifier: @escaping () -> UUID = UUID.init
    ) {
        self.directories = directories
        self.preferences = preferences
        self.fileSystem = fileSystem
        self.validator = validator
        self.identifier = identifier
    }

    func apply(_ backup: ValidatedReynardBackup) throws {
        let migrationRoot = directories.migrationRecovery
        let operationRoot = migrationRoot.appendingPathComponent(identifier().uuidString, isDirectory: true)
        let stagingRoot = operationRoot.appendingPathComponent("staging", isDirectory: true)
        let rollbackRoot = operationRoot.appendingPathComponent("rollback", isDirectory: true)
        let stagedBackup = stagingRoot.appendingPathComponent("backup.reynardbackup", isDirectory: true)
        let rollbackApplicationSupport = rollbackRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let rollbackDownloads = rollbackRoot.appendingPathComponent("Downloads", isDirectory: true)
        let rollbackPreferences = rollbackRoot.appendingPathComponent("preferences.plist", isDirectory: false)
        let journalURL = operationRoot.appendingPathComponent("journal.json", isDirectory: false)

        var journalWritten = false
        var ownsOperationRoot = false

        do {
            guard !fileSystem.fileExists(at: operationRoot) else {
                throw ReynardDataTransferError.stagingFailure
            }
            ownsOperationRoot = true
            try fileSystem.createDirectory(at: stagingRoot)
            try fileSystem.createDirectory(at: rollbackRoot)
            try fileSystem.checkpoint(.beforeStaging)

            try fileSystem.copyItem(at: backup.rootURL, to: stagedBackup)
            try fileSystem.checkpoint(.afterStaging)

            let staged = try validator.validate(at: stagedBackup, availableCapacity: UInt64.max)
            guard staged.manifest == backup.manifest else {
                throw ReynardDataTransferError.stagingFailure
            }

            let stagedApplicationSupport = stagedBackup.appendingPathComponent(
                "payload/ApplicationSupport",
                isDirectory: true
            )
            let stagedDownloads = stagedBackup.appendingPathComponent(
                "payload/Downloads",
                isDirectory: true
            )
            if !fileSystem.fileExists(at: stagedApplicationSupport) {
                try fileSystem.createDirectory(at: stagedApplicationSupport)
            }
            if !fileSystem.fileExists(at: stagedDownloads) {
                try fileSystem.createDirectory(at: stagedDownloads)
            }

            let importedPreferences = try decodePreferences(
                from: fileSystem.readData(at: staged.preferencesURL)
            )
            let oldPreferencesData = try encodePreferences(preferences.persistentDomain())
            try fileSystem.writeData(oldPreferencesData, to: rollbackPreferences)

            let applicationSupportExisted = fileSystem.fileExists(at: directories.applicationSupport)
            let downloadsExisted = fileSystem.fileExists(at: directories.downloads)
            let journal = ReynardMigrationJournal(
                version: ReynardMigrationJournal.currentVersion,
                applicationSupportExisted: applicationSupportExisted,
                downloadsExisted: downloadsExisted
            )
            try fileSystem.writeData(try JSONEncoder().encode(journal), to: journalURL)
            journalWritten = true

            if applicationSupportExisted {
                try fileSystem.moveItem(
                    at: directories.applicationSupport,
                    to: rollbackApplicationSupport
                )
            }
            if downloadsExisted {
                try fileSystem.moveItem(at: directories.downloads, to: rollbackDownloads)
            }
            try fileSystem.checkpoint(.afterRollbackRename)

            try fileSystem.createDirectory(at: directories.applicationSupport.deletingLastPathComponent())
            try fileSystem.moveItem(at: stagedApplicationSupport, to: directories.applicationSupport)
            try fileSystem.checkpoint(.afterFirstFinalRename)

            try fileSystem.createDirectory(at: directories.downloads.deletingLastPathComponent())
            try fileSystem.moveItem(at: stagedDownloads, to: directories.downloads)
            try fileSystem.checkpoint(.afterSecondFinalRename)

            try preferences.replacePersistentDomain(with: importedPreferences)
            try fileSystem.checkpoint(.duringPreferenceImport)

            try verifyAppliedBackup(staged, importedPreferences: importedPreferences)
            try? fileSystem.removeItem(at: operationRoot)
            removeMigrationRootIfEmpty(migrationRoot)
        } catch {
            guard journalWritten else {
                if ownsOperationRoot {
                    try? fileSystem.removeItem(at: operationRoot)
                }
                removeMigrationRootIfEmpty(migrationRoot)
                throw ReynardDataTransferError.stagingFailure
            }

            do {
                try ReynardMigrationRecovery(
                    directories: directories,
                    preferences: preferences,
                    fileSystem: fileSystem
                ).recoverOperation(at: operationRoot)
            } catch {
                throw ReynardDataTransferError.rollbackFailure
            }
            throw ReynardDataTransferError.applyFailure
        }
    }

    private func verifyAppliedBackup(
        _ backup: ValidatedReynardBackup,
        importedPreferences: [String: Any]
    ) throws {
        for file in backup.files where file.relativePath != "preferences.plist" {
            let destination: URL
            let applicationSupportPrefix = "payload/ApplicationSupport/"
            let downloadsPrefix = "payload/Downloads/"
            if file.relativePath.hasPrefix(applicationSupportPrefix) {
                destination = directories.applicationSupport.appendingPathComponent(
                    String(file.relativePath.dropFirst(applicationSupportPrefix.count)),
                    isDirectory: false
                )
            } else if file.relativePath.hasPrefix(downloadsPrefix) {
                destination = directories.downloads.appendingPathComponent(
                    String(file.relativePath.dropFirst(downloadsPrefix.count)),
                    isDirectory: false
                )
            } else {
                throw ReynardDataTransferError.applyFailure
            }

            guard try ReynardFileHasher.regularFileSize(at: destination) == file.size,
                  try ReynardFileHasher.sha256(of: destination) == file.sha256 else {
                throw ReynardDataTransferError.applyFailure
            }
        }
        guard preferencesEqual(preferences.persistentDomain(), importedPreferences) else {
            throw ReynardDataTransferError.applyFailure
        }
    }

    private func decodePreferences(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let domain = value as? [String: Any] else {
            throw ReynardDataTransferError.invalidManifest
        }
        return domain
    }

    private func encodePreferences(_ domain: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: domain,
            format: .binary,
            options: 0
        )
    }

    private func preferencesEqual(_ first: [String: Any], _ second: [String: Any]) -> Bool {
        NSDictionary(dictionary: first).isEqual(to: second)
    }

    private func removeMigrationRootIfEmpty(_ migrationRoot: URL) {
        try? fileSystem.removeDirectoryIfEmpty(at: migrationRoot)
    }
}
