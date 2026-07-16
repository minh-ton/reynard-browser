import Foundation

@main
struct ReynardMigrationRecoveryTests {
    private enum InterruptedState: CaseIterable {
        case prepared
        case applicationSupportBackedUp
        case bothRootsBackedUp
        case applicationSupportInstalled
        case bothRootsInstalled
        case preferencesInstalled
    }

    static func main() throws {
        try testEveryInterruptedStateRestoresOriginalData()
        try testRecoveryCanResumeAfterItsOwnInterruption()
        try testOriginallyMissingRootsAreRemoved()
        try testCorruptJournalIsPreserved()
        try testUnjournaledStagingIsRemoved()
        try testRecoveringOneOperationPreservesAnother()
        print("ReynardMigrationRecoveryTests passed")
    }

    private static func testEveryInterruptedStateRestoresOriginalData() throws {
        for state in InterruptedState.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let operation = try fixture.makeOperation(state: state)

            try ReynardMigrationRecovery(
                directories: fixture.directories,
                preferences: fixture.preferences
            ).recoverPendingTransactions()

            try fixture.assertOriginalState()
            precondition(!FileManager.default.fileExists(atPath: operation.path))
            precondition(!FileManager.default.fileExists(
                atPath: fixture.directories.migrationRecovery.path
            ))
        }
    }

    private static func testRecoveryCanResumeAfterItsOwnInterruption() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operation = try fixture.makeOperation(state: .bothRootsInstalled)
        let interruptedFileSystem = InterruptingMigrationFileSystem()

        do {
            try ReynardMigrationRecovery(
                directories: fixture.directories,
                preferences: fixture.preferences,
                fileSystem: interruptedFileSystem
            ).recoverPendingTransactions()
            preconditionFailure("Expected recovery interruption")
        } catch let error as ReynardDataTransferError {
            precondition(error == .rollbackFailure)
        }

        precondition(FileManager.default.fileExists(atPath: operation.path))
        try ReynardMigrationRecovery(
            directories: fixture.directories,
            preferences: fixture.preferences
        ).recoverPendingTransactions()
        try fixture.assertOriginalState()
        precondition(!FileManager.default.fileExists(atPath: operation.path))
    }

    private static func testOriginallyMissingRootsAreRemoved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.directories.applicationSupport)
        try FileManager.default.removeItem(at: fixture.directories.downloads)
        let operation = try fixture.makeOperation(
            state: .prepared,
            applicationSupportExisted: false,
            downloadsExisted: false
        )
        try Fixture.write("new-app-data", to: fixture.directories.appData.appendingPathComponent("new"))
        try Fixture.write("new-download", to: fixture.directories.downloads.appendingPathComponent("new"))
        fixture.preferences.domain = ["state": "new"]

        try ReynardMigrationRecovery(
            directories: fixture.directories,
            preferences: fixture.preferences
        ).recoverPendingTransactions()

        precondition(!FileManager.default.fileExists(atPath: fixture.directories.applicationSupport.path))
        precondition(!FileManager.default.fileExists(atPath: fixture.directories.downloads.path))
        precondition(fixture.preferences.domain["state"] as? String == "old")
        precondition(!FileManager.default.fileExists(atPath: operation.path))
    }

    private static func testCorruptJournalIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operation = fixture.operationURL()
        try Fixture.write("not-json", to: operation.appendingPathComponent("journal.json"))

        do {
            try ReynardMigrationRecovery(
                directories: fixture.directories,
                preferences: fixture.preferences
            ).recoverPendingTransactions()
            preconditionFailure("Expected corrupt journal failure")
        } catch let error as ReynardDataTransferError {
            precondition(error == .rollbackFailure)
        }
        precondition(FileManager.default.fileExists(atPath: operation.path))
    }

    private static func testUnjournaledStagingIsRemoved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operation = fixture.operationURL()
        try Fixture.write(
            "staged",
            to: operation.appendingPathComponent("staging/backup.reynardbackup/evidence")
        )

        try ReynardMigrationRecovery(
            directories: fixture.directories,
            preferences: fixture.preferences
        ).recoverPendingTransactions()

        precondition(!FileManager.default.fileExists(atPath: operation.path))
    }

    private static func testRecoveringOneOperationPreservesAnother() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operation = try fixture.makeOperation(state: .prepared)
        let unrelated = fixture.directories.migrationRecovery.appendingPathComponent(
            "unrelated",
            isDirectory: true
        )
        try Fixture.write("keep", to: unrelated.appendingPathComponent("evidence"))

        try ReynardMigrationRecovery(
            directories: fixture.directories,
            preferences: fixture.preferences
        ).recoverOperation(at: operation)

        precondition(!FileManager.default.fileExists(atPath: operation.path))
        precondition(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private final class Fixture {
        let root: URL
        let directories: ReynardDirectories
        let preferences = TestPreferencesStore(domain: ["state": "old", "count": 7])

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "reynard-recovery-\(UUID().uuidString)",
                isDirectory: true
            )
            directories = ReynardDirectories.make(
                applicationSupport: root.appendingPathComponent("Library/Application Support", isDirectory: true),
                caches: root.appendingPathComponent("Library/Caches", isDirectory: true),
                documents: root.appendingPathComponent("Documents", isDirectory: true),
                temporary: root.appendingPathComponent("Temporary", isDirectory: true)
            )
            try Self.write("old-app-data", to: directories.appData.appendingPathComponent("old"))
            try Self.write("old-download", to: directories.downloads.appendingPathComponent("old"))
        }

        func operationURL() -> URL {
            directories.migrationRecovery.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        }

        func makeOperation(
            state: InterruptedState,
            applicationSupportExisted: Bool = true,
            downloadsExisted: Bool = true
        ) throws -> URL {
            let operation = operationURL()
            let rollback = operation.appendingPathComponent("rollback", isDirectory: true)
            try Self.writePreferences(
                ["state": "old", "count": 7],
                to: rollback.appendingPathComponent("preferences.plist")
            )
            let journal = ReynardMigrationJournal(
                version: ReynardMigrationJournal.currentVersion,
                applicationSupportExisted: applicationSupportExisted,
                downloadsExisted: downloadsExisted
            )
            let journalData = try JSONEncoder().encode(journal)
            try journalData.write(
                to: operation.appendingPathComponent("journal.json"),
                options: .atomic
            )

            guard applicationSupportExisted, downloadsExisted else {
                return operation
            }
            switch state {
            case .prepared:
                break
            case .applicationSupportBackedUp:
                try moveApplicationSupportToRollback(operation)
            case .bothRootsBackedUp:
                try moveApplicationSupportToRollback(operation)
                try moveDownloadsToRollback(operation)
            case .applicationSupportInstalled:
                try moveApplicationSupportToRollback(operation)
                try moveDownloadsToRollback(operation)
                try Self.write("new-app-data", to: directories.appData.appendingPathComponent("new"))
            case .bothRootsInstalled:
                try moveApplicationSupportToRollback(operation)
                try moveDownloadsToRollback(operation)
                try Self.write("new-app-data", to: directories.appData.appendingPathComponent("new"))
                try Self.write("new-download", to: directories.downloads.appendingPathComponent("new"))
            case .preferencesInstalled:
                try moveApplicationSupportToRollback(operation)
                try moveDownloadsToRollback(operation)
                try Self.write("new-app-data", to: directories.appData.appendingPathComponent("new"))
                try Self.write("new-download", to: directories.downloads.appendingPathComponent("new"))
                preferences.domain = ["state": "new", "count": 9]
            }
            return operation
        }

        func assertOriginalState() throws {
            let appData = try Data(contentsOf: directories.appData.appendingPathComponent("old"))
            let download = try Data(contentsOf: directories.downloads.appendingPathComponent("old"))
            precondition(appData == Data("old-app-data".utf8))
            precondition(download == Data("old-download".utf8))
            precondition(NSDictionary(dictionary: preferences.domain).isEqual(to: [
                "state": "old",
                "count": 7,
            ]))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        private func moveApplicationSupportToRollback(_ operation: URL) throws {
            let destination = operation.appendingPathComponent(
                "rollback/ApplicationSupport",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: directories.applicationSupport, to: destination)
        }

        private func moveDownloadsToRollback(_ operation: URL) throws {
            let destination = operation.appendingPathComponent(
                "rollback/Downloads",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: directories.downloads, to: destination)
        }

        static func write(_ value: String, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(value.utf8).write(to: url)
        }

        private static func writePreferences(_ domain: [String: Any], to url: URL) throws {
            let data = try PropertyListSerialization.data(
                fromPropertyList: domain,
                format: .binary,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
    }

    private final class TestPreferencesStore: ReynardPreferencesStore {
        var domain: [String: Any]

        init(domain: [String: Any]) {
            self.domain = domain
        }

        func persistentDomain() -> [String: Any] { domain }
        func replacePersistentDomain(with domain: [String: Any]) throws { self.domain = domain }
        func removePersistentDomain() throws { domain.removeAll() }
    }

    private final class InterruptingMigrationFileSystem: ReynardMigrationFileSystem {
        private let base = DefaultReynardMigrationFileSystem()
        private var didInterrupt = false

        func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
        func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
        func isRegularFile(at url: URL) -> Bool { base.isRegularFile(at: url) }
        func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
        func copyItem(at source: URL, to destination: URL) throws {
            try base.copyItem(at: source, to: destination)
        }
        func moveItem(at source: URL, to destination: URL) throws {
            if !didInterrupt, source.path.hasSuffix("rollback/Downloads") {
                didInterrupt = true
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
        func checkpoint(_ boundary: ReynardMigrationBoundary) throws {}
    }

    private struct InjectedFailure: Error {}
}
