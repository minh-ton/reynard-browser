//
//  AddonPackageStaging.swift
//  Reynard
//

import Foundation

enum AddonPackageStaging {
    static let maximumStagingAge: TimeInterval = 24 * 60 * 60

    static func stage(
        packageURL: URL,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) throws -> URL {
        let stagingDirectoryURL = directoryURL ?? defaultDirectoryURL(
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: stagingDirectoryURL,
            withIntermediateDirectories: true
        )
        let destinationURL = stagingDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("xpi")

        let hasSecurityScopedAccess = packageURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }
        try fileManager.copyItem(at: packageURL, to: destinationURL)
        return destinationURL
    }

    static func remove(_ stagedURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: stagedURL)
    }

    static func removeStaleFiles(
        now: Date = Date(),
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        let stagingDirectoryURL = directoryURL ?? defaultDirectoryURL(
            fileManager: fileManager
        )
        guard let files = try? fileManager.contentsOfDirectory(
            at: stagingDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for fileURL in files {
            let values = try? fileURL.resourceValues(forKeys: [
                .contentModificationDateKey,
            ])
            guard let modifiedAt = values?.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) >= maximumStagingAge else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        return fileManager.temporaryDirectory.appendingPathComponent(
            "Addons",
            isDirectory: true
        )
    }
}
