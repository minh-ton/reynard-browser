//
//  TabManagementStore.swift
//  Reynard
//
//  Created by Minh Ton on 4/4/26.
//

import Foundation
import GeckoView
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
        let createdAt: Date?
        let openerTabID: UUID?
        let tabSessionState: String?
        let thumbnail: UIImage?
        let isMuted: Bool
        let isPrivate: Bool
    }
    
    struct RecentlyClosedTabSnapshot {
        let id: UUID
        let title: String
        let url: String?
        let tabSessionState: String?
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
        let createdAt: Date?
        let openerTabID: UUID?
        let tabSessionState: String?
        let isMuted: Bool
    }
    
    private struct PersistedState {
        let selectedRegularTabID: UUID?
        let selectedPrivateTabID: UUID?
        let selectedTabMode: TabMode
        let lastTabOverview: LastTabOverview
    }
    
    private struct PersistedWindow {
        let id: UUID
        let sceneID: String?
        let selectedRegularTabID: UUID?
        let selectedPrivateTabID: UUID?
        let selectedTabMode: TabMode
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.TabManagementStore.Queue", qos: .userInitiated)
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private let recentlyClosedTabLimit = 20
    
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
    
    // MARK: - Windows
    
    func windowID(forSceneID sceneID: String) -> UUID {
        stateQueue.sync {
            if let window = fetchWindowLocked(sceneID: sceneID) {
                return window.id
            }
            
            if let window = fetchWindowLocked(sceneID: nil) {
                _ = linkWindowLocked(window.id, toSceneID: sceneID)
                return window.id
            }
            
            return insertWindowLocked(sceneID: sceneID)
        }
    }
    
    func createWindow(sceneID: String) -> UUID {
        stateQueue.sync {
            insertWindowLocked(sceneID: sceneID)
        }
    }
    
    func removeWindows(notMatchingSceneIDs sceneIDs: Set<String>, supportsMultipleScenes: Bool) {
        stateQueue.async {
            defer {
                self.pruneThumbCacheLocked(validTabIDs: self.fetchTabIDsLocked())
            }
            
            let windows = self.fetchWindowsLocked()
            let closedWindows = windows.filter { window in
                window.sceneID.map { !sceneIDs.contains($0) } ?? false
            }
            guard !closedWindows.isEmpty else {
                return
            }
            
            let replacesSingleSession = closedWindows.count == 1
            && sceneIDs.count == 1
            && (!supportsMultipleScenes || windows.count == 1)
            if replacesSingleSession,
               let sceneID = sceneIDs.first {
                _ = self.linkWindowLocked(closedWindows[0].id, toSceneID: sceneID)
                return
            }
            
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return
            }
            
            var privateTabIDs: [UUID] = []
            for window in closedWindows {
                for tab in self.fetchTabsLocked(windowID: window.id, isPrivate: false) {
                    if let url = URLUtils.restorableURL(from: tab.url) {
                        _ = self.insertRecentlyClosedTabLocked(
                            id: tab.id,
                            title: tab.title,
                            url: url,
                            tabSessionState: tab.tabSessionState
                        )
                    }
                }
                privateTabIDs += self.fetchTabsLocked(windowID: window.id, isPrivate: true).map(\.id)
                
                guard self.deleteWindowLocked(window.id) else {
                    _ = self.executeLocked("ROLLBACK TRANSACTION;")
                    return
                }
            }
            
            guard let expiredTabIDs = self.pruneRecentlyClosedTabsLocked(),
                  self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            DispatchQueue.main.async {
                (expiredTabIDs + privateTabIDs).forEach { tabID in
                    NavigationHistoryStore.shared.removeThumbnails(for: tabID)
                }
            }
            self.postRecentlyClosedTabsDidChange()
        }
    }
    
    // MARK: - Tabs
    
    func snapshot(forWindow windowID: UUID) -> Snapshot {
        stateQueue.sync {
            let window = fetchWindowLocked(id: windowID)
            return Snapshot(
                regularTabs: fetchTabsLocked(windowID: windowID, isPrivate: false),
                privateTabs: fetchTabsLocked(windowID: windowID, isPrivate: true),
                selectedRegularTabID: window?.selectedRegularTabID,
                selectedPrivateTabID: window?.selectedPrivateTabID,
                selectedTabMode: window?.selectedTabMode ?? .regular,
                lastTabOverview: persistedStateLocked().lastTabOverview
            )
        }
    }
    
    func persistTabs(
        windowID: UUID,
        regularTabs: [Tab],
        privateTabs: [Tab],
        selectedRegularTabID: UUID?,
        selectedPrivateTabID: UUID?,
        selectedTabMode: TabMode
    ) {
        let persistedRegularTabs = regularTabs.map {
            PersistedTab(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                createdAt: $0.createdAt,
                openerTabID: $0.state.openerTabID,
                tabSessionState: $0.state.tabSessionState?.serializedString(),
                isMuted: $0.isMuted
            )
        }
        let persistedPrivateTabs = privateTabs.map {
            PersistedTab(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                createdAt: $0.createdAt,
                openerTabID: nil,
                tabSessionState: nil,
                isMuted: $0.isMuted
            )
        }
        
        stateQueue.async {
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return
            }
            
            guard self.deleteTabsLocked(windowID: windowID),
                  self.saveWindowSelectionLocked(
                    windowID: windowID,
                    selectedRegularTabID: selectedRegularTabID,
                    selectedPrivateTabID: selectedPrivateTabID,
                    selectedTabMode: selectedTabMode
                  ),
                  self.insertTabsLocked(persistedRegularTabs, windowID: windowID, isPrivate: false),
                  self.insertTabsLocked(persistedPrivateTabs, windowID: windowID, isPrivate: true) else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
        }
    }
    
    func flushPendingWrites() {
        stateQueue.sync {}
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
    
    func recentlyClosedTabs(limit: Int) -> [RecentlyClosedTabSnapshot] {
        stateQueue.sync {
            fetchRecentlyClosedTabsLocked(limit: limit)
        }
    }
    
    func saveRecentlyClosedTab(id: UUID, title: String, url: String?, tabSessionState: String?) {
        stateQueue.async {
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return
            }
            
            guard self.insertRecentlyClosedTabLocked(
                id: id,
                title: title,
                url: url,
                tabSessionState: tabSessionState
            ) else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            guard let expiredTabIDs = self.pruneRecentlyClosedTabsLocked() else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return
            }
            
            DispatchQueue.main.async {
                expiredTabIDs.forEach { tabID in
                    NavigationHistoryStore.shared.removeThumbnails(for: tabID)
                }
            }
            self.postRecentlyClosedTabsDidChange()
        }
    }
    
    func takeRecentlyClosedTab(id: UUID) -> RecentlyClosedTabSnapshot? {
        stateQueue.sync {
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return nil
            }
            
            guard let snapshot = self.fetchRecentlyClosedTabLocked(id: id),
                  self.deleteRecentlyClosedTabLocked(id: id) else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return nil
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return nil
            }
            
            self.postRecentlyClosedTabsDidChange()
            return snapshot
        }
    }
    
    @discardableResult
    func removeRecentlyClosedTab(id: UUID) -> Bool {
        let didRemove = stateQueue.sync {
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return false
            }
            
            guard self.fetchRecentlyClosedTabLocked(id: id) != nil,
                  self.deleteRecentlyClosedTabLocked(id: id) else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return false
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return false
            }
            
            return true
        }
        
        guard didRemove else {
            return false
        }
        
        NavigationHistoryStore.shared.removeThumbnails(for: id)
        postRecentlyClosedTabsDidChange()
        return true
    }
    
    @discardableResult
    func clearRecentlyClosedTabs() -> Bool {
        let tabIDs = stateQueue.sync {
            guard self.executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
                return nil as [UUID]?
            }
            
            let tabIDs = self.fetchRecentlyClosedTabIDsLocked()
            guard self.deleteAllRecentlyClosedTabsLocked() else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return nil
            }
            
            guard self.executeLocked("COMMIT TRANSACTION;") else {
                _ = self.executeLocked("ROLLBACK TRANSACTION;")
                return nil
            }
            
            return tabIDs
        }
        
        guard let tabIDs else {
            return false
        }
        
        tabIDs.forEach { tabID in
            NavigationHistoryStore.shared.removeThumbnails(for: tabID)
        }
        postRecentlyClosedTabsDidChange()
        return true
    }
    
    private func postRecentlyClosedTabsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .recentlyClosedTabsDidChange, object: self)
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
            created_at REAL,
            opened_from TEXT,
            tab_session_state TEXT,
            is_muted INTEGER NOT NULL DEFAULT 0,
            is_private INTEGER NOT NULL,
            position INTEGER NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_tabs_private_position ON tabs(is_private, position ASC);
        
        CREATE TABLE IF NOT EXISTS windows (
            id TEXT PRIMARY KEY,
            scene_id TEXT,
            selected_regular_tab_id TEXT,
            selected_private_tab_id TEXT,
            selected_tab_mode TEXT NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS recently_closed_tabs (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT,
            tab_session_state TEXT
        );
        """
        
        _ = executeLocked(sql)
        ensureColumnLocked(name: "created_at", table: "tabs", definition: "REAL")
        ensureColumnLocked(name: "opened_from", table: "tabs", definition: "TEXT")
        ensureColumnLocked(name: "tab_session_state", table: "tabs", definition: "TEXT")
        ensureColumnLocked(name: "is_muted", table: "tabs", definition: "INTEGER NOT NULL DEFAULT 0")
        ensureColumnLocked(name: "tab_session_state", table: "recently_closed_tabs", definition: "TEXT")
        ensureColumnLocked(name: "window_id", table: "tabs", definition: "TEXT")
        _ = executeLocked("CREATE INDEX IF NOT EXISTS idx_tabs_window_position ON tabs(window_id, is_private, position ASC);")
        moveTabsWithoutWindowLocked()
    }
    
    // MARK: - Schema Migration
    
    private func ensureColumnLocked(name: String, table: String, definition: String) {
        guard let statement = prepareStatementLocked("PRAGMA table_info(\(table));") else {
            return
        }
        
        var hasColumn = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if string(from: statement, at: 1) == name {
                hasColumn = true
                break
            }
        }
        sqlite3_finalize(statement)
        
        guard !hasColumn else {
            return
        }
        
        _ = executeLocked("ALTER TABLE \(table) ADD COLUMN \(name) \(definition);")
    }
    
    private func moveTabsWithoutWindowLocked() {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO windows (id, scene_id, selected_regular_tab_id, selected_private_tab_id, selected_tab_mode)
            SELECT ?, NULL, selected_regular_tab_id, selected_private_tab_id, selected_tab_mode
            FROM tab_state
            WHERE id = 1
              AND EXISTS (SELECT 1 FROM tabs WHERE window_id IS NULL);
            """
        ) else {
            return
        }
        
        let windowID = UUID().uuidString
        bind(windowID, to: statement, at: 1)
        let didInsertWindow = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) > 0
        sqlite3_finalize(statement)
        
        guard didInsertWindow,
              let statement = prepareStatementLocked("UPDATE tabs SET window_id = ? WHERE window_id IS NULL;") else {
            return
        }
        
        bind(windowID, to: statement, at: 1)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
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
    
    // MARK: - Window Persistence
    
    private func fetchWindowLocked(sceneID: String?) -> PersistedWindow? {
        return fetchWindowsLocked().first { $0.sceneID == sceneID }
    }
    
    private func fetchWindowLocked(id: UUID) -> PersistedWindow? {
        return fetchWindowsLocked().first { $0.id == id }
    }
    
    private func fetchWindowsLocked() -> [PersistedWindow] {
        guard let statement = prepareStatementLocked(
            """
            SELECT id, scene_id, selected_regular_tab_id, selected_private_tab_id, selected_tab_mode
            FROM windows
            ORDER BY rowid ASC;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var windows: [PersistedWindow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(from: statement, at: 0)) else {
                continue
            }
            
            windows.append(
                PersistedWindow(
                    id: id,
                    sceneID: optionalString(from: statement, at: 1),
                    selectedRegularTabID: optionalString(from: statement, at: 2).flatMap { UUID(uuidString: $0) },
                    selectedPrivateTabID: optionalString(from: statement, at: 3).flatMap { UUID(uuidString: $0) },
                    selectedTabMode: TabMode(rawValue: string(from: statement, at: 4)) ?? .regular
                )
            )
        }
        
        return windows
    }
    
    private func insertWindowLocked(sceneID: String) -> UUID {
        let windowID = UUID()
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO windows (id, scene_id, selected_tab_mode)
            VALUES (?, ?, ?);
            """
        ) else {
            return windowID
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(windowID.uuidString, to: statement, at: 1)
        bind(sceneID, to: statement, at: 2)
        bind(TabMode.regular.rawValue, to: statement, at: 3)
        sqlite3_step(statement)
        return windowID
    }
    
    private func linkWindowLocked(_ windowID: UUID, toSceneID sceneID: String) -> Bool {
        guard let statement = prepareStatementLocked("UPDATE windows SET scene_id = ? WHERE id = ?;") else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(sceneID, to: statement, at: 1)
        bind(windowID.uuidString, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func saveWindowSelectionLocked(
        windowID: UUID,
        selectedRegularTabID: UUID?,
        selectedPrivateTabID: UUID?,
        selectedTabMode: TabMode
    ) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            UPDATE windows
            SET selected_regular_tab_id = ?, selected_private_tab_id = ?, selected_tab_mode = ?
            WHERE id = ?;
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
        bind(windowID.uuidString, to: statement, at: 4)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteWindowLocked(_ windowID: UUID) -> Bool {
        guard deleteTabsLocked(windowID: windowID),
              let statement = prepareStatementLocked("DELETE FROM windows WHERE id = ?;") else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(windowID.uuidString, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    // MARK: - Tab Queries
    
    private func fetchTabsLocked(windowID: UUID, isPrivate: Bool) -> [TabSnapshot] {
        guard let statement = prepareStatementLocked(
            """
            SELECT id, title, url, created_at, tab_session_state, is_muted, opened_from
            FROM tabs
            WHERE window_id = ? AND is_private = ?
            ORDER BY position ASC;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(windowID.uuidString, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, isPrivate ? 1 : 0)
        
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
                    createdAt: optionalDate(from: statement, at: 3),
                    openerTabID: optionalString(from: statement, at: 6).flatMap { UUID(uuidString: $0) },
                    tabSessionState: optionalString(from: statement, at: 4),
                    thumbnail: loadThumbnailLocked(for: id),
                    isMuted: sqlite3_column_int64(statement, 5) != 0,
                    isPrivate: isPrivate
                )
            )
        }
        
        return tabs
    }
    
    private func fetchTabIDsLocked() -> Set<UUID> {
        guard let statement = prepareStatementLocked("SELECT id FROM tabs;") else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var tabIDs = Set<UUID>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = UUID(uuidString: string(from: statement, at: 0)) {
                tabIDs.insert(id)
            }
        }
        
        return tabIDs
    }
    
    private func fetchRecentlyClosedTabsLocked(limit: Int) -> [RecentlyClosedTabSnapshot] {
        guard limit > 0,
              let statement = prepareStatementLocked(
                """
                SELECT id, title, url, tab_session_state
                FROM recently_closed_tabs
                ORDER BY rowid DESC
                LIMIT ?;
                """
              ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, Int64(limit))
        
        var tabs: [RecentlyClosedTabSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(from: statement, at: 0)) else {
                continue
            }
            
            tabs.append(
                RecentlyClosedTabSnapshot(
                    id: id,
                    title: string(from: statement, at: 1),
                    url: optionalString(from: statement, at: 2),
                    tabSessionState: optionalString(from: statement, at: 3)
                )
            )
        }
        
        return tabs
    }
    
    private func fetchRecentlyClosedTabLocked(id: UUID) -> RecentlyClosedTabSnapshot? {
        guard let statement = prepareStatementLocked(
            """
            SELECT id, title, url, tab_session_state
            FROM recently_closed_tabs
            WHERE id = ?
            LIMIT 1;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(id.uuidString, to: statement, at: 1)
        
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = UUID(uuidString: string(from: statement, at: 0)) else {
            return nil
        }
        
        return RecentlyClosedTabSnapshot(
            id: id,
            title: string(from: statement, at: 1),
            url: optionalString(from: statement, at: 2),
            tabSessionState: optionalString(from: statement, at: 3)
        )
    }
    
    private func fetchRecentlyClosedTabIDsLocked() -> [UUID] {
        guard let statement = prepareStatementLocked(
            """
            SELECT id
            FROM recently_closed_tabs;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var tabIDs: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(from: statement, at: 0)) else {
                continue
            }
            
            tabIDs.append(id)
        }
        
        return tabIDs
    }
    
    // MARK: - Tab Persistence
    
    private func deleteTabsLocked(windowID: UUID) -> Bool {
        guard let statement = prepareStatementLocked("DELETE FROM tabs WHERE window_id = ?;") else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(windowID.uuidString, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func insertTabsLocked(_ tabs: [PersistedTab], windowID: UUID, isPrivate: Bool) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT OR REPLACE INTO tabs (id, title, url, created_at, tab_session_state, is_muted, is_private, position, opened_from, window_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            bindOptional(tab.createdAt, to: statement, at: 4)
            bindOptional(tab.tabSessionState, to: statement, at: 5)
            sqlite3_bind_int64(statement, 6, tab.isMuted ? 1 : 0)
            sqlite3_bind_int64(statement, 7, isPrivate ? 1 : 0)
            sqlite3_bind_int64(statement, 8, Int64(index))
            bindOptional(tab.openerTabID?.uuidString, to: statement, at: 9)
            bind(windowID.uuidString, to: statement, at: 10)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        
        return true
    }
    
    private func insertRecentlyClosedTabLocked(
        id: UUID,
        title: String,
        url: String?,
        tabSessionState: String?
    ) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO recently_closed_tabs (id, title, url, tab_session_state)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                url = excluded.url,
                tab_session_state = excluded.tab_session_state;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(id.uuidString, to: statement, at: 1)
        bind(title, to: statement, at: 2)
        bindOptional(url, to: statement, at: 3)
        bindOptional(tabSessionState, to: statement, at: 4)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func pruneRecentlyClosedTabsLocked() -> [UUID]? {
        guard let statement = prepareStatementLocked(
            """
            SELECT id
            FROM recently_closed_tabs
            ORDER BY rowid DESC
            LIMIT -1 OFFSET ?;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, Int64(recentlyClosedTabLimit))
        
        var expiredTabIDs: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(from: statement, at: 0)) else {
                continue
            }
            
            expiredTabIDs.append(id)
        }
        
        for tabID in expiredTabIDs {
            guard deleteRecentlyClosedTabLocked(id: tabID) else {
                return nil
            }
        }
        
        return expiredTabIDs
    }
    
    private func deleteRecentlyClosedTabLocked(id: UUID) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            DELETE FROM recently_closed_tabs
            WHERE id = ?;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(id.uuidString, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteAllRecentlyClosedTabsLocked() -> Bool {
        return executeLocked("DELETE FROM recently_closed_tabs;")
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
    
    private func bindOptional(_ value: Date?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
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
    
    private func optionalDate(from statement: OpaquePointer?, at index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }
}
