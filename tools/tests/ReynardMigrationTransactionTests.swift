import Foundation

@main
struct ReynardMigrationTransactionTests {
    static func main() throws {
        try testSuccessfulImportReplacesDataAndPreferences()
        try testEveryFailureBoundaryRestoresOriginalData()
        try testRollbackFailurePreservesRecoveryData()
        try testUnrelatedRecoveryDataIsPreserved()
        try testOperationIdentifierCollisionIsRejected()
        try testStagedCorruptionIsRejectedBeforeLiveDataChanges()
        print("ReynardMigrationTransactionTests passed")
    }

    private static func testSuccessfulImportReplacesDataAndPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let validated = try fixture.validatedBackup()
        let transaction = ReynardMigrationTransaction(
            directories: fixture.directories,
            preferences: fixture.preferences,
            fileSystem: TestMigrationFileSystem()
        )
        try transaction.apply(validated)

        let importedAppData = try Data(
            contentsOf: fixture.directories.appData.appendingPathComponent("new.json")
        )
        let importedDownload = try Data(
            contentsOf: fixture.directories.downloads.appendingPathComponent("new.txt")
        )
        precondition(importedAppData == Data("new-data".utf8))
        precondition(importedDownload == Data("new-download".utf8))
        precondition(!FileManager.default.fileExists(atPath: fixture.directories.appData.appendingPathComponent("old.json").path))
        precondition(fixture.preferences.domain["state"] as? String == "new")
        precondition(!FileManager.default.fileExists(
            atPath: fixture.directories.migrationRecovery.path
        ))
    }

    private static func testEveryFailureBoundaryRestoresOriginalData() throws {
        for boundary in ReynardMigrationBoundary.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let originalFiles = try snapshot(fixture.liveRoots)
            let originalPreferences = fixture.preferences.domain

            let transaction = ReynardMigrationTransaction(
                directories: fixture.directories,
                preferences: fixture.preferences,
                fileSystem: TestMigrationFileSystem(failingAt: boundary)
            )
            let expectedError: ReynardDataTransferError = boundary == .beforeStaging || boundary == .afterStaging
                ? .stagingFailure
                : .applyFailure
            do {
                try transaction.apply(fixture.validatedBackup())
                preconditionFailure("Expected injected failure at \(boundary)")
            } catch let error as ReynardDataTransferError {
                precondition(error == expectedError)
            }

            let restoredFiles = try snapshot(fixture.liveRoots)
            precondition(restoredFiles == originalFiles, "Data changed after failure at \(boundary)")
            precondition(NSDictionary(dictionary: fixture.preferences.domain).isEqual(to: originalPreferences))
        }
    }

    private static func testRollbackFailurePreservesRecoveryData() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileSystem = TestMigrationFileSystem(
            failingAt: .afterFirstFinalRename,
            failRollbackRestore: true
        )
        let transaction = ReynardMigrationTransaction(
            directories: fixture.directories,
            preferences: fixture.preferences,
            fileSystem: fileSystem
        )

        do {
            try transaction.apply(fixture.validatedBackup())
            preconditionFailure("Expected rollback failure")
        } catch let error as ReynardDataTransferError {
            precondition(error == .rollbackFailure)
        }

        let migrationRoot = fixture.directories.migrationRecovery
        guard let enumerator = FileManager.default.enumerator(
            at: migrationRoot,
            includingPropertiesForKeys: nil
        ) else {
            preconditionFailure("Rollback evidence must remain available")
        }
        let paths = enumerator.compactMap { ($0 as? URL)?.path }
        precondition(paths.contains { $0.hasSuffix("rollback/ApplicationSupport") })
        precondition(paths.contains { $0.hasSuffix("rollback/preferences.plist") })
    }

    private static func testUnrelatedRecoveryDataIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let evidence = fixture.directories.migrationRecovery.appendingPathComponent(
            "existing/rollback/evidence",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: evidence.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preserve".utf8).write(to: evidence)

        try ReynardMigrationTransaction(
            directories: fixture.directories,
            preferences: fixture.preferences,
            fileSystem: TestMigrationFileSystem()
        ).apply(fixture.validatedBackup())

        let preservedEvidence = try Data(contentsOf: evidence)
        precondition(preservedEvidence == Data("preserve".utf8))
    }

    private static func testOperationIdentifierCollisionIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let evidence = fixture.directories.migrationRecovery.appendingPathComponent(
            "\(operationIdentifier.uuidString)/rollback/evidence",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: evidence.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preserve".utf8).write(to: evidence)

        do {
            try ReynardMigrationTransaction(
                directories: fixture.directories,
                preferences: fixture.preferences,
                fileSystem: TestMigrationFileSystem(),
                identifier: { operationIdentifier }
            ).apply(fixture.validatedBackup())
            preconditionFailure("An existing operation identifier must be rejected")
        } catch let error as ReynardDataTransferError {
            precondition(error == .stagingFailure)
        }
        let preservedEvidence = try Data(contentsOf: evidence)
        precondition(preservedEvidence == Data("preserve".utf8))
    }

    private static func testStagedCorruptionIsRejectedBeforeLiveDataChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFiles = try snapshot(fixture.liveRoots)
        let originalPreferences = fixture.preferences.domain

        do {
            try ReynardMigrationTransaction(
                directories: fixture.directories,
                preferences: fixture.preferences,
                fileSystem: TestMigrationFileSystem(corruptAfterStaging: true)
            ).apply(fixture.validatedBackup())
            preconditionFailure("Corrupt staged data must be rejected")
        } catch let error as ReynardDataTransferError {
            precondition(error == .stagingFailure)
        }

        let restoredFiles = try snapshot(fixture.liveRoots)
        precondition(restoredFiles == originalFiles)
        precondition(NSDictionary(dictionary: fixture.preferences.domain).isEqual(to: originalPreferences))
    }

    private final class Fixture {
        let root: URL
        let directories: ReynardDirectories
        let preferences = TestPreferencesStore(domain: ["state": "old", "count": 7])
        let backupURL: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "reynard-transaction-\(UUID().uuidString)",
                isDirectory: true
            )
            directories = ReynardDirectories.make(
                applicationSupport: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
                caches: root.appendingPathComponent("Caches", isDirectory: true),
                documents: root.appendingPathComponent("Documents", isDirectory: true),
                temporary: root.appendingPathComponent("Temporary", isDirectory: true)
            )
            try Self.write("old-data", to: directories.appData.appendingPathComponent("old.json"))
            try Self.write("old-profile", to: directories.applicationSupport.appendingPathComponent(".mozilla/profile.txt"))
            try Self.write("regenerated", to: directories.ddi.appendingPathComponent("Image.dmg"))
            try Self.write("old-download", to: directories.downloads.appendingPathComponent("old.txt"))

            let backupDirectories = ReynardDirectories.make(
                applicationSupport: root.appendingPathComponent("BackupSource/ApplicationSupport", isDirectory: true),
                caches: root.appendingPathComponent("BackupSource/Caches", isDirectory: true),
                documents: root.appendingPathComponent("BackupSource/Documents", isDirectory: true),
                temporary: root.appendingPathComponent("BackupSource/Temporary", isDirectory: true)
            )
            try Self.write("new-data", to: backupDirectories.appData.appendingPathComponent("new.json"))
            try Self.write("new-profile", to: backupDirectories.applicationSupport.appendingPathComponent(".mozilla/profile.txt"))
            try Self.write("new-download", to: backupDirectories.downloads.appendingPathComponent("new.txt"))
            backupURL = try ReynardBackupExporter(
                directories: backupDirectories,
                metadata: .init(
                    version: "0.7.0",
                    build: "abcdef0",
                    bundleIdentifier: "com.minh-ton.Reynard"
                ),
                preferences: { ["state": "new", "count": 9] }
            ).export()
        }

        var liveRoots: [String: URL] {
            [
                "ApplicationSupport": directories.applicationSupport,
                "Downloads": directories.downloads,
            ]
        }

        func validatedBackup() throws -> ValidatedReynardBackup {
            try ReynardBackupValidator().validate(at: backupURL, availableCapacity: UInt64.max)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        private static func write(_ value: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
    }

    private final class TestPreferencesStore: ReynardPreferencesStore {
        var domain: [String: Any]

        init(domain: [String: Any]) {
            self.domain = domain
        }

        func persistentDomain() -> [String: Any] {
            domain
        }

        func replacePersistentDomain(with domain: [String: Any]) throws {
            self.domain = domain
        }

        func removePersistentDomain() throws {
            domain.removeAll()
        }
    }

    private final class TestMigrationFileSystem: ReynardMigrationFileSystem {
        let failingAt: ReynardMigrationBoundary?
        let failRollbackRestore: Bool
        let corruptAfterStaging: Bool
        private let base = DefaultReynardMigrationFileSystem()
        private var copiedDestination: URL?

        init(
            failingAt: ReynardMigrationBoundary? = nil,
            failRollbackRestore: Bool = false,
            corruptAfterStaging: Bool = false
        ) {
            self.failingAt = failingAt
            self.failRollbackRestore = failRollbackRestore
            self.corruptAfterStaging = corruptAfterStaging
        }

        func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
        func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
        func isRegularFile(at url: URL) -> Bool { base.isRegularFile(at: url) }
        func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
        func copyItem(at source: URL, to destination: URL) throws {
            try base.copyItem(at: source, to: destination)
            copiedDestination = destination
        }
        func moveItem(at source: URL, to destination: URL) throws {
            if failRollbackRestore,
               source.path.contains("/rollback/ApplicationSupport") {
                throw InjectedFailure()
            }
            try base.moveItem(at: source, to: destination)
        }
        func removeItem(at url: URL) throws { try base.removeItem(at: url) }
        func removeDirectoryIfEmpty(at url: URL) throws {
            try base.removeDirectoryIfEmpty(at: url)
        }
        func contentsOfDirectory(at url: URL) throws -> [URL] {
            try base.contentsOfDirectory(at: url)
        }
        func readData(at url: URL) throws -> Data { try base.readData(at: url) }
        func writeData(_ data: Data, to url: URL) throws { try base.writeData(data, to: url) }

        func checkpoint(_ boundary: ReynardMigrationBoundary) throws {
            if corruptAfterStaging,
               boundary == .afterStaging,
               let copiedDestination {
                let preferences = copiedDestination.appendingPathComponent("preferences.plist")
                var data = try base.readData(at: preferences)
                data.append(0)
                try base.writeData(data, to: preferences)
            }
            if boundary == failingAt {
                throw InjectedFailure()
            }
        }
    }

    private struct InjectedFailure: Error {}

    private static func snapshot(_ roots: [String: URL]) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for (label, root) in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let relative = String(url.path.dropFirst(root.path.count + 1))
                result["\(label)/\(relative)"] = try Data(contentsOf: url)
            }
        }
        return result
    }

}
