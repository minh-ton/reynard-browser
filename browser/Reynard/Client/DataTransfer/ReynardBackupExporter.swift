//
//  ReynardBackupExporter.swift
//  Reynard
//

import Foundation

struct ReynardBackupExporter {
    struct Metadata {
        let version: String
        let build: String
        let bundleIdentifier: String

        static var current: Metadata {
            Metadata(
                version: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "0.0.0",
                build: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion"
                ) as? String ?? "0",
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.minh-ton.Reynard"
            )
        }
    }

    enum ExportError: Error {
        case invalidMetadata
        case sourceEnumerationFailed
        case manifestVerificationFailed
    }

    private struct SourceRoot {
        let source: URL
        let destination: String
        let policyPath: String
    }

    private let directories: ReynardDirectories
    private let fileManager: FileManager
    private let policy: ReynardBackupContentPolicy
    private let metadata: Metadata
    private let preferences: () throws -> [String: Any]
    private let now: () -> Date
    private let identifier: () -> UUID

    init(
        directories: ReynardDirectories = .shared,
        fileManager: FileManager = .default,
        policy: ReynardBackupContentPolicy = ReynardBackupContentPolicy(),
        metadata: Metadata = .current,
        preferences: @escaping () throws -> [String: Any] = {
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                return [:]
            }
            return UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]
        },
        now: @escaping () -> Date = Date.init,
        identifier: @escaping () -> UUID = UUID.init
    ) {
        self.directories = directories
        self.fileManager = fileManager
        self.policy = policy
        self.metadata = metadata
        self.preferences = preferences
        self.now = now
        self.identifier = identifier
    }

    func export() throws -> URL {
        guard !metadata.version.isEmpty,
              !metadata.build.isEmpty,
              !metadata.bundleIdentifier.isEmpty else {
            throw ExportError.invalidMetadata
        }

        let exportsDirectory = directories.temporary
            .appendingPathComponent("DataTransfer", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let packageURL = exportsDirectory
            .appendingPathComponent("Reynard-\(identifier().uuidString)", isDirectory: true)
            .appendingPathExtension("reynardbackup")
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)

        do {
            var files: [ReynardBackupFile] = []
            for root in sourceRoots() {
                try copySourceRoot(root, to: packageURL, files: &files)
            }
            try writePreferences(to: packageURL, files: &files)

            let manifest = ReynardBackupManifest(
                reynardVersion: metadata.version,
                reynardBuild: metadata.build,
                createdAt: Date(
                    timeIntervalSince1970: floor(now().timeIntervalSince1970)
                ),
                sourceBundleIdentifier: metadata.bundleIdentifier,
                files: files
            )
            let manifestData = try manifest.encoded()
            let manifestURL = packageURL.appendingPathComponent("manifest.json", isDirectory: false)
            try manifestData.write(to: manifestURL, options: .atomic)

            guard try ReynardBackupManifest.decode(Data(contentsOf: manifestURL)) == manifest else {
                throw ExportError.manifestVerificationFailed
            }
            return packageURL
        } catch {
            try? fileManager.removeItem(at: packageURL)
            throw error
        }
    }

    private func sourceRoots() -> [SourceRoot] {
        [
            SourceRoot(
                source: directories.applicationSupport.appendingPathComponent(".mozilla", isDirectory: true),
                destination: "payload/ApplicationSupport/.mozilla",
                policyPath: "ApplicationSupport/.mozilla"
            ),
            SourceRoot(
                source: directories.appData,
                destination: "payload/ApplicationSupport/AppData",
                policyPath: "ApplicationSupport/AppData"
            ),
            SourceRoot(
                source: directories.downloads,
                destination: "payload/Downloads",
                policyPath: "Downloads"
            ),
        ]
    }

    private func copySourceRoot(
        _ root: SourceRoot,
        to packageURL: URL,
        files: inout [ReynardBackupFile]
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let rootValues = try root.source.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            return
        }

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root.source,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ExportError.sourceEnumerationFailed
        }

        let sourceComponents = root.source.standardizedFileURL.pathComponents
        while let sourceURL = enumerator.nextObject() as? URL {
            let standardizedSource = sourceURL.standardizedFileURL
            let components = standardizedSource.pathComponents
            guard components.starts(with: sourceComponents),
                  components.count > sourceComponents.count else {
                throw ExportError.sourceEnumerationFailed
            }

            let relativeComponents = components.dropFirst(sourceComponents.count)
            let relativePath = relativeComponents.joined(separator: "/")
            let policyPath = root.policyPath + "/" + relativePath
            let values = try standardizedSource.resourceValues(forKeys: Set(resourceKeys))

            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values.isDirectory == true {
                guard policy.includes(relativePath: policyPath + "/.directory") else {
                    enumerator.skipDescendants()
                    continue
                }
                let destination = packageURL.appendingPathComponent(
                    root.destination + "/" + relativePath,
                    isDirectory: true
                )
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }

            guard values.isRegularFile == true,
                  policy.includes(relativePath: policyPath),
                  (try? ReynardFileHasher.regularFileSize(at: standardizedSource)) != nil else {
                continue
            }

            let packageRelativePath = root.destination + "/" + relativePath
            let destination = packageURL.appendingPathComponent(packageRelativePath, isDirectory: false)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: standardizedSource, to: destination)
            files.append(try backupFile(for: destination, relativePath: packageRelativePath))
        }

        if enumerationError != nil {
            throw ExportError.sourceEnumerationFailed
        }
    }

    private func writePreferences(
        to packageURL: URL,
        files: inout [ReynardBackupFile]
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: preferences(),
            format: .binary,
            options: 0
        )
        let relativePath = "preferences.plist"
        let destination = packageURL.appendingPathComponent(relativePath, isDirectory: false)
        try data.write(to: destination, options: .atomic)
        files.append(try backupFile(for: destination, relativePath: relativePath))
    }

    private func backupFile(for url: URL, relativePath: String) throws -> ReynardBackupFile {
        ReynardBackupFile(
            relativePath: relativePath,
            size: try ReynardFileHasher.regularFileSize(at: url),
            sha256: try ReynardFileHasher.sha256(of: url)
        )
    }
}
