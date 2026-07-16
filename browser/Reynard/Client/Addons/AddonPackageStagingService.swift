//
//  AddonPackageStagingService.swift
//  Reynard
//

import Foundation
import os

enum AddonPackageStagingLog {
    private static let log = OSLog(subsystem: "com.minh-ton.Reynard", category: "AddonStaging")

    static func error(_ operation: String, error: Error) {
        os_log(
            "%{public}@: %{public}@",
            log: log,
            type: .error,
            operation,
            error.localizedDescription
        )
    }
}

final class AddonPackageStagingService: @unchecked Sendable {
    enum StagingError: Error, Equatable {
        case invalidPackageURL
        case unsupportedPackageType
    }

    static let shared = AddonPackageStagingService()
    nonisolated static let maximumStagingAge: TimeInterval = 24 * 60 * 60

    private let makeFileManager: @Sendable () -> FileManager
    private let directoryURL: URL
    private let now: @Sendable () -> Date

    init(
        makeFileManager: @escaping @Sendable () -> FileManager = { .default },
        directoryURL: URL? = nil,
        directories: ReynardDirectories = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.makeFileManager = makeFileManager
        self.directoryURL = directoryURL ?? directories.temporary
            .appendingPathComponent("Addons", isDirectory: true)
        self.now = now
    }

    func stage(packageURL: URL) async throws -> URL {
        let makeFileManager = makeFileManager
        let directoryURL = directoryURL
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = makeFileManager()
            try Task.checkCancellation()
            guard packageURL.isFileURL else {
                throw StagingError.invalidPackageURL
            }
            let packageExtension = packageURL.pathExtension.lowercased()
            guard packageExtension == "xpi" || packageExtension == "zip" else {
                throw StagingError.unsupportedPackageType
            }

            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let identifier = UUID().uuidString
            let temporaryURL = directoryURL
                .appendingPathComponent(identifier, isDirectory: false)
                .appendingPathExtension("partial")
            let destinationURL = directoryURL
                .appendingPathComponent(identifier, isDirectory: false)
                .appendingPathExtension("xpi")
            let hasSecurityScopedAccess = packageURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScopedAccess {
                    packageURL.stopAccessingSecurityScopedResource()
                }
                if fileManager.fileExists(atPath: temporaryURL.path) {
                    try? fileManager.removeItem(at: temporaryURL)
                }
            }

            try fileManager.copyItem(at: packageURL, to: temporaryURL)
            try Task.checkCancellation()
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        }.value
    }

    func remove(_ stagedURL: URL) async throws {
        let makeFileManager = makeFileManager
        let directoryURL = directoryURL.standardizedFileURL
        try await Task.detached(priority: .utility) {
            let fileManager = makeFileManager()
            let candidateURL = stagedURL.standardizedFileURL
            guard candidateURL.deletingLastPathComponent() == directoryURL else {
                throw StagingError.invalidPackageURL
            }
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                return
            }
            try fileManager.removeItem(at: candidateURL)
        }.value
    }

    func removeStaleFiles() async throws {
        let makeFileManager = makeFileManager
        let directoryURL = directoryURL
        let now = now()
        try await Task.detached(priority: .utility) {
            let fileManager = makeFileManager()
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return
            }
            let files = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for fileURL in files {
                try Task.checkCancellation()
                let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modifiedAt = values.contentModificationDate,
                      now.timeIntervalSince(modifiedAt) >= Self.maximumStagingAge else {
                    continue
                }
                try fileManager.removeItem(at: fileURL)
            }
        }.value
    }
}
