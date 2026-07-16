import Foundation

@main
struct ReynardPendingImportPreflightTests {
    static func main() throws {
        try testValidPackagePasses()
        try testUnsupportedVersionAndSourceAreRejected()
        try testMetadataSizeLimitsAreEnforced()
        print("ReynardPendingImportPreflightTests passed")
    }

    private static func testValidPackagePasses() throws {
        let root = try makePackage()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try ReynardPendingImportPreflight().validate(at: root)
        precondition(manifest.formatVersion == 1)
        precondition(manifest.sourceBundleIdentifier == "com.minh-ton.Reynard")
    }

    private static func testUnsupportedVersionAndSourceAreRejected() throws {
        let versionRoot = try makePackage { $0["formatVersion"] = 2 }
        defer { try? FileManager.default.removeItem(at: versionRoot) }
        expect(.unsupportedVersion) {
            _ = try ReynardPendingImportPreflight().validate(at: versionRoot)
        }

        let sourceRoot = try makePackage { $0["sourceBundleIdentifier"] = "example.invalid" }
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        expect(.invalidManifest) {
            _ = try ReynardPendingImportPreflight().validate(at: sourceRoot)
        }
    }

    private static func testMetadataSizeLimitsAreEnforced() throws {
        let manifestRoot = try makePackage()
        defer { try? FileManager.default.removeItem(at: manifestRoot) }
        let manifestURL = manifestRoot.appendingPathComponent("manifest.json")
        let manifestHandle = try FileHandle(forWritingTo: manifestURL)
        try manifestHandle.truncate(
            atOffset: ReynardBackupValidator.maximumManifestSize + 1
        )
        try manifestHandle.close()
        expect(.invalidManifest) {
            _ = try ReynardPendingImportPreflight().validate(at: manifestRoot)
        }

        let preferencesRoot = try makePackage {
            let size = ReynardBackupValidator.maximumPreferencesSize + 1
            $0["files"] = [[
                "relativePath": "preferences.plist",
                "size": size,
                "sha256": String(repeating: "0", count: 64),
            ]]
            $0["totalSize"] = size
        }
        defer { try? FileManager.default.removeItem(at: preferencesRoot) }
        expect(.invalidManifest) {
            _ = try ReynardPendingImportPreflight().validate(at: preferencesRoot)
        }
    }

    private static func makePackage(
        mutate: (inout [String: Any]) -> Void = { _ in }
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reynard-preflight-\(UUID().uuidString).reynardbackup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var manifest: [String: Any] = [
            "formatVersion": 1,
            "reynardVersion": "0.7.0",
            "reynardBuild": "abcdef0",
            "createdAt": "2025-06-15T15:06:40Z",
            "sourceBundleIdentifier": "com.minh-ton.Reynard",
            "fileCount": 1,
            "totalSize": 0,
            "files": [[
                "relativePath": "preferences.plist",
                "size": 0,
                "sha256": String(repeating: "0", count: 64),
            ]],
        ]
        mutate(&manifest)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    private static func expect(
        _ expected: ReynardDataTransferError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as ReynardDataTransferError {
            precondition(error == expected)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
