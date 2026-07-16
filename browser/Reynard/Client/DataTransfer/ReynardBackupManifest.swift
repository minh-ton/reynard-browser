//
//  ReynardBackupManifest.swift
//  Reynard
//

import Foundation

struct ReynardBackupManifest: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let reynardVersion: String
    let reynardBuild: String
    let createdAt: Date
    let sourceBundleIdentifier: String
    let fileCount: Int
    let totalSize: UInt64
    let files: [ReynardBackupFile]

    init(
        reynardVersion: String,
        reynardBuild: String,
        createdAt: Date,
        sourceBundleIdentifier: String,
        files: [ReynardBackupFile]
    ) {
        let sortedFiles = files.sorted { $0.relativePath < $1.relativePath }
        self.formatVersion = Self.currentFormatVersion
        self.reynardVersion = reynardVersion
        self.reynardBuild = reynardBuild
        self.createdAt = createdAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.fileCount = sortedFiles.count
        self.totalSize = sortedFiles.reduce(0) { $0 + $1.size }
        self.files = sortedFiles
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ReynardBackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReynardBackupManifest.self, from: data)
    }
}

struct ReynardBackupFile: Codable, Equatable {
    let relativePath: String
    let size: UInt64
    let sha256: String
}
