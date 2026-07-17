//
//  ReynardBackupValidator.swift
//  Reynard
//

import Darwin
import Foundation

struct ValidatedReynardBackup {
    let rootURL: URL
    let manifest: ReynardBackupManifest
    let files: [ReynardBackupFile]

    var preferencesURL: URL {
        rootURL.appendingPathComponent("preferences.plist", isDirectory: false)
    }
}

struct ReynardBackupValidator {
    static let maximumFileCount = 250_000
    static let maximumFileSize: UInt64 = 2_147_483_648
    static let maximumTotalSize: UInt64 = 21_474_836_480
    static let stagingAllowance: UInt64 = 268_435_456
    static let maximumManifestSize: UInt64 = 16 * 1024 * 1024
    static let maximumPreferencesSize: UInt64 = 16 * 1024 * 1024

    private let fileManager: FileManager
    private let contentPolicy: ReynardBackupContentPolicy
    private let expectedBundleIdentifier: String

    init(
        fileManager: FileManager = .default,
        contentPolicy: ReynardBackupContentPolicy = ReynardBackupContentPolicy(),
        expectedBundleIdentifier: String = "com.minh-ton.Reynard"
    ) {
        self.fileManager = fileManager
        self.contentPolicy = contentPolicy
        self.expectedBundleIdentifier = expectedBundleIdentifier
    }

    func validate(at rootURL: URL, availableCapacity: UInt64) throws -> ValidatedReynardBackup {
        let root = rootURL.standardizedFileURL
        let rootInformation = try fileInformation(at: root)
        guard rootInformation.st_mode & S_IFMT == S_IFDIR else {
            throw ReynardDataTransferError.unsupportedFileType
        }

        let manifestURL = root.appendingPathComponent("manifest.json", isDirectory: false)
        let manifestInformation = try fileInformation(at: manifestURL, missingError: .invalidManifest)
        guard Self.isSupportedFile(
            mode: manifestInformation.st_mode,
            linkCount: manifestInformation.st_nlink
        ) else {
            throw ReynardDataTransferError.unsupportedFileType
        }
        guard manifestInformation.st_size >= 0,
              UInt64(manifestInformation.st_size) <= Self.maximumManifestSize else {
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
        guard manifest.sourceBundleIdentifier == expectedBundleIdentifier,
              !manifest.reynardVersion.isEmpty,
              !manifest.reynardBuild.isEmpty,
              manifest.fileCount >= 0,
              manifest.fileCount <= Self.maximumFileCount,
              manifest.files.count <= Self.maximumFileCount,
              manifest.fileCount == manifest.files.count,
              manifest.totalSize <= Self.maximumTotalSize else {
            throw ReynardDataTransferError.invalidManifest
        }

        var declaredPaths = Set<String>()
        var calculatedTotal: UInt64 = 0
        for file in manifest.files {
            guard isSafePackagePath(file.relativePath) else {
                throw ReynardDataTransferError.unsafePath
            }
            guard declaredPaths.insert(file.relativePath).inserted,
                  file.size <= Self.maximumFileSize,
                  (file.relativePath != "preferences.plist" ||
                    file.size <= Self.maximumPreferencesSize),
                  isValidSHA256(file.sha256) else {
                throw ReynardDataTransferError.invalidManifest
            }
            let (newTotal, overflow) = calculatedTotal.addingReportingOverflow(file.size)
            guard !overflow, newTotal <= Self.maximumTotalSize else {
                throw ReynardDataTransferError.invalidManifest
            }
            calculatedTotal = newTotal
        }
        guard calculatedTotal == manifest.totalSize,
              declaredPaths.contains("preferences.plist") else {
            throw ReynardDataTransferError.invalidManifest
        }

        let (stagedSize, multiplicationOverflow) = manifest.totalSize.multipliedReportingOverflow(by: 2)
        let (requiredCapacity, additionOverflow) = stagedSize.addingReportingOverflow(Self.stagingAllowance)
        guard !multiplicationOverflow,
              !additionOverflow,
              availableCapacity >= requiredCapacity else {
            throw ReynardDataTransferError.insufficientSpace
        }

        let actualPaths = try enumerateRegularFiles(beneath: root)
        if !declaredPaths.isSubset(of: actualPaths) {
            throw ReynardDataTransferError.missingFile
        }
        if !actualPaths.isSubset(of: declaredPaths) {
            throw ReynardDataTransferError.extraFile
        }

        for file in manifest.files {
            let url = root.appendingPathComponent(file.relativePath, isDirectory: false)
            let information = try fileInformation(at: url, missingError: .missingFile)
            guard Self.isSupportedFile(mode: information.st_mode, linkCount: information.st_nlink) else {
                throw ReynardDataTransferError.unsupportedFileType
            }
            guard information.st_size >= 0,
                  UInt64(information.st_size) == file.size else {
                throw ReynardDataTransferError.sizeMismatch
            }
            let hash: String
            do {
                hash = try ReynardFileHasher.sha256(of: url)
            } catch {
                throw ReynardDataTransferError.unsupportedFileType
            }
            guard hash == file.sha256 else {
                throw ReynardDataTransferError.checksumMismatch
            }
        }

        do {
            let preferencesURL = root.appendingPathComponent("preferences.plist")
            let preferencesInformation = try fileInformation(
                at: preferencesURL,
                missingError: .missingFile
            )
            guard preferencesInformation.st_size >= 0,
                  UInt64(preferencesInformation.st_size) <= Self.maximumPreferencesSize else {
                throw ReynardDataTransferError.invalidManifest
            }
            let data = try Data(contentsOf: preferencesURL)
            let value = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard value is [String: Any] else {
                throw ReynardDataTransferError.invalidManifest
            }
        } catch let error as ReynardDataTransferError {
            throw error
        } catch {
            throw ReynardDataTransferError.invalidManifest
        }

        return ValidatedReynardBackup(
            rootURL: root,
            manifest: manifest,
            files: manifest.files.sorted { $0.relativePath < $1.relativePath }
        )
    }

    static func isSupportedFile(mode: mode_t, linkCount: nlink_t) -> Bool {
        mode & S_IFMT == S_IFREG && linkCount == 1
    }

    private func enumerateRegularFiles(beneath root: URL) throws -> Set<String> {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ReynardDataTransferError.invalidManifest
        }

        let rootComponents = root.pathComponents
        var paths = Set<String>()
        var entryCount = 0
        while let url = enumerator.nextObject() as? URL {
            entryCount += 1
            guard entryCount <= Self.maximumFileCount * 2 else {
                throw ReynardDataTransferError.invalidManifest
            }

            let standardized = url.standardizedFileURL
            let components = standardized.pathComponents
            guard components.starts(with: rootComponents),
                  components.count > rootComponents.count else {
                throw ReynardDataTransferError.unsafePath
            }
            let relativePath = components.dropFirst(rootComponents.count).joined(separator: "/")
            guard isCanonicalRelativePath(relativePath) else {
                throw ReynardDataTransferError.unsafePath
            }

            let information = try fileInformation(at: standardized)
            switch information.st_mode & S_IFMT {
            case S_IFDIR:
                continue
            case S_IFREG where Self.isSupportedFile(
                mode: information.st_mode,
                linkCount: information.st_nlink
            ):
                if relativePath != "manifest.json" {
                    paths.insert(relativePath)
                }
            default:
                if information.st_mode & S_IFMT == S_IFLNK {
                    enumerator.skipDescendants()
                }
                throw ReynardDataTransferError.unsupportedFileType
            }
        }
        guard enumerationError == nil else {
            throw ReynardDataTransferError.invalidManifest
        }
        return paths
    }

    private func isSafePackagePath(_ path: String) -> Bool {
        guard isCanonicalRelativePath(path) else {
            return false
        }
        if path == "preferences.plist" {
            return true
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.first == "payload", components.count > 2 else {
            return false
        }
        return contentPolicy.includes(relativePath: components.dropFirst().joined(separator: "/"))
    }

    private func isCanonicalRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private func fileInformation(
        at url: URL,
        missingError: ReynardDataTransferError = .unsupportedFileType
    ) throws -> stat {
        var information = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return -1 }
            return lstat(representation, &information)
        }
        guard result == 0 else {
            throw missingError
        }
        return information
    }
}
