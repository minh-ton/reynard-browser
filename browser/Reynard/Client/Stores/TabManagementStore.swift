//
//  TabManagementStore.swift
//  Reynard
//
//  Created by Minh Ton on 4/4/26.
//

import Foundation
import SQLite3
import UIKit

final class TabManagementStore {
    static let shared = TabManagementStore()
    
    enum LastTabOverview: String, Codable {
        case regular
        case `private`
    }
    
    struct Snapshot {
        let regularTabs: [TabSnapshot]
        let privateTabs: [TabSnapshot]
        let selectedRegularTabID: UUID?
        let selectedPrivateTabID: UUID?
        let selectedTabMode: TabMode
        let lastTabOverview: LastTabOverview
    }
    
    struct TabSnapshot {
        let id: UUID
        let title: String
        let url: String?
        let thumbnail: UIImage?
        let isPrivate: Bool
    }
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
        let thumbnailCacheDirectoryURL: URL
    }
    
    private struct PersistedTab {
        let id: UUID
        let title: String
        let url: String?
    }
    
    private struct PersistedState {
        let selectedRegularTabID: UUID?
        let selectedPrivateTabID: UUID?
        let selectedTabMode: TabMode
        let lastTabOverview: LastTabOverview
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.TabManagementStore.Queue", qos: .userInitiated)
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
            .appendingPathComponent("TabManagement", isDirectory: true)
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("TabManagement", isDirectory: false),
            thumbnailCacheDirectoryURL: directoryURL.appendingPathComponent("ThumbCache", isDirectory: true)
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
            ensureStateRowLocked()
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
    
    // MARK: - Tabs
    
    func currentSnapshot() -> Snapshot {
        stateQueue.sync {
            let state = persistedStateLocked()
            return Snapshot(
                regularTabs: fetchTabsLocked(isPrivate: false),
                privateTabs: fetchTabsLocked(isPrivate: true),
                selectedRegularTabID: state.selectedRegularTabID,
                selectedPrivateTabID: state.selectedPrivateTabID,
                selectedTabMode: state.selectedTabMode,
                lastTabOverview: state.lastTabOverview
            )
        }
    }
    
    func preferredRestoredMode() -> TabMode {
        let snapshot = currentSnapshot()
        if snapshot.selectedTabMode == .private, !snapshot.privateTabs.isEmpty {
            return .private
        }
        if snapshot.selectedTabMode == .regular, !snapshot.regularTabs.isEmpty {
            return .regular
        }
        if !snapshot.regularTabs.isEmpty {
            return .regular
        }
        if !snapshot.privateTabs.isEmpty {
            return .private
        }
        return .regular
    }
    
    func persistTabs(
        regularTabs: [Tab],
        privateTabs: [Tab],
        selectedRegularTabID: UUID?,
        selectedPrivateTabID: UUID?,
        selectedTabMode: TabMode
    ) {
        let persistedRegularTabs = regularTabs.map {
            PersistedTab(id: $0.id, title: $0.title, url: $0.url)
        }
        let persistedPrivateTabs = privateTabs.map {
            PersistedTab(id: $0.id, title: $0.title, url: $0.url)
        }
        
        stateQueue.async {
            let lastTabOverview = self.persistedStateLocked().lastTabOverview
            
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return
            }
            
            guard self.executeLocked("DELETE FROM tabs;"),
                  self.saveStateLocked(
                    selectedRegularTabID: selectedRegularTabID,
                    selectedPrivateTabID: selectedPrivateTabID,
                    selectedTabMode: selectedTabMode,
                    lastTabOverview: lastTabOverview
                  ),
                  self.insertTabsLocked(persistedRegularTabs, isPrivate: false),
                  self.insertTabsLocked(persistedPrivateTabs, isPrivate: true) else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            self.pruneThumbCacheLocked(validTabIDs: Set((persistedRegularTabs + persistedPrivateTabs).map(\.id)))
        }
    }
    
    func persistLastOverview(_ lastTabOverview: LastTabOverview) {
        stateQueue.async {
            let state = self.persistedStateLocked()
            _ = self.saveStateLocked(
                selectedRegularTabID: state.selectedRegularTabID,
                selectedPrivateTabID: state.selectedPrivateTabID,
                selectedTabMode: state.selectedTabMode,
                lastTabOverview: lastTabOverview
            )
        }
    }
    
    func persistThumbnail(_ image: UIImage?, for tabID: UUID) {
        stateQueue.async {
            let fileURL = self.thumbnailFileURL(for: tabID)
            
            guard let image else {
                if self.fileManager.fileExists(atPath: fileURL.path) {
                    try? self.fileManager.removeItem(at: fileURL)
                }
                return
            }
            
            guard let data = image.pngData() else {
                return
            }
            
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    func tabs(matching query: String, limit: Int, isPrivate: Bool) -> [TabSnapshot] {
        stateQueue.sync {
            searchTabsLocked(matching: query, limit: limit, isPrivate: isPrivate)
        }
    }
    
    // MARK: - Storage
    
    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: storage.thumbnailCacheDirectoryURL, withIntermediateDirectories: true)
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
            assertionFailure("Failed to open TabManagement database")
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
        CREATE TABLE IF NOT EXISTS tab_state (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            selected_regular_tab_id TEXT,
            selected_private_tab_id TEXT,
            selected_tab_mode TEXT NOT NULL,
            last_tab_overview TEXT NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS tabs (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT,
            is_private INTEGER NOT NULL,
            position INTEGER NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_tabs_private_position ON tabs(is_private, position ASC);
        """
        
        _ = executeLocked(sql)
    }
    
    private func ensureStateRowLocked() {
        let state = persistedStateLocked()
        _ = saveStateLocked(
            selectedRegularTabID: state.selectedRegularTabID,
            selectedPrivateTabID: state.selectedPrivateTabID,
            selectedTabMode: state.selectedTabMode,
            lastTabOverview: state.lastTabOverview
        )
    }
    
    // MARK: - Persisted State
    
    private func persistedStateLocked() -> PersistedState {
        let defaultState = PersistedState(
            selectedRegularTabID: nil,
            selectedPrivateTabID: nil,
            selectedTabMode: .regular,
            lastTabOverview: .regular
        )
        
        guard let statement = prepareStatementLocked(
            """
            SELECT selected_regular_tab_id, selected_private_tab_id, selected_tab_mode, last_tab_overview
            FROM tab_state
            WHERE id = 1
            LIMIT 1;
            """
        ) else {
            return defaultState
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return defaultState
        }
        
        return PersistedState(
            selectedRegularTabID: optionalString(from: statement, at: 0).flatMap { UUID(uuidString: $0) },
            selectedPrivateTabID: optionalString(from: statement, at: 1).flatMap { UUID(uuidString: $0) },
            selectedTabMode: TabMode(rawValue: string(from: statement, at: 2)) ?? .regular,
            lastTabOverview: LastTabOverview(rawValue: string(from: statement, at: 3)) ?? .regular
        )
    }
    
    private func saveStateLocked(
        selectedRegularTabID: UUID?,
        selectedPrivateTabID: UUID?,
        selectedTabMode: TabMode,
        lastTabOverview: LastTabOverview
    ) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO tab_state (id, selected_regular_tab_id, selected_private_tab_id, selected_tab_mode, last_tab_overview)
            VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                selected_regular_tab_id = excluded.selected_regular_tab_id,
                selected_private_tab_id = excluded.selected_private_tab_id,
                selected_tab_mode = excluded.selected_tab_mode,
                last_tab_overview = excluded.last_tab_overview;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bindOptional(selectedRegularTabID?.uuidString, to: statement, at: 1)
        bindOptional(selectedPrivateTabID?.uuidString, to: statement, at: 2)
        bind(selectedTabMode.rawValue, to: statement, at: 3)
        bind(lastTabOverview.rawValue, to: statement, at: 4)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    // MARK: - Tab Queries
    
    private func fetchTabsLocked(isPrivate: Bool) -> [TabSnapshot] {
        guard let statement = prepareStatementLocked(
            """
            SELECT id, title, url
            FROM tabs
            WHERE is_private = ?
            ORDER BY position ASC;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, isPrivate ? 1 : 0)
        
        var tabs: [TabSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(from: statement, at: 0)) else {
                continue
            }
            
            tabs.append(
                TabSnapshot(
                    id: id,
                    title: string(from: statement, at: 1),
                    url: optionalString(from: statement, at: 2),
                    thumbnail: loadThumbnailLocked(for: id),
                    isPrivate: isPrivate
                )
            )
        }
        
        return tabs
    }
    
    private func searchTabsLocked(matching query: String, limit: Int, isPrivate: Bool) -> [TabSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }
        
        let strippedQuery = URLUtils.normalizedURLMatchString(from: normalizedQuery)
        let tabs = fetchTabsLocked(isPrivate: isPrivate)
        var matches: [TabSnapshot] = []
        matches.reserveCapacity(min(limit, tabs.count))
        
        for tab in tabs {
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let urlValue = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strippedURL = URLUtils.normalizedURLMatchString(from: urlValue)
            let titleMatches = !title.isEmpty && title.contains(normalizedQuery)
            let urlMatches = !strippedURL.isEmpty && !strippedQuery.isEmpty && strippedURL.hasPrefix(strippedQuery)
            guard titleMatches || urlMatches else {
                continue
            }
            
            matches.append(tab)
            if matches.count >= limit {
                break
            }
        }
        
        return matches
    }
    
    // MARK: - Tab Persistence
    
    private func insertTabsLocked(_ tabs: [PersistedTab], isPrivate: Bool) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO tabs (id, title, url, is_private, position)
            VALUES (?, ?, ?, ?, ?);
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        for (index, tab) in tabs.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(tab.id.uuidString, to: statement, at: 1)
            bind(tab.title, to: statement, at: 2)
            bindOptional(tab.url, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, isPrivate ? 1 : 0)
            sqlite3_bind_int64(statement, 5, Int64(index))
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Thumbnails
    
    private func loadThumbnailLocked(for tabID: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: thumbnailFileURL(for: tabID)) else {
            return nil
        }
        
        return UIImage(data: data)
    }
    
    private func pruneThumbCacheLocked(validTabIDs: Set<UUID>) {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: storage.thumbnailCacheDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for fileURL in fileURLs {
            guard let tabID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent),
                  validTabIDs.contains(tabID) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
        }
    }
    
    private func thumbnailFileURL(for tabID: UUID) -> URL {
        return storage.thumbnailCacheDirectoryURL
            .appendingPathComponent(tabID.uuidString, isDirectory: false)
            .appendingPathExtension("png")
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
    
    private func bindOptional(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        
        bind(value, to: statement, at: index)
    }
    
    private func string(from statement: OpaquePointer?, at index: Int32) -> String {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            return ""
        }
        
        return String(cString: rawValue)
    }
    
    private func optionalString(from statement: OpaquePointer?, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        
        return string(from: statement, at: index)
    }
}
