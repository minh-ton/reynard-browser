//
//  SyncMetadataStore.swift
//  Reynard
//
//  Local bookkeeping for Sync: which Sync record ID belongs to which
//  history URL, plus a cache of other devices' open tabs.
//

import Foundation
import SQLite3

final class SyncMetadataStore {
    static let shared = SyncMetadataStore()

    private let directoryURL: URL
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        openDatabase()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    private func openDatabase() {
        let path = directoryURL.appendingPathComponent("SyncMetadata", isDirectory: false).path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle {
                sqlite3_close(handle)
            }
            return
        }
        database = handle
        execute("PRAGMA journal_mode = WAL;")
        execute("""
        CREATE TABLE IF NOT EXISTS history_guids (
            url TEXT PRIMARY KEY,
            guid TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_history_guids_guid ON history_guids(guid);
        """)
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let database else {
            return false
        }
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    // MARK: - History GUIDs

    func historyGUIDs(for urls: [String]) -> [String: String] {
        guard let database, !urls.isEmpty else {
            return [:]
        }
        var result: [String: String] = [:]
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT guid FROM history_guids WHERE url = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        for url in urls {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, url, -1, sqliteTransient)
            if sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) {
                result[url] = String(cString: raw)
            }
        }
        return result
    }

    func setHistoryGUIDs(_ mapping: [String: String]) {
        guard let database, !mapping.isEmpty else {
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO history_guids (url, guid) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        execute("BEGIN IMMEDIATE TRANSACTION;")
        for (url, guid) in mapping {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, url, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, guid, -1, sqliteTransient)
            sqlite3_step(statement)
        }
        execute("COMMIT TRANSACTION;")
    }

    // MARK: - Remote tabs cache

    private var remoteTabsURL: URL {
        directoryURL.appendingPathComponent("RemoteTabs.json", isDirectory: false)
    }

    func loadRemoteTabs() -> [RemoteClientTabs] {
        guard let data = try? Data(contentsOf: remoteTabsURL) else {
            return []
        }
        return (try? JSONDecoder().decode([RemoteClientTabs].self, from: data)) ?? []
    }

    func saveRemoteTabs(_ clients: [RemoteClientTabs]) {
        guard let data = try? JSONEncoder().encode(clients) else {
            return
        }
        try? data.write(to: remoteTabsURL, options: [.atomic])
    }

    // MARK: - Reset

    func reset() {
        execute("DELETE FROM history_guids;")
        try? FileManager.default.removeItem(at: remoteTabsURL)
    }
}

struct RemoteClientTabs: Codable, Equatable {
    struct RemoteTab: Codable, Equatable {
        let title: String
        let url: String
        let lastUsed: Date
    }

    let clientID: String
    let name: String
    let lastModified: Date
    let tabs: [RemoteTab]
}
