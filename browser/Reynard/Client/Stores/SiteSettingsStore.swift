//
//  SiteSettingsStore.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import Foundation
import SQLite3

enum SiteWebsiteMode: String {
    case desktop
    case mobile
}

struct SiteSettingsRecord {
    let host: String
    let pageZoom: Int?
    let websiteMode: SiteWebsiteMode?
    let readerMode: Bool?
    let createdAt: Date
    let updatedAt: Date
}

final class SiteSettingsStore {
    static let shared = SiteSettingsStore()
    
    private enum Constants {
        static let databaseName = "SiteSettings"
        static let pageZoomRange = 50...300
    }
    
    private enum SettingColumn: String {
        case pageZoom = "page_zoom"
        case websiteMode = "website_mode"
        case readerMode = "reader_mode"
    }
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.SiteSettingsStore.Queue", qos: .utility)
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Lifecycle
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("SiteSettings", isDirectory: true)
        
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent(Constants.databaseName, isDirectory: false)
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
        }
    }
    
    deinit {
        stateQueue.sync {
            guard let database else {
                return
            }
            
            sqlite3_close(database)
            self.database = nil
        }
    }
    
    // MARK: - Settings
    
    func settings(for url: URL) -> SiteSettingsRecord? {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return nil
        }
        
        return stateQueue.sync {
            settingsLocked(for: host)
        }
    }
    
    func allSettings() -> [SiteSettingsRecord] {
        return stateQueue.sync {
            settingsLocked(where: nil)
        }
    }
    
    func settingsWithPageZoom() -> [SiteSettingsRecord] {
        return stateQueue.sync {
            settingsLocked(where: "page_zoom IS NOT NULL")
        }
    }
    
    func settingsWithWebsiteMode() -> [SiteSettingsRecord] {
        return stateQueue.sync {
            settingsLocked(where: "website_mode IS NOT NULL")
        }
    }
    
    func settingsWithReaderMode() -> [SiteSettingsRecord] {
        return stateQueue.sync {
            settingsLocked(where: "reader_mode IS NOT NULL")
        }
    }
    
    func setPageZoom(_ value: Int, for url: URL) -> Bool {
        guard Constants.pageZoomRange.contains(value),
              let host = URLUtils.normalizedHost(url.host) else {
            return false
        }
        
        return stateQueue.sync {
            if value == Prefs.AppearanceSettings.defaultPageZoomLevel {
                return clearSettingLocked(.pageZoom, for: host)
            }
            
            return setIntSettingLocked(value, column: .pageZoom, for: host)
        }
    }
    
    func setWebsiteMode(_ mode: SiteWebsiteMode, for url: URL) -> Bool {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return false
        }

        return setWebsiteMode(mode, forHost: host)
    }

    func setWebsiteMode(_ mode: SiteWebsiteMode, forHost host: String) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        
        return stateQueue.sync {
            setTextSettingLocked(mode.rawValue, column: .websiteMode, for: host)
        }
    }
    
    func setReaderMode(_ enabled: Bool, for url: URL) -> Bool {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return false
        }
        
        return stateQueue.sync {
            if !enabled {
                return clearSettingLocked(.readerMode, for: host)
            }
            
            return setIntSettingLocked(1, column: .readerMode, for: host)
        }
    }
    
    func setPageZoom(_ value: Int, forHost host: String) -> Bool {
        guard Constants.pageZoomRange.contains(value),
              let host = URLUtils.normalizedHost(host) else {
            return false
        }
        
        return stateQueue.sync {
            if value == Prefs.AppearanceSettings.defaultPageZoomLevel {
                return clearSettingLocked(.pageZoom, for: host)
            }
            
            return setIntSettingLocked(value, column: .pageZoom, for: host)
        }
    }
    
    func clearPageZoom(forHost host: String) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        
        return stateQueue.sync {
            clearSettingLocked(.pageZoom, for: host)
        }
    }
    
    func clearWebsiteMode(for url: URL) -> Bool {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return false
        }

        return clearWebsiteMode(forHost: host)
    }

    func clearWebsiteMode(forHost host: String) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        
        return stateQueue.sync {
            clearSettingLocked(.websiteMode, for: host)
        }
    }
    
    func clearReaderMode(for url: URL) -> Bool {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return false
        }
        
        return stateQueue.sync {
            clearSettingLocked(.readerMode, for: host)
        }
    }
    
    func clearSettings(for url: URL) -> Bool {
        guard let host = URLUtils.normalizedHost(url.host) else {
            return false
        }
        
        return stateQueue.sync {
            deleteSettingsLocked(for: host)
        }
    }
    
    func clearAllSettings() -> Bool {
        return stateQueue.sync {
            executeLocked("DELETE FROM site_settings;")
        }
    }
    
    func clearAllPageZoomSettings() -> Bool {
        return stateQueue.sync {
            clearAllSettingsLocked(column: .pageZoom)
        }
    }
    
    // MARK: - Storage
    
    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
    }
    
    private func openDatabaseLocked() {
        guard database == nil else {
            return
        }
        
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storage.databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            assertionFailure("Failed to open SiteSettings database")
            return
        }
        
        self.database = database
    }
    
    private func configureDatabaseLocked() {
        guard database != nil else {
            return
        }
        
        _ = executeLocked("PRAGMA foreign_keys = ON;")
        _ = executeLocked("PRAGMA journal_mode = WAL;")
        _ = executeLocked("PRAGMA synchronous = NORMAL;")
        _ = executeLocked("PRAGMA temp_store = MEMORY;")
        sqlite3_busy_timeout(database, 2_500)
    }
    
    private func createSchemaLocked() {
        let sql = """
        CREATE TABLE IF NOT EXISTS site_settings (
            host TEXT PRIMARY KEY,
            page_zoom INTEGER NULL CHECK(page_zoom IS NULL OR page_zoom BETWEEN 50 AND 300),
            website_mode TEXT NULL CHECK(website_mode IS NULL OR website_mode IN ('desktop', 'mobile')),
            reader_mode INTEGER NULL CHECK(reader_mode IS NULL OR reader_mode IN (0, 1)),
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_site_settings_updated_at ON site_settings(updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_site_settings_page_zoom ON site_settings(page_zoom) WHERE page_zoom IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_site_settings_website_mode ON site_settings(website_mode) WHERE website_mode IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_site_settings_reader_mode ON site_settings(reader_mode) WHERE reader_mode IS NOT NULL;
        """
        
        _ = executeLocked(sql)
    }
    
    // MARK: - Records
    
    private func settingsLocked(for host: String) -> SiteSettingsRecord? {
        guard let statement = prepareStatementLocked(
            """
            SELECT host, page_zoom, website_mode, reader_mode, created_at, updated_at
            FROM site_settings
            WHERE host = ?
            LIMIT 1;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return record(from: statement)
    }
    
    private func settingsLocked(where condition: String?) -> [SiteSettingsRecord] {
        let sql: String
        if let condition {
            sql = """
            SELECT host, page_zoom, website_mode, reader_mode, created_at, updated_at
            FROM site_settings
            WHERE \(condition)
            ORDER BY updated_at DESC;
            """
        } else {
            sql = """
            SELECT host, page_zoom, website_mode, reader_mode, created_at, updated_at
            FROM site_settings
            ORDER BY updated_at DESC;
            """
        }
        
        guard let statement = prepareStatementLocked(sql) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var records: [SiteSettingsRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = record(from: statement) else {
                continue
            }
            
            records.append(record)
        }
        return records
    }
    
    private func setIntSettingLocked(_ value: Int, column: SettingColumn, for host: String) -> Bool {
        let timestamp = Date().timeIntervalSince1970
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO site_settings (host, \(column.rawValue), created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(host) DO UPDATE SET
                \(column.rawValue) = excluded.\(column.rawValue),
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, Int32(value))
        sqlite3_bind_double(statement, 3, timestamp)
        sqlite3_bind_double(statement, 4, timestamp)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func setTextSettingLocked(_ value: String, column: SettingColumn, for host: String) -> Bool {
        let timestamp = Date().timeIntervalSince1970
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO site_settings (host, \(column.rawValue), created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(host) DO UPDATE SET
                \(column.rawValue) = excluded.\(column.rawValue),
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(value, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, timestamp)
        sqlite3_bind_double(statement, 4, timestamp)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func clearSettingLocked(_ column: SettingColumn, for host: String) -> Bool {
        let timestamp = Date().timeIntervalSince1970
        guard let statement = prepareStatementLocked(
            """
            UPDATE site_settings
            SET \(column.rawValue) = NULL, updated_at = ?
            WHERE host = ?;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, timestamp)
        bind(host, to: statement, at: 2)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }
        
        return deleteEmptySettingsLocked(for: host)
    }
    
    private func deleteEmptySettingsLocked(for host: String) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            DELETE FROM site_settings
            WHERE host = ?
                AND page_zoom IS NULL
                AND website_mode IS NULL
                AND reader_mode IS NULL;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteSettingsLocked(for host: String) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            DELETE FROM site_settings
            WHERE host = ?;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func clearAllSettingsLocked(column: SettingColumn) -> Bool {
        let timestamp = Date().timeIntervalSince1970
        guard let statement = prepareStatementLocked(
            """
            UPDATE site_settings
            SET \(column.rawValue) = NULL, updated_at = ?
            WHERE \(column.rawValue) IS NOT NULL;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, timestamp)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }
        
        return executeLocked(
            """
            DELETE FROM site_settings
            WHERE page_zoom IS NULL
                AND website_mode IS NULL
                AND reader_mode IS NULL;
            """
        )
    }
    
    // MARK: - SQLite
    
    private func prepareStatementLocked(_ sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("Failed to prepare SiteSettings SQL statement")
            return nil
        }
        
        return statement
    }
    
    private func executeLocked(_ sql: String) -> Bool {
        guard let database else {
            return false
        }
        
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }
    
    private func bind(_ text: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }
    
    private func string(from statement: OpaquePointer, at index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        
        return String(cString: cString)
    }
    
    private func record(from statement: OpaquePointer) -> SiteSettingsRecord? {
        let host = string(from: statement, at: 0)
        guard !host.isEmpty else {
            return nil
        }
        
        let pageZoom: Int?
        if sqlite3_column_type(statement, 1) == SQLITE_NULL {
            pageZoom = nil
        } else {
            pageZoom = Int(sqlite3_column_int(statement, 1))
        }
        
        let websiteMode: SiteWebsiteMode?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            websiteMode = nil
        } else {
            websiteMode = SiteWebsiteMode(rawValue: string(from: statement, at: 2))
        }
        
        let readerMode: Bool?
        if sqlite3_column_type(statement, 3) == SQLITE_NULL {
            readerMode = nil
        } else {
            readerMode = sqlite3_column_int(statement, 3) != 0
        }
        
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        return SiteSettingsRecord(
            host: host,
            pageZoom: pageZoom,
            websiteMode: websiteMode,
            readerMode: readerMode,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
