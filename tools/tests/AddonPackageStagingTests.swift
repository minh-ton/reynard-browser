import Foundation

@main
enum AddonPackageStagingTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reynard-addon-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.xpi")
        try Data("addon".utf8).write(to: source)
        let staging = root.appendingPathComponent("staging", isDirectory: true)

        let service = AddonPackageStagingService(
            directoryURL: staging,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let staged = try await service.stage(packageURL: source)
        precondition(FileManager.default.fileExists(atPath: staged.path))
        try await service.remove(staged)
        precondition(!FileManager.default.fileExists(atPath: staged.path))

        let stale = try await service.stage(packageURL: source)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000 - 2 * 24 * 60 * 60)],
            ofItemAtPath: stale.path
        )
        try await service.removeStaleFiles()
        precondition(!FileManager.default.fileExists(atPath: stale.path))

        let unsupported = root.appendingPathComponent("source.txt")
        try Data("addon".utf8).write(to: unsupported)
        do {
            _ = try await service.stage(packageURL: unsupported)
            preconditionFailure("Unsupported packages must be rejected")
        } catch let error as AddonPackageStagingService.StagingError {
            precondition(error == .unsupportedPackageType)
        }

        do {
            try await service.remove(root.appendingPathComponent("outside.xpi"))
            preconditionFailure("Cleanup must remain inside the staging directory")
        } catch let error as AddonPackageStagingService.StagingError {
            precondition(error == .invalidPackageURL)
        }
        print("AddonPackageStagingTests passed")
    }
}
