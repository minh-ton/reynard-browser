import Darwin
import Foundation

@main
struct ReynardBackupValidatorTests {
    private static let validHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private static let zeroHash = String(repeating: "0", count: 64)

    static func main() throws {
        try testValidBackupReturnsSortedFiles()
        try testUnsupportedVersionsAreRejected()
        try testUnsafeAndDuplicatePathsAreRejected()
        try testUnsupportedFileTypesAreRejected()
        try testMissingAndExtraFilesAreRejected()
        try testSizeAndChecksumMismatchesAreRejected()
        try testManifestLimitsAreEnforced()
        try testMetadataSizeLimitsAreEnforced()
        try testAvailableSpaceIsEnforced()
        try testUnexpectedSourceBundleIsRejected()
        print("ReynardBackupValidatorTests passed")
    }

    private static func testValidBackupReturnsSortedFiles() throws {
        let root = try makeBackup(files: [
            "payload/Downloads/z.txt": Data("abc".utf8),
            "preferences.plist": try preferencesData(["enabled": true]),
            "payload/ApplicationSupport/AppData/a.json": Data("abc".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let validated = try ReynardBackupValidator().validate(at: root, availableCapacity: UInt64.max)
        precondition(validated.rootURL == root.standardizedFileURL)
        precondition(validated.files.map(\.relativePath) == [
            "payload/ApplicationSupport/AppData/a.json",
            "payload/Downloads/z.txt",
            "preferences.plist",
        ])
    }

    private static func testUnsupportedVersionsAreRejected() throws {
        for version in [0, 2] {
            let root = try makeBackup(files: ["preferences.plist": try preferencesData([:])]) {
                $0["formatVersion"] = version
            }
            defer { try? FileManager.default.removeItem(at: root) }
            expect(.unsupportedVersion) {
                _ = try ReynardBackupValidator().validate(at: root, availableCapacity: UInt64.max)
            }
        }
    }

    private static func testUnsafeAndDuplicatePathsAreRejected() throws {
        for path in ["/var/mobile/data", "payload/Downloads/../secret", "payload//Downloads/file"] {
            let root = try makeBackup(files: [:]) {
                $0["files"] = [entry(path: path, size: 0, hash: zeroHash)]
                $0["fileCount"] = 1
            }
            defer { try? FileManager.default.removeItem(at: root) }
            expect(.unsafePath) {
                _ = try ReynardBackupValidator().validate(at: root, availableCapacity: UInt64.max)
            }
        }

        let duplicateRoot = try makeBackup(files: [:]) {
            $0["files"] = [
                entry(path: "preferences.plist", size: 0, hash: zeroHash),
                entry(path: "preferences.plist", size: 0, hash: zeroHash),
            ]
            $0["fileCount"] = 2
        }
        defer { try? FileManager.default.removeItem(at: duplicateRoot) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(at: duplicateRoot, availableCapacity: UInt64.max)
        }
    }

    private static func testUnsupportedFileTypesAreRejected() throws {
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFLNK), linkCount: 1))
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFIFO), linkCount: 1))
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFSOCK), linkCount: 1))
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFCHR), linkCount: 1))
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFBLK), linkCount: 1))
        precondition(!ReynardBackupValidator.isSupportedFile(mode: mode_t(S_IFREG), linkCount: 2))

        let symlinkRoot = try makeBackup(files: ["preferences.plist": try preferencesData([:])])
        defer { try? FileManager.default.removeItem(at: symlinkRoot) }
        try FileManager.default.createSymbolicLink(
            at: symlinkRoot.appendingPathComponent("link"),
            withDestinationURL: symlinkRoot.appendingPathComponent("preferences.plist")
        )
        expect(.unsupportedFileType) {
            _ = try ReynardBackupValidator().validate(at: symlinkRoot, availableCapacity: UInt64.max)
        }

        let hardLinkRoot = try makeBackup(files: [:])
        defer { try? FileManager.default.removeItem(at: hardLinkRoot) }
        let first = hardLinkRoot.appendingPathComponent("payload/Downloads/first")
        let second = hardLinkRoot.appendingPathComponent("payload/Downloads/second")
        try write(Data("abc".utf8), to: first)
        try FileManager.default.linkItem(at: first, to: second)
        let preferences = hardLinkRoot.appendingPathComponent("preferences.plist")
        let preferencesContents = try preferencesData([:])
        try write(preferencesContents, to: preferences)
        try replaceManifest(at: hardLinkRoot, files: [
            entry(path: "payload/Downloads/first", size: 3, hash: validHash),
            entry(path: "payload/Downloads/second", size: 3, hash: validHash),
            entry(
                path: "preferences.plist",
                size: UInt64(preferencesContents.count),
                hash: try ReynardFileHasher.sha256(of: preferences)
            ),
        ])
        expect(.unsupportedFileType) {
            _ = try ReynardBackupValidator().validate(at: hardLinkRoot, availableCapacity: UInt64.max)
        }

        let fifoRoot = try makeBackup(files: ["preferences.plist": try preferencesData([:])])
        defer { try? FileManager.default.removeItem(at: fifoRoot) }
        let fifo = fifoRoot.appendingPathComponent("pipe")
        precondition(mkfifo(fifo.path, 0o600) == 0)
        expect(.unsupportedFileType) {
            _ = try ReynardBackupValidator().validate(at: fifoRoot, availableCapacity: UInt64.max)
        }
    }

    private static func testMissingAndExtraFilesAreRejected() throws {
        let missingRoot = try makeBackup(files: [:]) {
            $0["files"] = [entry(path: "preferences.plist", size: 0, hash: zeroHash)]
            $0["fileCount"] = 1
        }
        defer { try? FileManager.default.removeItem(at: missingRoot) }
        expect(.missingFile) {
            _ = try ReynardBackupValidator().validate(at: missingRoot, availableCapacity: UInt64.max)
        }

        let extraRoot = try makeBackup(files: ["preferences.plist": try preferencesData([:])])
        defer { try? FileManager.default.removeItem(at: extraRoot) }
        try write(Data("extra".utf8), to: extraRoot.appendingPathComponent("extra.txt"))
        expect(.extraFile) {
            _ = try ReynardBackupValidator().validate(at: extraRoot, availableCapacity: UInt64.max)
        }
    }

    private static func testSizeAndChecksumMismatchesAreRejected() throws {
        let sizeRoot = try makeBackup(files: ["preferences.plist": Data("abc".utf8)]) {
            var files = $0["files"] as! [[String: Any]]
            files[0]["size"] = 4
            $0["files"] = files
            $0["totalSize"] = 4
        }
        defer { try? FileManager.default.removeItem(at: sizeRoot) }
        expect(.sizeMismatch) {
            _ = try ReynardBackupValidator().validate(at: sizeRoot, availableCapacity: UInt64.max)
        }

        let hashRoot = try makeBackup(files: ["preferences.plist": Data("abc".utf8)]) {
            var files = $0["files"] as! [[String: Any]]
            files[0]["sha256"] = zeroHash
            $0["files"] = files
        }
        defer { try? FileManager.default.removeItem(at: hashRoot) }
        expect(.checksumMismatch) {
            _ = try ReynardBackupValidator().validate(at: hashRoot, availableCapacity: UInt64.max)
        }
    }

    private static func testManifestLimitsAreEnforced() throws {
        let countRoot = try makeBackup(files: [:]) {
            $0["fileCount"] = 250_001
        }
        defer { try? FileManager.default.removeItem(at: countRoot) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(at: countRoot, availableCapacity: UInt64.max)
        }

        let largeFileRoot = try makeBackup(files: [:]) {
            $0["files"] = [entry(
                path: "payload/Downloads/large",
                size: 2_147_483_649,
                hash: zeroHash
            )]
            $0["fileCount"] = 1
            $0["totalSize"] = 2_147_483_649
        }
        defer { try? FileManager.default.removeItem(at: largeFileRoot) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(at: largeFileRoot, availableCapacity: UInt64.max)
        }

        let totalRoot = try makeBackup(files: [:]) {
            let files = (0..<11).map {
                entry(
                    path: "payload/Downloads/file-\($0)",
                    size: 2_147_483_648,
                    hash: zeroHash
                )
            }
            $0["files"] = files
            $0["fileCount"] = files.count
            $0["totalSize"] = UInt64(23_622_320_128)
        }
        defer { try? FileManager.default.removeItem(at: totalRoot) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(at: totalRoot, availableCapacity: UInt64.max)
        }
    }

    private static func testMetadataSizeLimitsAreEnforced() throws {
        let manifestRoot = try makeBackup(files: [
            "preferences.plist": try preferencesData([:]),
        ])
        defer { try? FileManager.default.removeItem(at: manifestRoot) }
        let manifestURL = manifestRoot.appendingPathComponent("manifest.json")
        let manifestHandle = try FileHandle(forWritingTo: manifestURL)
        try manifestHandle.truncate(
            atOffset: ReynardBackupValidator.maximumManifestSize + 1
        )
        try manifestHandle.close()
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(
                at: manifestRoot,
                availableCapacity: UInt64.max
            )
        }

        let preferencesRoot = try makeBackup(files: [:]) {
            let size = ReynardBackupValidator.maximumPreferencesSize + 1
            $0["files"] = [entry(
                path: "preferences.plist",
                size: size,
                hash: zeroHash
            )]
            $0["fileCount"] = 1
            $0["totalSize"] = size
        }
        defer { try? FileManager.default.removeItem(at: preferencesRoot) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(
                at: preferencesRoot,
                availableCapacity: UInt64.max
            )
        }
    }

    private static func testAvailableSpaceIsEnforced() throws {
        let preferences = try preferencesData([:])
        let root = try makeBackup(files: ["preferences.plist": preferences])
        defer { try? FileManager.default.removeItem(at: root) }
        let required = UInt64(preferences.count * 2) + ReynardBackupValidator.stagingAllowance
        expect(.insufficientSpace) {
            _ = try ReynardBackupValidator().validate(at: root, availableCapacity: required - 1)
        }
        _ = try ReynardBackupValidator().validate(at: root, availableCapacity: required)
    }

    private static func testUnexpectedSourceBundleIsRejected() throws {
        let root = try makeBackup(files: ["preferences.plist": try preferencesData([:])]) {
            $0["sourceBundleIdentifier"] = "example.invalid"
        }
        defer { try? FileManager.default.removeItem(at: root) }
        expect(.invalidManifest) {
            _ = try ReynardBackupValidator().validate(at: root, availableCapacity: UInt64.max)
        }
    }

    private static func makeBackup(
        files: [String: Data],
        mutateManifest: (inout [String: Any]) -> Void = { _ in }
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reynard-validator-\(UUID().uuidString).reynardbackup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var entries: [[String: Any]] = []
        for path in files.keys.sorted() {
            let data = files[path]!
            try write(data, to: root.appendingPathComponent(path))
            entries.append(entry(
                path: path,
                size: UInt64(data.count),
                hash: try ReynardFileHasher.sha256(of: root.appendingPathComponent(path))
            ))
        }
        var manifest = manifestDictionary(files: entries)
        mutateManifest(&manifest)
        try writeManifest(manifest, at: root)
        return root
    }

    private static func replaceManifest(at root: URL, files: [[String: Any]]) throws {
        try writeManifest(manifestDictionary(files: files), at: root)
    }

    private static func manifestDictionary(files: [[String: Any]]) -> [String: Any] {
        let total = files.reduce(UInt64(0)) { partial, file in
            partial + (file["size"] as? UInt64 ?? UInt64(file["size"] as? Int ?? 0))
        }
        return [
            "formatVersion": 1,
            "reynardVersion": "0.7.0",
            "reynardBuild": "abcdef0",
            "createdAt": "2025-06-15T15:06:40Z",
            "sourceBundleIdentifier": "com.minh-ton.Reynard",
            "fileCount": files.count,
            "totalSize": total,
            "files": files,
        ]
    }

    private static func entry(path: String, size: UInt64, hash: String) -> [String: Any] {
        ["relativePath": path, "size": size, "sha256": hash]
    }

    private static func writeManifest(_ manifest: [String: Any], at root: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func preferencesData(_ preferences: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: preferences,
            format: .binary,
            options: 0
        )
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private static func expect(
        _ expected: ReynardDataTransferError,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as ReynardDataTransferError {
            precondition(error == expected, "Expected \(expected), received \(error)")
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
