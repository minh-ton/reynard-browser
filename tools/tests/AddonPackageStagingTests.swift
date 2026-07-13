import Foundation

@main
enum AddonPackageStagingTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reynard-addon-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.xpi")
        try Data("addon".utf8).write(to: source)
        let staging = root.appendingPathComponent("staging", isDirectory: true)

        let staged = try AddonPackageStaging.stage(
            packageURL: source,
            directoryURL: staging
        )
        precondition(FileManager.default.fileExists(atPath: staged.path))
        AddonPackageStaging.remove(staged)
        precondition(!FileManager.default.fileExists(atPath: staged.path))

        let stale = try AddonPackageStaging.stage(
            packageURL: source,
            directoryURL: staging
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)],
            ofItemAtPath: stale.path
        )
        AddonPackageStaging.removeStaleFiles(directoryURL: staging)
        precondition(!FileManager.default.fileExists(atPath: stale.path))
        print("AddonPackageStagingTests passed")
    }
}
