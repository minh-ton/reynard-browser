//
//  ReynardPendingImportPreflight.swift
//  Reynard
//

import Darwin
import Foundation

struct ReynardPendingImportPreflight {
    func validate(at packageURL: URL) throws -> ReynardBackupManifest {
        let package = packageURL.standardizedFileURL
        guard package.pathExtension.lowercased() == "reynardbackup" else {
            throw ReynardDataTransferError.invalidManifest
        }

        let packageInformation = try fileInformation(at: package)
        guard packageInformation.st_mode & S_IFMT == S_IFDIR else {
            throw ReynardDataTransferError.unsupportedFileType
        }

        let manifestURL = package.appendingPathComponent("manifest.json", isDirectory: false)
        let manifestSize: UInt64
        do {
            manifestSize = try ReynardFileHasher.regularFileSize(at: manifestURL)
        } catch {
            throw ReynardDataTransferError.invalidManifest
        }
        guard manifestSize <= ReynardBackupValidator.maximumManifestSize else {
            throw ReynardDataTransferError.invalidManifest
        }

        let manifest: ReynardBackupManifest
        do {
            manifest = try ReynardBackupManifest.decode(Data(contentsOf: manifestURL))
        } catch {
            throw ReynardDataTransferError.invalidManifest
        }
        guard manifest.formatVersion == ReynardBackupManifest.currentFormatVersion else {
            throw ReynardDataTransferError.unsupportedVersion
        }
        guard manifest.sourceBundleIdentifier == "com.minh-ton.Reynard",
              !manifest.reynardVersion.isEmpty,
              !manifest.reynardBuild.isEmpty,
              manifest.fileCount == manifest.files.count,
              manifest.fileCount > 0,
              manifest.fileCount <= ReynardBackupValidator.maximumFileCount,
              manifest.totalSize <= ReynardBackupValidator.maximumTotalSize else {
            throw ReynardDataTransferError.invalidManifest
        }

        var paths = Set<String>()
        var totalSize: UInt64 = 0
        for file in manifest.files {
            guard paths.insert(file.relativePath).inserted,
                  file.size <= ReynardBackupValidator.maximumFileSize,
                  (file.relativePath != "preferences.plist" ||
                    file.size <= ReynardBackupValidator.maximumPreferencesSize) else {
                throw ReynardDataTransferError.invalidManifest
            }
            let (newTotal, overflow) = totalSize.addingReportingOverflow(file.size)
            guard !overflow else {
                throw ReynardDataTransferError.invalidManifest
            }
            totalSize = newTotal
        }
        guard paths.contains("preferences.plist"),
              totalSize == manifest.totalSize else {
            throw ReynardDataTransferError.invalidManifest
        }
        return manifest
    }

    private func fileInformation(at url: URL) throws -> stat {
        var information = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return -1 }
            return lstat(representation, &information)
        }
        guard result == 0 else {
            throw ReynardDataTransferError.invalidManifest
        }
        return information
    }
}
