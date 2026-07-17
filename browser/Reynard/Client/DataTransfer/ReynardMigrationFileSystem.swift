//
//  ReynardMigrationFileSystem.swift
//  Reynard
//

import Darwin
import Foundation

enum ReynardMigrationBoundary: CaseIterable {
    case beforeStaging
    case afterStaging
    case afterRollbackRename
    case afterFirstFinalRename
    case afterSecondFinalRename
    case duringPreferenceImport
}

protocol ReynardMigrationFileSystem {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func isRegularFile(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func removeDirectoryIfEmpty(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func checkpoint(_ boundary: ReynardMigrationBoundary) throws
}

struct DefaultReynardMigrationFileSystem: ReynardMigrationFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func isDirectory(at url: URL) -> Bool {
        itemType(at: url) == S_IFDIR
    }

    func isRegularFile(at url: URL) -> Bool {
        itemType(at: url) == S_IFREG
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try fileManager.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func removeDirectoryIfEmpty(at url: URL) throws {
        let result: Int32 = url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else {
                errno = EINVAL
                return -1
            }
            return rmdir(representation)
        }
        guard result != 0 else { return }

        let errorCode = errno
        guard errorCode != ENOENT, errorCode != ENOTEMPTY else { return }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode))
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func checkpoint(_ boundary: ReynardMigrationBoundary) throws {}

    private func itemType(at url: URL) -> mode_t? {
        var information = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return -1 }
            return lstat(representation, &information)
        }
        guard result == 0 else { return nil }
        return information.st_mode & S_IFMT
    }
}
