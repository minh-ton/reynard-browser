//
//  ReynardFileHasher.swift
//  Reynard
//

import CryptoKit
import Darwin
import Foundation

enum ReynardFileHasher {
    enum HashError: Error {
        case inaccessibleFile
        case unsupportedFileType
        case hardLink
    }

    private static let bufferSize = 1024 * 1024

    static func sha256(of url: URL) throws -> String {
        _ = try regularFileSize(at: url)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func regularFileSize(at url: URL) throws -> UInt64 {
        var information = stat()
        let status: Int32 = url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else {
                return -1
            }
            return lstat(representation, &information)
        }

        guard status == 0 else {
            throw HashError.inaccessibleFile
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw HashError.unsupportedFileType
        }
        guard information.st_nlink == 1 else {
            throw HashError.hardLink
        }
        guard information.st_size >= 0 else {
            throw HashError.inaccessibleFile
        }
        return UInt64(information.st_size)
    }
}
