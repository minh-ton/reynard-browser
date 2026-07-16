import Foundation

@main
struct ReynardBackupManifestTests {
    static func main() throws {
        try testManifestRoundTripIsStable()
        try testFileHasherStreamsRegularFiles()
        try testExporterCreatesACompleteDocumentPackage()
        try testExporterDoesNotFollowSourceRootLinks()
        try testExporterRemovesPartialPackageAfterFailure()
        print("ReynardBackupManifestTests passed")
    }

    private static func testManifestRoundTripIsStable() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let files = [
            ReynardBackupFile(relativePath: "payload/Downloads/z.pdf", size: 3, sha256: "03"),
            ReynardBackupFile(relativePath: "payload/ApplicationSupport/AppData/a.json", size: 2, sha256: "02"),
        ]
        let manifest = ReynardBackupManifest(
            reynardVersion: "0.7.0",
            reynardBuild: "abcdef0",
            createdAt: createdAt,
            sourceBundleIdentifier: "com.minh-ton.Reynard",
            files: files
        )

        precondition(manifest.formatVersion == 1)
        precondition(manifest.fileCount == 2)
        precondition(manifest.totalSize == 5)
        precondition(manifest.files.map(\.relativePath) == [
            "payload/ApplicationSupport/AppData/a.json",
            "payload/Downloads/z.pdf",
        ])

        let firstEncoding = try manifest.encoded()
        let secondEncoding = try manifest.encoded()
        precondition(firstEncoding == secondEncoding)
        let decodedManifest = try ReynardBackupManifest.decode(firstEncoding)
        precondition(decodedManifest == manifest)

        let json = try JSONSerialization.jsonObject(with: firstEncoding) as? [String: Any]
        precondition(json?["formatVersion"] as? Int == 1)
        precondition(json?["createdAt"] as? String == "2025-06-15T15:06:40Z")
    }

    private static func testFileHasherStreamsRegularFiles() throws {
        let root = temporaryRoot(named: "hasher")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("value.txt", isDirectory: false)
        try Data("abc".utf8).write(to: file)
        let hash = try ReynardFileHasher.sha256(of: file)
        precondition(hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        do {
            _ = try ReynardFileHasher.sha256(of: root)
            preconditionFailure("Directories must not be hashed as files")
        } catch {}

        let link = root.appendingPathComponent("value-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        do {
            _ = try ReynardFileHasher.sha256(of: link)
            preconditionFailure("Symbolic links must not be hashed")
        } catch {}

        let hardLink = root.appendingPathComponent("value-hard-link", isDirectory: false)
        try FileManager.default.linkItem(at: file, to: hardLink)
        do {
            _ = try ReynardFileHasher.sha256(of: hardLink)
            preconditionFailure("Hard links must not be hashed")
        } catch {}
    }

    private static func testExporterCreatesACompleteDocumentPackage() throws {
        let root = temporaryRoot(named: "exporter")
        defer { try? FileManager.default.removeItem(at: root) }

        let directories = ReynardDirectories.make(
            applicationSupport: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
            caches: root.appendingPathComponent("Caches", isDirectory: true),
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            temporary: root.appendingPathComponent("Temporary", isDirectory: true)
        )

        let mozillaFile = directories.applicationSupport
            .appendingPathComponent(".mozilla/profiles.ini", isDirectory: false)
        let historyFile = directories.appData
            .appendingPathComponent("History/items.json", isDirectory: false)
        let ddiFile = directories.ddi.appendingPathComponent("Image.dmg", isDirectory: false)
        let cacheFile = directories.caches.appendingPathComponent("mozilla/cache2/entry", isDirectory: false)
        let downloadFile = directories.downloads.appendingPathComponent("example.pdf", isDirectory: false)

        try write("profile", to: mozillaFile)
        try write("history", to: historyFile)
        try write("ddi", to: ddiFile)
        try write("cache", to: cacheFile)
        try write("download", to: downloadFile)
        let hardLinkSource = directories.appData.appendingPathComponent("hard-link-source", isDirectory: false)
        let hardLinkCopy = directories.appData.appendingPathComponent("hard-link-copy", isDirectory: false)
        try write("linked", to: hardLinkSource)
        try FileManager.default.linkItem(at: hardLinkSource, to: hardLinkCopy)
        try FileManager.default.createSymbolicLink(
            at: directories.appData.appendingPathComponent("history-link", isDirectory: false),
            withDestinationURL: historyFile
        )

        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let exporter = ReynardBackupExporter(
            directories: directories,
            metadata: ReynardBackupExporter.Metadata(
                version: "0.7.0",
                build: "abcdef0",
                bundleIdentifier: "com.minh-ton.Reynard"
            ),
            preferences: {
                [
                    "enabled": true,
                    "createdAt": createdAt,
                    "payload": Data([0x01, 0x02, 0x03]),
                ]
            },
            now: { createdAt },
            identifier: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )

        let package = try exporter.export()
        precondition(package.pathExtension == "reynardbackup")
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path))
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("preferences.plist").path))
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/.mozilla/profiles.ini").path))
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/AppData/History/items.json").path))
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/Downloads/example.pdf").path))
        precondition(!FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/DDI/Image.dmg").path))
        precondition(!FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/Caches/mozilla/cache2/entry").path))
        precondition(!FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/AppData/history-link").path))
        precondition(!FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/AppData/hard-link-source").path))
        precondition(!FileManager.default.fileExists(atPath: package.appendingPathComponent("payload/ApplicationSupport/AppData/hard-link-copy").path))

        let manifestData = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let manifest = try ReynardBackupManifest.decode(manifestData)
        precondition(manifest.reynardVersion == "0.7.0")
        precondition(manifest.reynardBuild == "abcdef0")
        precondition(manifest.createdAt == createdAt)
        precondition(manifest.sourceBundleIdentifier == "com.minh-ton.Reynard")
        precondition(manifest.fileCount == 4)
        precondition(manifest.files.map(\.relativePath) == [
            "payload/ApplicationSupport/.mozilla/profiles.ini",
            "payload/ApplicationSupport/AppData/History/items.json",
            "payload/Downloads/example.pdf",
            "preferences.plist",
        ])

        for file in manifest.files {
            let exportedFile = package.appendingPathComponent(file.relativePath, isDirectory: false)
            let values = try exportedFile.resourceValues(forKeys: [.fileSizeKey])
            precondition(UInt64(values.fileSize ?? -1) == file.size)
            let hash = try ReynardFileHasher.sha256(of: exportedFile)
            precondition(hash == file.sha256)
        }

        let preferencesData = try Data(contentsOf: package.appendingPathComponent("preferences.plist"))
        let preferences = try PropertyListSerialization.propertyList(from: preferencesData, format: nil) as? [String: Any]
        precondition(preferences?["enabled"] as? Bool == true)
        precondition(preferences?["createdAt"] as? Date == createdAt)
        precondition(preferences?["payload"] as? Data == Data([0x01, 0x02, 0x03]))
    }

    private static func testExporterDoesNotFollowSourceRootLinks() throws {
        let root = temporaryRoot(named: "root-link")
        defer { try? FileManager.default.removeItem(at: root) }

        let directories = ReynardDirectories.make(
            applicationSupport: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
            caches: root.appendingPathComponent("Caches", isDirectory: true),
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            temporary: root.appendingPathComponent("Temporary", isDirectory: true)
        )
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try write("secret", to: outside.appendingPathComponent("secret.txt", isDirectory: false))
        try FileManager.default.createDirectory(
            at: directories.applicationSupport,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: directories.applicationSupport.appendingPathComponent(".mozilla", isDirectory: true),
            withDestinationURL: outside
        )

        let exporter = ReynardBackupExporter(
            directories: directories,
            metadata: ReynardBackupExporter.Metadata(
                version: "0.7.0",
                build: "abcdef0",
                bundleIdentifier: "com.minh-ton.Reynard"
            ),
            preferences: { [:] },
            now: { Date(timeIntervalSince1970: 1_750_000_000.5) },
            identifier: { UUID(uuidString: "00000000-0000-0000-0000-000000000002")! }
        )
        let package = try exporter.export()
        precondition(!FileManager.default.fileExists(
            atPath: package.appendingPathComponent(
                "payload/ApplicationSupport/.mozilla/secret.txt",
                isDirectory: false
            ).path
        ))

        let manifest = try ReynardBackupManifest.decode(
            Data(contentsOf: package.appendingPathComponent("manifest.json", isDirectory: false))
        )
        precondition(manifest.createdAt == Date(timeIntervalSince1970: 1_750_000_000))
        precondition(manifest.files.map(\.relativePath) == ["preferences.plist"])
    }

    private static func testExporterRemovesPartialPackageAfterFailure() throws {
        let root = temporaryRoot(named: "failed-export")
        defer { try? FileManager.default.removeItem(at: root) }

        let directories = ReynardDirectories.make(
            applicationSupport: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
            caches: root.appendingPathComponent("Caches", isDirectory: true),
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            temporary: root.appendingPathComponent("Temporary", isDirectory: true)
        )
        let exportIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let exporter = ReynardBackupExporter(
            directories: directories,
            metadata: ReynardBackupExporter.Metadata(
                version: "0.7.0",
                build: "abcdef0",
                bundleIdentifier: "com.minh-ton.Reynard"
            ),
            preferences: { ["unsupported": URL(string: "https://example.com")!] },
            identifier: { exportIdentifier }
        )

        do {
            _ = try exporter.export()
            preconditionFailure("Invalid preferences must fail the export")
        } catch {}

        let partialPackage = directories.temporary
            .appendingPathComponent("DataTransfer/Exports", isDirectory: true)
            .appendingPathComponent("Reynard-\(exportIdentifier.uuidString)", isDirectory: true)
            .appendingPathExtension("reynardbackup")
        precondition(!FileManager.default.fileExists(atPath: partialPackage.path))
    }

    private static func temporaryRoot(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "reynard-backup-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }
}
