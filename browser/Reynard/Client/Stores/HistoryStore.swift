//
//  HistoryStore.swift
//  Reynard
//
//  Created by Minh Ton on 23/4/26.
//

import Foundation
import SQLite3

struct HistoryStoreSnapshot {
    let items: [HistorySiteSnapshot]
}

struct HistorySiteSnapshot: Hashable {
    let id: Int64
    let title: String
    let url: URL
    let lastVisitedAt: Date
}

final class HistoryStore {
    static let shared = HistoryStore()
    
    private enum Constants {
        static let databaseName = "History"
    }
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.HistoryStore.Queue", qos: .userInitiated)
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
            .appendingPathComponent("History", isDirectory: true)
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
    
    // MARK: - History
    
    func currentSnapshot() -> HistoryStoreSnapshot {
        stateQueue.sync {
            HistoryStoreSnapshot(items: fetchSitesLocked())
        }
    }
    
    func currentSnapshot(limit: Int, offset: Int) -> HistoryStoreSnapshot {
        stateQueue.sync {
            HistoryStoreSnapshot(items: fetchSitesLocked(limit: limit, offset: offset))
        }
    }
    
    func search(matching query: String, limit: Int) -> HistoryStoreSnapshot {
        stateQueue.sync {
            HistoryStoreSnapshot(items: searchSitesLocked(matching: query, limit: limit))
        }
    }
    
    func interruptReader() {
        guard let database else {
            return
        }
        
        sqlite3_interrupt(database)
    }
    
    func recordVisit(url: URL, title: String, visitedAt: Date = Date()) {
        stateQueue.async {
            guard URLUtils.isWebURL(url) else {
                return
            }
            
            if self.recordVisitLocked(url: url, title: title, visitedAt: visitedAt) {
                self.postDidChange()
            }
        }
    }
    
    func updatePageTitle(for pageURL: URL, title: String) {
        let normalizedTitle = pageTitle(title, fallbackURL: pageURL)
        guard !normalizedTitle.isEmpty else {
            return
        }
        
        stateQueue.async {
            guard URLUtils.isWebURL(pageURL) else {
                return
            }
            
            if self.updateTitleLocked(for: pageURL, title: normalizedTitle) {
                self.postDidChange()
            }
        }
    }
    
    func removeSite(id: Int64) {
        stateQueue.async {
            if self.deleteHistoryItemLocked(id: id) {
                self.postDidChange()
            }
        }
    }
    
    func clearVisits(since startDate: Date?) {
        stateQueue.async {
            if self.clearHistoryLocked(since: startDate) {
                self.postDidChange()
            }
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
            assertionFailure("Failed to open History database")
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
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL UNIQUE,
            host TEXT NOT NULL DEFAULT '',
            stripped_url TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL,
            visit_count INTEGER NOT NULL DEFAULT 0,
            frecency INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            siteID INTEGER NOT NULL REFERENCES history(id) ON DELETE CASCADE,
            date REAL NOT NULL,
            UNIQUE(siteID, date)
        );
        
        CREATE INDEX IF NOT EXISTS idx_history_updated_at ON history(updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_history_host_frecency ON history(host, frecency DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_history_stripped_url_frecency ON history(stripped_url, frecency DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_history_frecency_id ON history(frecency DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_visits_siteID_date ON visits(siteID, date DESC);
        """
        
        _ = executeLocked(sql)
        ensureHistoryColumnLocked(name: "host", definition: "TEXT NOT NULL DEFAULT ''")
        ensureHistoryColumnLocked(name: "stripped_url", definition: "TEXT NOT NULL DEFAULT ''")
        ensureHistoryColumnLocked(name: "visit_count", definition: "INTEGER NOT NULL DEFAULT 0")
        ensureHistoryColumnLocked(name: "frecency", definition: "INTEGER NOT NULL DEFAULT 0")
        backfillHistorySearchMetadataLocked()
    }
    
    // MARK: - Record Mutations
    
    private func recordVisitLocked(url: URL, title: String, visitedAt: Date) -> Bool {
        let normalizedTitle = pageTitle(title, fallbackURL: url)
        let timestamp = visitedAt.timeIntervalSince1970
        
        guard beginTransactionLocked() else {
            return false
        }
        
        guard upsertHistoryLocked(url: url.absoluteString, title: normalizedTitle, timestamp: timestamp),
              let siteID = siteIDLocked(for: url.absoluteString),
              insertVisitLocked(siteID: siteID, timestamp: timestamp),
              incrementVisitStatsLocked(siteID: siteID, lastVisitedAt: visitedAt) else {
            rollbackTransactionLocked()
            return false
        }
        
        guard commitTransactionLocked() else {
            rollbackTransactionLocked()
            return false
        }
        
        return true
    }
    
    private func updateTitleLocked(for pageURL: URL, title: String) -> Bool {
        guard let statement = prepareStatementLocked(
            "UPDATE history SET title = ? WHERE url = ? AND title != ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(title, to: statement, at: 1)
        bind(pageURL.absoluteString, to: statement, at: 2)
        bind(title, to: statement, at: 3)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }
        
        return sqlite3_changes(database) > 0
    }
    
    private func deleteHistoryItemLocked(id: Int64) -> Bool {
        guard let statement = prepareStatementLocked(
            "DELETE FROM history WHERE id = ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, id)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }
        
        return sqlite3_changes(database) > 0
    }
    
    private func clearHistoryLocked(since startDate: Date?) -> Bool {
        guard beginTransactionLocked() else {
            return false
        }
        
        if let startDate {
            guard deleteVisitsLocked(since: startDate.timeIntervalSince1970),
                  executeLocked("DELETE FROM history WHERE id NOT IN (SELECT DISTINCT siteID FROM visits);"),
                  rebuildHistoryStatsLocked() else {
                rollbackTransactionLocked()
                return false
            }
        } else {
            guard executeLocked("DELETE FROM history;") else {
                rollbackTransactionLocked()
                return false
            }
        }
        
        guard commitTransactionLocked() else {
            rollbackTransactionLocked()
            return false
        }
        
        return true
    }
    
    private func deleteVisitsLocked(since timestamp: TimeInterval) -> Bool {
        guard let statement = prepareStatementLocked("DELETE FROM visits WHERE date >= ?;") else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, timestamp)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func rebuildHistoryStatsLocked() -> Bool {
        guard let selectStatement = prepareStatementLocked(
            """
            SELECT history.id, COUNT(visits.id), MAX(visits.date)
            FROM history
            JOIN visits ON visits.siteID = history.id
            GROUP BY history.id;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(selectStatement)
        }
        
        guard let updateStatement = prepareStatementLocked(
            "UPDATE history SET visit_count = ?, updated_at = ?, frecency = ? WHERE id = ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(updateStatement)
        }
        
        while sqlite3_step(selectStatement) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStatement, 0)
            let visitCount = Int(sqlite3_column_int64(selectStatement, 1))
            let updatedAt = sqlite3_column_double(selectStatement, 2)
            let frecency = frecencyScore(forVisitCount: visitCount, lastVisitedAt: Date(timeIntervalSince1970: updatedAt))
            
            sqlite3_reset(updateStatement)
            sqlite3_clear_bindings(updateStatement)
            sqlite3_bind_int64(updateStatement, 1, Int64(visitCount))
            sqlite3_bind_double(updateStatement, 2, updatedAt)
            sqlite3_bind_int64(updateStatement, 3, Int64(frecency))
            sqlite3_bind_int64(updateStatement, 4, id)
            
            guard sqlite3_step(updateStatement) == SQLITE_DONE else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Snapshot Queries
    
    private func fetchSitesLocked() -> [HistorySiteSnapshot] {
        fetchSitesLocked(limit: nil, offset: 0)
    }
    
    private func fetchSitesLocked(limit: Int?, offset: Int) -> [HistorySiteSnapshot] {
        let sql: String
        if limit != nil {
            sql = """
            SELECT id, title, url, updated_at
            FROM history
            ORDER BY updated_at DESC
            LIMIT ? OFFSET ?;
            """
        } else {
            sql = """
            SELECT id, title, url, updated_at
            FROM history
            ORDER BY updated_at DESC;
            """
        }
        
        guard let statement = prepareStatementLocked(sql) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        if let limit {
            sqlite3_bind_int64(statement, 1, Int64(limit))
            sqlite3_bind_int64(statement, 2, Int64(offset))
        }
        
        return readSnapshotsLocked(from: statement)
    }
    
    // MARK: - Search
    
    private func searchSitesLocked(matching query: String, limit: Int) -> [HistorySiteSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }
        
        var results: [HistorySiteSnapshot] = []
        var seenURLs = Set<URL>()
        
        for item in heuristicMatchesLocked(matching: normalizedQuery, limit: 1) {
            if seenURLs.insert(item.url).inserted {
                results.append(item)
            }
        }
        
        let remaining = max(0, limit - results.count)
        guard remaining > 0 else {
            return results
        }
        
        for item in rankedMatchesLocked(matching: normalizedQuery, limit: remaining) {
            if seenURLs.insert(item.url).inserted {
                results.append(item)
            }
        }
        
        return results
    }
    
    private func heuristicMatchesLocked(matching query: String, limit: Int) -> [HistorySiteSnapshot] {
        if isHostOnlyQuery(query) {
            let upperBound = query + "\u{FFFF}"
            guard let statement = prepareStatementLocked(
                """
                SELECT id, title, url, updated_at
                FROM history
                WHERE host >= ? AND host < ?
                ORDER BY frecency DESC, id DESC
                LIMIT ?;
                """
            ) else {
                return []
            }
            
            defer {
                sqlite3_finalize(statement)
            }
            
            bind(query, to: statement, at: 1)
            bind(upperBound, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, Int64(limit))
            return readSnapshotsLocked(from: statement)
        }
        
        guard query.contains("/") || query.contains(":") || query.contains("?") else {
            return []
        }
        
        let urlComponents = URLUtils.urlMatchComponents(from: query)
        guard !urlComponents.hostAndPort.isEmpty else {
            return []
        }
        
        let host = urlComponents.hostAndPort
        let strippedPrefix = host + urlComponents.suffix
        let upperBound = strippedPrefix + "\u{FFFF}"
        guard let statement = prepareStatementLocked(
            """
            SELECT id, title, url, updated_at
            FROM history
            WHERE (host = ? OR host = 'www.' || ?)
              AND stripped_url >= ?
              AND stripped_url < ?
            ORDER BY frecency DESC, id DESC
            LIMIT ?;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(host, to: statement, at: 2)
        bind(strippedPrefix, to: statement, at: 3)
        bind(upperBound, to: statement, at: 4)
        sqlite3_bind_int64(statement, 5, Int64(limit))
        return readSnapshotsLocked(from: statement)
    }
    
    private func rankedMatchesLocked(matching query: String, limit: Int) -> [HistorySiteSnapshot] {
        let tokens = query
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        
        guard !tokens.isEmpty else {
            return []
        }
        
        let conditions = Array(repeating: "(title LIKE ? COLLATE NOCASE OR stripped_url LIKE ? COLLATE NOCASE OR host LIKE ? COLLATE NOCASE)", count: tokens.count)
            .joined(separator: " AND ")
        let sql = """
        SELECT id, title, url, updated_at
        FROM history
        WHERE frecency > 0
          AND \(conditions)
        ORDER BY frecency DESC, id DESC
        LIMIT ?;
        """
        
        guard let statement = prepareStatementLocked(sql) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var bindIndex: Int32 = 1
        for token in tokens {
            let escapedToken = escapedLikePattern(token)
            bind("%\(escapedToken)%", to: statement, at: bindIndex)
            bind("%\(escapedToken)%", to: statement, at: bindIndex + 1)
            bind("\(escapedToken)%", to: statement, at: bindIndex + 2)
            bindIndex += 3
        }
        
        sqlite3_bind_int64(statement, bindIndex, Int64(limit))
        return readSnapshotsLocked(from: statement)
    }
    
    // MARK: - Snapshot Decoding
    
    private func readSnapshotsLocked(from statement: OpaquePointer?) -> [HistorySiteSnapshot] {
        
        var items: [HistorySiteSnapshot] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let id = sqlite3_column_int64(statement, 0)
                let title = string(from: statement, at: 1)
                let urlString = string(from: statement, at: 2)
                let visitDate = sqlite3_column_double(statement, 3)
                
                guard let url = URL(string: urlString), URLUtils.isWebURL(url) else {
                    continue
                }
                
                items.append(
                    HistorySiteSnapshot(
                        id: id,
                        title: title,
                        url: url,
                        lastVisitedAt: Date(timeIntervalSince1970: visitDate)
                    )
                )
            case SQLITE_DONE:
                return items
            case SQLITE_INTERRUPT:
                return []
            default:
                return []
            }
        }
    }
    
    // MARK: - Record Persistence
    
    private func upsertHistoryLocked(url: String, title: String, timestamp: TimeInterval) -> Bool {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        let strippedURL = URLUtils.normalizedURLStringForMatching(from: url)
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO history (url, host, stripped_url, title, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                host = excluded.host,
                stripped_url = excluded.stripped_url,
                title = CASE
                    WHEN excluded.title = '' THEN history.title
                    ELSE excluded.title
                END,
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(url, to: statement, at: 1)
        bind(host, to: statement, at: 2)
        bind(strippedURL, to: statement, at: 3)
        bind(title, to: statement, at: 4)
        sqlite3_bind_double(statement, 5, timestamp)
        sqlite3_bind_double(statement, 6, timestamp)
        
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func siteIDLocked(for url: String) -> Int64? {
        guard let statement = prepareStatementLocked(
            "SELECT id FROM history WHERE url = ? LIMIT 1;"
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(url, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return sqlite3_column_int64(statement, 0)
    }
    
    private func insertVisitLocked(siteID: Int64, timestamp: TimeInterval) -> Bool {
        guard let statement = prepareStatementLocked(
            "INSERT INTO visits (siteID, date) VALUES (?, ?);"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, siteID)
        sqlite3_bind_double(statement, 2, timestamp)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func beginTransactionLocked() -> Bool {
        return executeLocked("BEGIN IMMEDIATE TRANSACTION;")
    }
    
    private func commitTransactionLocked() -> Bool {
        return executeLocked("COMMIT TRANSACTION;")
    }
    
    private func rollbackTransactionLocked() {
        _ = executeLocked("ROLLBACK TRANSACTION;")
    }
    
    // MARK: - Schema Migration
    
    private func ensureHistoryColumnLocked(name: String, definition: String) {
        guard !historyColumnExistsLocked(name) else {
            return
        }
        
        _ = executeLocked("ALTER TABLE history ADD COLUMN \(name) \(definition);")
    }
    
    private func historyColumnExistsLocked(_ name: String) -> Bool {
        guard let statement = prepareStatementLocked("PRAGMA table_info(history);") else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if string(from: statement, at: 1) == name {
                return true
            }
        }
        
        return false
    }
    
    private func backfillHistorySearchMetadataLocked() {
        guard let selectStatement = prepareStatementLocked(
            """
            SELECT id, url, updated_at
            FROM history
            WHERE host = '' OR stripped_url = '' OR visit_count = 0 OR frecency = 0;
            """
        ) else {
            return
        }
        
        defer {
            sqlite3_finalize(selectStatement)
        }
        
        guard let updateStatement = prepareStatementLocked(
            "UPDATE history SET host = ?, stripped_url = ?, visit_count = ?, frecency = ? WHERE id = ?;"
        ) else {
            return
        }
        
        defer {
            sqlite3_finalize(updateStatement)
        }
        
        while sqlite3_step(selectStatement) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStatement, 0)
            let urlString = string(from: selectStatement, at: 1)
            let updatedAt = sqlite3_column_double(selectStatement, 2)
            guard let url = URL(string: urlString), URLUtils.isWebURL(url) else {
                continue
            }
            
            let visitCount = visitCountLocked(siteID: id)
            let frecency = frecencyScore(forVisitCount: visitCount, lastVisitedAt: Date(timeIntervalSince1970: updatedAt))
            
            sqlite3_reset(updateStatement)
            sqlite3_clear_bindings(updateStatement)
            bind(url.host?.lowercased() ?? "", to: updateStatement, at: 1)
            bind(URLUtils.normalizedURLStringForMatching(from: urlString), to: updateStatement, at: 2)
            sqlite3_bind_int64(updateStatement, 3, Int64(visitCount))
            sqlite3_bind_int64(updateStatement, 4, Int64(frecency))
            sqlite3_bind_int64(updateStatement, 5, id)
            _ = sqlite3_step(updateStatement)
        }
    }
    
    // MARK: - Frecency
    
    private func incrementVisitStatsLocked(siteID: Int64, lastVisitedAt: Date) -> Bool {
        let recencyWeight = frecencyWeight(for: lastVisitedAt)
        guard let statement = prepareStatementLocked(
            "UPDATE history SET visit_count = visit_count + 1, frecency = (visit_count + 1) * ? WHERE id = ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, Int64(recencyWeight))
        sqlite3_bind_int64(statement, 2, siteID)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func visitCountLocked(siteID: Int64) -> Int {
        guard let statement = prepareStatementLocked(
            "SELECT COUNT(*) FROM visits WHERE siteID = ?;"
        ) else {
            return 0
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, siteID)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    private func frecencyScore(forVisitCount visitCount: Int, lastVisitedAt: Date) -> Int {
        max(visitCount, 1) * frecencyWeight(for: lastVisitedAt)
    }
    
    private func frecencyWeight(for lastVisitedAt: Date) -> Int {
        let age = Date().timeIntervalSince(lastVisitedAt)
        if age < 86_400.0 {
            return 100
        }
        
        if age < 7.0 * 86_400.0 {
            return 70
        }
        
        if age < 30.0 * 86_400.0 {
            return 50
        }
        
        if age < 90.0 * 86_400.0 {
            return 30
        }
        
        return 10
    }
    
    // MARK: - SQLite
    
    private func executeLocked(_ sql: String) -> Bool {
        guard let database else {
            return false
        }
        
        var errorPointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        if let errorPointer {
            sqlite3_free(errorPointer)
        }
        return result == SQLITE_OK
    }
    
    private func prepareStatementLocked(_ sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        
        return statement
    }
    
    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }
    
    private func string(from statement: OpaquePointer?, at index: Int32) -> String {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            return ""
        }
        
        return String(cString: rawValue)
    }
    
    // MARK: - Helpers
    
    private func pageTitle(_ title: String, fallbackURL: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallbackURL.host ?? fallbackURL.absoluteString : trimmedTitle
    }
    
    private func isHostOnlyQuery(_ query: String) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        
        return !query.unicodeScalars.contains { scalar in
            scalar.properties.isWhitespace || scalar == "/" || scalar == "?" || scalar == "#"
        }
    }
    
    private func escapedLikePattern(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
    
    private func postDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: self)
        }
    }
}
