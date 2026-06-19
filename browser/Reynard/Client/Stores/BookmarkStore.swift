//
//  BookmarkStore.swift
//  Reynard
//
//  Created by Minh Ton on 20/5/26.
//

import Foundation
import SQLite3

enum BookmarkNodeType: Int64 {
    case bookmark = 1
    case folder = 2
}

struct BookmarkSnapshot: Hashable {
    let id: Int64
    let guid: String
    let dateAdded: Date
    let parentGUID: String?
    let parentName: String?
    let title: String
    let url: URL
}

struct BookmarkFolderHierarchySnapshot {
    let parent: BookmarkFolderSnapshot
    let items: [BookmarkFolderSnapshot]
}

struct BookmarkFolderContentsSnapshot {
    let parent: BookmarkFolderSnapshot
    let items: [BookmarkContentSnapshot]
}

enum BookmarkContentSnapshot: Hashable {
    case folder(BookmarkFolderSnapshot)
    case bookmark(BookmarkSnapshot)
}

struct BookmarkFolderSnapshot: Hashable {
    let id: Int64
    let guid: String
    let dateAdded: Date
    let parentGUID: String?
    let parentName: String?
    let title: String
    let position: Int
    let childCount: Int
    let isProtected: Bool
}

final class BookmarkStore {
    static let shared = BookmarkStore()
    
    private enum Constants {
        static let databaseName = "Bookmarks"
        static let bookmarkTableName = "bookmarks"
        static let structureTableName = "bookmark_structure"
        static let rootFolderGUID = "root________"
        static let rootFolderTitle = "Bookmarks"
        static let favoritesFolderGUID = "favorites___"
        static let favoritesFolderTitle = "Favorites"
    }
    
    private static let defaultFavoriteBookmarks: [(title: String, urlString: String)] = [
        ("Apple", "https://www.apple.com/"),
        ("Google", "https://www.google.com/"),
        ("Facebook", "https://facebook.com/"),
        ("Reddit", "https://www.reddit.com/"),
        ("YouTube", "https://youtube.com/"),
        ("GitHub", "https://github.com/"),
        ("ChatGPT", "https://chatgpt.com/")
    ]
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }
    
    private struct FolderRecord {
        let guid: String
        let title: String
    }
    
    private struct PlacementRecord {
        let parentGUID: String
        let index: Int
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.BookmarkStore.Queue", qos: .userInitiated)
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
            .appendingPathComponent("Bookmarks", isDirectory: true)
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent(Constants.databaseName, isDirectory: false)
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
            let isEmptyDatabase = isBookmarkTableEmptyLocked()
            ensureRootFolderLocked()
            if isEmptyDatabase {
                seedDefaultBookmarksLocked()
            }
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
    
    // MARK: - Bookmarks
    
    func bookmarks(matchingPrefix query: String, limit: Int) -> [BookmarkSnapshot] {
        stateQueue.sync {
            searchBookmarksPrefixLocked(matching: query, limit: limit)
        }
    }
    
    func bookmarks(matching query: String, limit: Int) -> [BookmarkSnapshot] {
        stateQueue.sync {
            searchBookmarksLocked(matching: query, limit: limit)
        }
    }
    
    func bookmark(savedFor url: URL) -> BookmarkSnapshot? {
        stateQueue.sync {
            bookmarkSnapshotLocked(url: url)
        }
    }
    
    // MARK: - Folder Queries
    
    func childFolders(in parentGUID: String? = nil) -> BookmarkFolderHierarchySnapshot {
        stateQueue.sync {
            let requestedParentGUID = resolvedParentGUID(for: parentGUID)
            let parent = folderSnapshotLocked(guid: requestedParentGUID) ?? rootFolderSnapshotLocked()
            return BookmarkFolderHierarchySnapshot(
                parent: parent,
                items: fetchChildFoldersLocked(parentGUID: parent.guid)
            )
        }
    }
    
    func isSavedInFavorites(_ url: URL) -> Bool {
        stateQueue.sync {
            containsBookmarkLocked(url: url, inFolderHierarchyWithGUID: Constants.favoritesFolderGUID)
        }
    }
    
    func favoritesFolderHierarchy() -> BookmarkFolderHierarchySnapshot {
        stateQueue.sync {
            let parent = folderSnapshotLocked(guid: Constants.favoritesFolderGUID) ?? rootFolderSnapshotLocked()
            return BookmarkFolderHierarchySnapshot(
                parent: parent,
                items: fetchChildFoldersLocked(parentGUID: parent.guid)
            )
        }
    }
    
    func contents(of parentGUID: String? = nil) -> BookmarkFolderContentsSnapshot {
        stateQueue.sync {
            let requestedParentGUID = resolvedParentGUID(for: parentGUID)
            let parent = folderSnapshotLocked(guid: requestedParentGUID) ?? rootFolderSnapshotLocked()
            return BookmarkFolderContentsSnapshot(
                parent: parent,
                items: fetchFolderContentsLocked(parentGUID: parent.guid)
            )
        }
    }
    
    // MARK: - Bookmark Mutations
    
    @discardableResult
    func addBookmark(title: String, url: URL, to parentGUID: String? = nil) -> BookmarkSnapshot? {
        let normalizedTitle = bookmarkTitle(title, fallbackURL: url)
        guard URLUtils.isAbsoluteURL(url), !normalizedTitle.isEmpty else {
            return nil
        }
        
        return stateQueue.sync {
            guard let parent = folderRecordLocked(guid: resolvedParentGUID(for: parentGUID)) else {
                return nil
            }
            
            let guid = makeGUID()
            let timestamp = Date()
            let placementIndex = nextChildIndexLocked(parentGUID: parent.guid)
            
            guard beginTransactionLocked() else {
                return nil
            }
            
            guard insertNodeLocked(
                guid: guid,
                type: .bookmark,
                dateAdded: timestamp,
                parentGUID: parent.guid,
                parentName: parent.title,
                title: normalizedTitle,
                url: url
            ), insertStructureEntryLocked(parentGUID: parent.guid, childGUID: guid, index: placementIndex) else {
                rollbackTransactionLocked()
                return nil
            }
            
            guard commitTransactionLocked() else {
                rollbackTransactionLocked()
                return nil
            }
            
            let snapshot = bookmarkSnapshotLocked(guid: guid)
            postDidChange()
            return snapshot
        }
    }
    
    @discardableResult
    func updateBookmark(guid: String, title: String, url: URL, parentGUID: String? = nil) -> BookmarkSnapshot? {
        let normalizedTitle = bookmarkTitle(title, fallbackURL: url)
        guard URLUtils.isAbsoluteURL(url), !normalizedTitle.isEmpty else {
            return nil
        }
        
        return stateQueue.sync {
            guard nodeTypeLocked(guid: guid) == .bookmark,
                  let parent = folderRecordLocked(guid: resolvedParentGUID(for: parentGUID)) else {
                return nil
            }
            
            let currentPlacement = placementLocked(childGUID: guid)
            
            guard beginTransactionLocked() else {
                return nil
            }
            
            if currentPlacement?.parentGUID != parent.guid {
                if let currentPlacement {
                    guard deleteStructureEntryLocked(childGUID: guid),
                          compactStructureIndicesLocked(parentGUID: currentPlacement.parentGUID, afterRemovingIndex: currentPlacement.index) else {
                        rollbackTransactionLocked()
                        return nil
                    }
                }
                
                let newIndex = nextChildIndexLocked(parentGUID: parent.guid)
                guard insertStructureEntryLocked(parentGUID: parent.guid, childGUID: guid, index: newIndex) else {
                    rollbackTransactionLocked()
                    return nil
                }
            }
            
            guard updateBookmarkLocked(guid: guid, title: normalizedTitle, url: url, parentGUID: parent.guid, parentName: parent.title) else {
                rollbackTransactionLocked()
                return nil
            }
            
            guard commitTransactionLocked() else {
                rollbackTransactionLocked()
                return nil
            }
            
            let snapshot = bookmarkSnapshotLocked(guid: guid)
            postDidChange()
            return snapshot
        }
    }
    
    @discardableResult
    func removeBookmark(guid: String) -> Bool {
        stateQueue.sync {
            deleteItemLocked(guid: guid, expectedType: .bookmark)
        }
    }
    
    @discardableResult
    func moveBookmarkItem(guid: String, to index: Int, in parentGUID: String? = nil) -> Bool {
        stateQueue.sync {
            let resolvedFolderGUID = resolvedParentGUID(for: parentGUID)
            guard let placement = placementLocked(childGUID: guid),
                  placement.parentGUID == resolvedFolderGUID else {
                return false
            }
            
            var childGUIDs = orderedChildGUIDsLocked(parentGUID: resolvedFolderGUID)
            guard let currentIndex = childGUIDs.firstIndex(of: guid),
                  !childGUIDs.isEmpty else {
                return false
            }
            
            let targetIndex = max(0, min(index, childGUIDs.count - 1))
            let protectedLeadingCount = childGUIDs.prefix(while: isProtectedFolderGUID).count
            guard !isProtectedFolderGUID(guid),
                  targetIndex >= protectedLeadingCount else {
                return false
            }
            
            guard currentIndex != targetIndex else {
                return true
            }
            
            let movedGUID = childGUIDs.remove(at: currentIndex)
            childGUIDs.insert(movedGUID, at: targetIndex)
            
            guard beginTransactionLocked() else {
                return false
            }
            
            guard updateStructureOrderLocked(childGUIDs: childGUIDs, parentGUID: resolvedFolderGUID) else {
                rollbackTransactionLocked()
                return false
            }
            
            guard commitTransactionLocked() else {
                rollbackTransactionLocked()
                return false
            }
            
            postDidChange()
            return true
        }
    }
    
    // MARK: - Folder Mutations
    
    @discardableResult
    func addFolder(title: String, to parentGUID: String? = nil) -> BookmarkFolderSnapshot? {
        let normalizedTitle = normalizedFolderTitle(title)
        guard !normalizedTitle.isEmpty else {
            return nil
        }
        
        return stateQueue.sync {
            guard let parent = folderRecordLocked(guid: resolvedParentGUID(for: parentGUID)) else {
                return nil
            }
            
            let guid = makeGUID()
            let timestamp = Date()
            let placementIndex = nextChildIndexLocked(parentGUID: parent.guid)
            
            guard beginTransactionLocked() else {
                return nil
            }
            
            guard insertNodeLocked(
                guid: guid,
                type: .folder,
                dateAdded: timestamp,
                parentGUID: parent.guid,
                parentName: parent.title,
                title: normalizedTitle,
                url: nil
            ), insertStructureEntryLocked(parentGUID: parent.guid, childGUID: guid, index: placementIndex) else {
                rollbackTransactionLocked()
                return nil
            }
            
            guard commitTransactionLocked() else {
                rollbackTransactionLocked()
                return nil
            }
            
            let snapshot = folderSnapshotLocked(guid: guid)
            postDidChange()
            return snapshot
        }
    }
    
    @discardableResult
    func removeFolder(guid: String) -> Bool {
        guard !isProtectedFolderGUID(guid) else {
            return false
        }
        
        return stateQueue.sync {
            deleteItemLocked(guid: guid, expectedType: .folder)
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
            assertionFailure("Failed to open Bookmarks database")
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
  CREATE TABLE IF NOT EXISTS \(Constants.bookmarkTableName) (
   id INTEGER PRIMARY KEY AUTOINCREMENT,
   guid TEXT NOT NULL UNIQUE,
   type TINYINT NOT NULL,
   date_added REAL NOT NULL,
   parentid TEXT REFERENCES \(Constants.bookmarkTableName)(guid) ON DELETE CASCADE,
   parentName TEXT,
   title TEXT,
   url TEXT,
   host TEXT NOT NULL DEFAULT '',
   stripped_url TEXT NOT NULL DEFAULT ''
  );
  
  CREATE TABLE IF NOT EXISTS \(Constants.structureTableName) (
   parent TEXT NOT NULL REFERENCES \(Constants.bookmarkTableName)(guid) ON DELETE CASCADE,
   child TEXT NOT NULL UNIQUE REFERENCES \(Constants.bookmarkTableName)(guid) ON DELETE CASCADE,
   idx INTEGER NOT NULL,
   PRIMARY KEY(parent, child),
   UNIQUE(parent, idx)
  );
  
  CREATE INDEX IF NOT EXISTS idx_bookmarks_parent_type_date ON \(Constants.bookmarkTableName)(parentid, type, date_added DESC, id DESC);
  CREATE INDEX IF NOT EXISTS idx_bookmarks_type_date ON \(Constants.bookmarkTableName)(type, date_added DESC, id DESC);
  CREATE INDEX IF NOT EXISTS idx_bookmarks_host_date ON \(Constants.bookmarkTableName)(type, host, date_added DESC, id DESC);
  CREATE INDEX IF NOT EXISTS idx_bookmarks_stripped_url_date ON \(Constants.bookmarkTableName)(type, stripped_url, date_added DESC, id DESC);
  CREATE INDEX IF NOT EXISTS idx_structure_parent_idx ON \(Constants.structureTableName)(parent, idx ASC);
  """
        
        _ = executeLocked(sql)
    }
    
    private func ensureRootFolderLocked() {
        guard folderRecordLocked(guid: Constants.rootFolderGUID) == nil else {
            return
        }
        
        let createdAt = Date(timeIntervalSince1970: 0)
        _ = insertNodeLocked(
            guid: Constants.rootFolderGUID,
            type: .folder,
            dateAdded: createdAt,
            parentGUID: nil,
            parentName: nil,
            title: Constants.rootFolderTitle,
            url: nil
        )
    }
    
    private func seedDefaultBookmarksLocked() {
        guard let rootFolder = folderRecordLocked(guid: Constants.rootFolderGUID) else {
            return
        }
        
        let createdAt = Date()
        
        guard beginTransactionLocked() else {
            return
        }
        
        guard insertNodeLocked(
            guid: Constants.favoritesFolderGUID,
            type: .folder,
            dateAdded: createdAt,
            parentGUID: rootFolder.guid,
            parentName: rootFolder.title,
            title: Constants.favoritesFolderTitle,
            url: nil
        ), insertStructureEntryLocked(parentGUID: rootFolder.guid, childGUID: Constants.favoritesFolderGUID, index: 0) else {
            rollbackTransactionLocked()
            return
        }
        
        for (index, bookmark) in Self.defaultFavoriteBookmarks.enumerated() {
            guard let url = URL(string: bookmark.urlString) else {
                rollbackTransactionLocked()
                return
            }
            
            let bookmarkGUID = makeGUID()
            guard insertNodeLocked(
                guid: bookmarkGUID,
                type: .bookmark,
                dateAdded: createdAt,
                parentGUID: Constants.favoritesFolderGUID,
                parentName: Constants.favoritesFolderTitle,
                title: bookmark.title,
                url: url
            ), insertStructureEntryLocked(parentGUID: Constants.favoritesFolderGUID, childGUID: bookmarkGUID, index: index) else {
                rollbackTransactionLocked()
                return
            }
        }
        
        guard commitTransactionLocked() else {
            rollbackTransactionLocked()
            return
        }
    }
    
    // MARK: - Search
    
    private func searchBookmarksPrefixLocked(matching query: String, limit: Int) -> [BookmarkSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }
        
        let escapedTitlePrefix = "\(escapedLikePattern(normalizedQuery))%"
        let escapedURLPrefix = "\(escapedLikePattern(URLUtils.normalizedURLStringForMatching(from: normalizedQuery)))%"
        
        guard let statement = prepareStatementLocked(
   """
   SELECT id, guid, date_added, parentid, parentName, title, url
   FROM \(Constants.bookmarkTableName)
   WHERE type = ?
     AND (
       title LIKE ? COLLATE NOCASE ESCAPE '\\'
       OR stripped_url LIKE ? COLLATE NOCASE ESCAPE '\\'
     )
   ORDER BY date_added DESC, id DESC
   LIMIT ?;
   """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, BookmarkNodeType.bookmark.rawValue)
        bind(escapedTitlePrefix, to: statement, at: 2)
        bind(escapedURLPrefix, to: statement, at: 3)
        sqlite3_bind_int64(statement, 4, Int64(limit))
        return readBookmarkSnapshotsLocked(from: statement)
    }
    
    private func searchBookmarksLocked(matching query: String, limit: Int) -> [BookmarkSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }
        
        var results: [BookmarkSnapshot] = []
        var seenGUIDs = Set<String>()
        
        for item in heuristicMatchesLocked(matching: normalizedQuery, limit: min(limit, 4)) {
            if seenGUIDs.insert(item.guid).inserted {
                results.append(item)
            }
        }
        
        let remaining = max(0, limit - results.count)
        guard remaining > 0 else {
            return results
        }
        
        for item in rankedMatchesLocked(matching: normalizedQuery, limit: remaining) {
            if seenGUIDs.insert(item.guid).inserted {
                results.append(item)
            }
        }
        
        return results
    }
    
    private func heuristicMatchesLocked(matching query: String, limit: Int) -> [BookmarkSnapshot] {
        if isHostOnlyQuery(query) {
            let upperBound = query + "\u{FFFF}"
            guard let statement = prepareStatementLocked(
    """
    SELECT id, guid, date_added, parentid, parentName, title, url
    FROM \(Constants.bookmarkTableName)
    WHERE type = ?
      AND host >= ?
      AND host < ?
    ORDER BY date_added DESC, id DESC
    LIMIT ?;
    """
            ) else {
                return []
            }
            
            defer {
                sqlite3_finalize(statement)
            }
            
            sqlite3_bind_int64(statement, 1, BookmarkNodeType.bookmark.rawValue)
            bind(query.lowercased(), to: statement, at: 2)
            bind(upperBound.lowercased(), to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, Int64(limit))
            return readBookmarkSnapshotsLocked(from: statement)
        }
        
        guard query.contains("/") || query.contains(":") || query.contains("?") else {
            return []
        }
        
        let urlComponents = URLUtils.urlMatchComponents(from: query)
        guard !urlComponents.hostAndPort.isEmpty else {
            return []
        }
        
        let normalizedHost = urlComponents.hostAndPort.lowercased()
        let strippedPrefix = normalizedHost + urlComponents.suffix
        let upperBound = strippedPrefix + "\u{FFFF}"
        guard let statement = prepareStatementLocked(
   """
   SELECT id, guid, date_added, parentid, parentName, title, url
   FROM \(Constants.bookmarkTableName)
   WHERE type = ?
     AND (host = ? OR host = 'www.' || ?)
     AND stripped_url >= ?
     AND stripped_url < ?
   ORDER BY date_added DESC, id DESC
   LIMIT ?;
   """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, BookmarkNodeType.bookmark.rawValue)
        bind(normalizedHost, to: statement, at: 2)
        bind(normalizedHost, to: statement, at: 3)
        bind(strippedPrefix, to: statement, at: 4)
        bind(upperBound, to: statement, at: 5)
        sqlite3_bind_int64(statement, 6, Int64(limit))
        return readBookmarkSnapshotsLocked(from: statement)
    }
    
    // MARK: - Bookmark Lookup
    
    private func bookmarkSnapshotLocked(url: URL) -> BookmarkSnapshot? {
        let urlString = url.absoluteString
        guard let statement = prepareStatementLocked(
   """
   SELECT id, guid, date_added, parentid, parentName, title, url
   FROM \(Constants.bookmarkTableName)
   WHERE type = ?
     AND (url = ? OR stripped_url = ?)
   ORDER BY date_added DESC, id DESC
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, BookmarkNodeType.bookmark.rawValue)
        bind(urlString, to: statement, at: 2)
        bind(URLUtils.normalizedURLStringForMatching(from: urlString), to: statement, at: 3)
        return readBookmarkSnapshotsLocked(from: statement).first
    }
    
    private func containsBookmarkLocked(url: URL, inFolderHierarchyWithGUID folderGUID: String) -> Bool {
        let urlString = url.absoluteString
        guard let statement = prepareStatementLocked(
   """
   WITH RECURSIVE descendants(guid) AS (
    SELECT ?
    UNION ALL
    SELECT s.child
    FROM \(Constants.structureTableName) AS s
    JOIN descendants AS d ON s.parent = d.guid
   )
   SELECT 1
   FROM \(Constants.bookmarkTableName) AS b
   JOIN descendants AS d ON d.guid = b.guid
   WHERE b.type = ?
     AND (b.url = ? OR b.stripped_url = ?)
   LIMIT 1;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(folderGUID, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, BookmarkNodeType.bookmark.rawValue)
        bind(urlString, to: statement, at: 3)
        bind(URLUtils.normalizedURLStringForMatching(from: urlString), to: statement, at: 4)
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    private func rankedMatchesLocked(matching query: String, limit: Int) -> [BookmarkSnapshot] {
        let tokens = query
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        
        guard !tokens.isEmpty else {
            return []
        }
        
        let conditions = Array(
            repeating: "(title LIKE ? COLLATE NOCASE OR url LIKE ? COLLATE NOCASE OR stripped_url LIKE ? COLLATE NOCASE OR host LIKE ? COLLATE NOCASE)",
            count: tokens.count
        ).joined(separator: " AND ")
        let sql = """
  SELECT id, guid, date_added, parentid, parentName, title, url
  FROM \(Constants.bookmarkTableName)
  WHERE type = ?
    AND \(conditions)
  ORDER BY date_added DESC, id DESC
  LIMIT ?;
  """
        
        guard let statement = prepareStatementLocked(sql) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, BookmarkNodeType.bookmark.rawValue)
        
        var bindIndex: Int32 = 2
        for token in tokens {
            let escapedToken = escapedLikePattern(token)
            bind("%\(escapedToken)%", to: statement, at: bindIndex)
            bind("%\(escapedToken)%", to: statement, at: bindIndex + 1)
            bind("%\(escapedToken)%", to: statement, at: bindIndex + 2)
            bind("\(escapedToken)%", to: statement, at: bindIndex + 3)
            bindIndex += 4
        }
        
        sqlite3_bind_int64(statement, bindIndex, Int64(limit))
        return readBookmarkSnapshotsLocked(from: statement)
    }
    
    // MARK: - Folder Lookup
    
    private func fetchChildFoldersLocked(parentGUID: String) -> [BookmarkFolderSnapshot] {
        guard let statement = prepareStatementLocked(
   """
   SELECT b.id, b.guid, b.date_added, b.parentid, b.parentName, b.title, s.idx,
       (
        SELECT COUNT(*)
        FROM \(Constants.structureTableName) AS nested
        JOIN \(Constants.bookmarkTableName) AS child ON child.guid = nested.child
        WHERE nested.parent = b.guid
       ) AS child_count
   FROM \(Constants.structureTableName) AS s
   JOIN \(Constants.bookmarkTableName) AS b ON b.guid = s.child
   WHERE s.parent = ?
     AND b.type = ?
   ORDER BY s.idx ASC;
   """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, BookmarkNodeType.folder.rawValue)
        return readFolderSnapshotsLocked(from: statement)
    }
    
    private func fetchFolderContentsLocked(parentGUID: String) -> [BookmarkContentSnapshot] {
        guard let statement = prepareStatementLocked(
   """
   SELECT b.id, b.guid, b.type, b.date_added, b.parentid, b.parentName, b.title, b.url, s.idx,
          (
       SELECT COUNT(*)
       FROM \(Constants.structureTableName) AS nested
       JOIN \(Constants.bookmarkTableName) AS child ON child.guid = nested.child
       WHERE nested.parent = b.guid
          ) AS child_count
   FROM \(Constants.structureTableName) AS s
   JOIN \(Constants.bookmarkTableName) AS b ON b.guid = s.child
   WHERE s.parent = ?
   ORDER BY s.idx ASC;
   """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        return readContentSnapshotsLocked(from: statement)
    }
    
    // MARK: - Record Lookup
    
    private func rootFolderSnapshotLocked() -> BookmarkFolderSnapshot {
        folderSnapshotLocked(guid: Constants.rootFolderGUID) ?? BookmarkFolderSnapshot(
            id: 0,
            guid: Constants.rootFolderGUID,
            dateAdded: Date(timeIntervalSince1970: 0),
            parentGUID: nil,
            parentName: nil,
            title: Constants.rootFolderTitle,
            position: 0,
            childCount: 0,
            isProtected: true
        )
    }
    
    private func bookmarkSnapshotLocked(guid: String) -> BookmarkSnapshot? {
        guard let statement = prepareStatementLocked(
   """
   SELECT id, guid, date_added, parentid, parentName, title, url
   FROM \(Constants.bookmarkTableName)
   WHERE guid = ?
     AND type = ?
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, BookmarkNodeType.bookmark.rawValue)
        return readBookmarkSnapshotsLocked(from: statement).first
    }
    
    private func folderSnapshotLocked(guid: String) -> BookmarkFolderSnapshot? {
        guard let statement = prepareStatementLocked(
   """
   SELECT b.id, b.guid, b.date_added, b.parentid, b.parentName, b.title,
       COALESCE(s.idx, 0),
       (
        SELECT COUNT(*)
        FROM \(Constants.structureTableName) AS nested
        JOIN \(Constants.bookmarkTableName) AS child ON child.guid = nested.child
        WHERE nested.parent = b.guid
       ) AS child_count
   FROM \(Constants.bookmarkTableName) AS b
   LEFT JOIN \(Constants.structureTableName) AS s ON s.child = b.guid
   WHERE b.guid = ?
     AND b.type = ?
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, BookmarkNodeType.folder.rawValue)
        return readFolderSnapshotsLocked(from: statement).first
    }
    
    private func folderRecordLocked(guid: String) -> FolderRecord? {
        guard let statement = prepareStatementLocked(
   """
   SELECT guid, title
   FROM \(Constants.bookmarkTableName)
   WHERE guid = ?
     AND type = ?
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, BookmarkNodeType.folder.rawValue)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return FolderRecord(
            guid: string(from: statement, at: 0),
            title: string(from: statement, at: 1)
        )
    }
    
    private func placementLocked(childGUID: String) -> PlacementRecord? {
        guard let statement = prepareStatementLocked(
   """
   SELECT parent, idx
   FROM \(Constants.structureTableName)
   WHERE child = ?
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(childGUID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return PlacementRecord(
            parentGUID: string(from: statement, at: 0),
            index: Int(sqlite3_column_int64(statement, 1))
        )
    }
    
    private func nextChildIndexLocked(parentGUID: String) -> Int {
        guard let statement = prepareStatementLocked(
   """
   SELECT COALESCE(MAX(idx), -1) + 1
   FROM \(Constants.structureTableName)
   WHERE parent = ?;
   """
        ) else {
            return 0
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    private func orderedChildGUIDsLocked(parentGUID: String) -> [String] {
        guard let statement = prepareStatementLocked(
   """
   SELECT child
   FROM \(Constants.structureTableName)
   WHERE parent = ?
   ORDER BY idx ASC;
   """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        
        var childGUIDs: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            childGUIDs.append(string(from: statement, at: 0))
        }
        
        return childGUIDs
    }
    
    // MARK: - Record Mutations
    
    private func insertNodeLocked(
        guid: String,
        type: BookmarkNodeType,
        dateAdded: Date,
        parentGUID: String?,
        parentName: String?,
        title: String,
        url: URL?
    ) -> Bool {
        let urlString = url?.absoluteString
        guard let statement = prepareStatementLocked(
   """
   INSERT INTO \(Constants.bookmarkTableName) (guid, type, date_added, parentid, parentName, title, url, host, stripped_url)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, type.rawValue)
        sqlite3_bind_double(statement, 3, dateAdded.timeIntervalSince1970)
        bindOptional(parentGUID, to: statement, at: 4)
        bindOptional(parentName, to: statement, at: 5)
        bind(title, to: statement, at: 6)
        bindOptional(urlString, to: statement, at: 7)
        bind(url?.host?.lowercased() ?? "", to: statement, at: 8)
        bind(URLUtils.normalizedURLStringForMatching(from: urlString ?? ""), to: statement, at: 9)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func insertStructureEntryLocked(parentGUID: String, childGUID: String, index: Int) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   INSERT INTO \(Constants.structureTableName) (parent, child, idx)
   VALUES (?, ?, ?);
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        bind(childGUID, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, Int64(index))
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func updateBookmarkLocked(guid: String, title: String, url: URL, parentGUID: String, parentName: String) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   UPDATE \(Constants.bookmarkTableName)
   SET parentid = ?,
    parentName = ?,
    title = ?,
    url = ?,
    host = ?,
    stripped_url = ?
   WHERE guid = ?
     AND type = ?;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        bind(parentName, to: statement, at: 2)
        bind(title, to: statement, at: 3)
        bind(url.absoluteString, to: statement, at: 4)
        bind(url.host?.lowercased() ?? "", to: statement, at: 5)
        bind(URLUtils.normalizedURLStringForMatching(from: url.absoluteString), to: statement, at: 6)
        bind(guid, to: statement, at: 7)
        sqlite3_bind_int64(statement, 8, BookmarkNodeType.bookmark.rawValue)
        
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteNodeLocked(guid: String, expectedType: BookmarkNodeType) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   DELETE FROM \(Constants.bookmarkTableName)
   WHERE guid = ?
     AND type = ?;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, expectedType.rawValue)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }
        
        return sqlite3_changes(database) > 0
    }
    
    private func deleteStructureEntryLocked(childGUID: String) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   DELETE FROM \(Constants.structureTableName)
   WHERE child = ?;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(childGUID, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteItemLocked(guid: String, expectedType: BookmarkNodeType) -> Bool {
        guard nodeTypeLocked(guid: guid) == expectedType else {
            return false
        }
        
        guard beginTransactionLocked() else {
            return false
        }
        
        let placement = placementLocked(childGUID: guid)
        if placement != nil,
           !deleteStructureEntryLocked(childGUID: guid) {
            rollbackTransactionLocked()
            return false
        }
        
        guard deleteNodeLocked(guid: guid, expectedType: expectedType) else {
            rollbackTransactionLocked()
            return false
        }
        
        if let placement,
           !compactStructureIndicesLocked(parentGUID: placement.parentGUID, afterRemovingIndex: placement.index) {
            rollbackTransactionLocked()
            return false
        }
        
        guard commitTransactionLocked() else {
            rollbackTransactionLocked()
            return false
        }
        
        postDidChange()
        return true
    }
    
    private func compactStructureIndicesLocked(parentGUID: String, afterRemovingIndex removedIndex: Int) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   UPDATE \(Constants.structureTableName)
   SET idx = idx - 1
   WHERE parent = ?
     AND idx > ?;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(parentGUID, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(removedIndex))
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func updateStructureOrderLocked(childGUIDs: [String], parentGUID: String) -> Bool {
        guard let statement = prepareStatementLocked(
   """
   UPDATE \(Constants.structureTableName)
   SET idx = ?
   WHERE parent = ?
     AND child = ?;
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        for (index, childGUID) in childGUIDs.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, Int64(-(index + 1)))
            bind(parentGUID, to: statement, at: 2)
            bind(childGUID, to: statement, at: 3)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        
        for (index, childGUID) in childGUIDs.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, Int64(index))
            bind(parentGUID, to: statement, at: 2)
            bind(childGUID, to: statement, at: 3)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Snapshot Decoding
    
    private func readBookmarkSnapshotsLocked(from statement: OpaquePointer?) -> [BookmarkSnapshot] {
        var items: [BookmarkSnapshot] = []
        
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let urlString = string(from: statement, at: 6)
                guard let url = URL(string: urlString), URLUtils.isAbsoluteURL(url) else {
                    continue
                }
                
                items.append(
                    BookmarkSnapshot(
                        id: sqlite3_column_int64(statement, 0),
                        guid: string(from: statement, at: 1),
                        dateAdded: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        parentGUID: optionalString(from: statement, at: 3),
                        parentName: optionalString(from: statement, at: 4),
                        title: string(from: statement, at: 5),
                        url: url
                    )
                )
            case SQLITE_DONE:
                return items
            default:
                return []
            }
        }
    }
    
    private func readFolderSnapshotsLocked(from statement: OpaquePointer?) -> [BookmarkFolderSnapshot] {
        var items: [BookmarkFolderSnapshot] = []
        
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                items.append(
                    BookmarkFolderSnapshot(
                        id: sqlite3_column_int64(statement, 0),
                        guid: string(from: statement, at: 1),
                        dateAdded: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        parentGUID: optionalString(from: statement, at: 3),
                        parentName: optionalString(from: statement, at: 4),
                        title: string(from: statement, at: 5),
                        position: Int(sqlite3_column_int64(statement, 6)),
                        childCount: Int(sqlite3_column_int64(statement, 7)),
                        isProtected: isProtectedFolderGUID(string(from: statement, at: 1))
                    )
                )
            case SQLITE_DONE:
                return items
            default:
                return []
            }
        }
    }
    
    private func readContentSnapshotsLocked(from statement: OpaquePointer?) -> [BookmarkContentSnapshot] {
        var items: [BookmarkContentSnapshot] = []
        
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let type = BookmarkNodeType(rawValue: sqlite3_column_int64(statement, 2))
                switch type {
                case .folder:
                    let guid = string(from: statement, at: 1)
                    items.append(
                        .folder(
                            BookmarkFolderSnapshot(
                                id: sqlite3_column_int64(statement, 0),
                                guid: guid,
                                dateAdded: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                                parentGUID: optionalString(from: statement, at: 4),
                                parentName: optionalString(from: statement, at: 5),
                                title: string(from: statement, at: 6),
                                position: Int(sqlite3_column_int64(statement, 8)),
                                childCount: Int(sqlite3_column_int64(statement, 9)),
                                isProtected: isProtectedFolderGUID(guid)
                            )
                        )
                    )
                case .bookmark:
                    let urlString = string(from: statement, at: 7)
                    guard let url = URL(string: urlString), URLUtils.isAbsoluteURL(url) else {
                        continue
                    }
                    
                    items.append(
                        .bookmark(
                            BookmarkSnapshot(
                                id: sqlite3_column_int64(statement, 0),
                                guid: string(from: statement, at: 1),
                                dateAdded: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                                parentGUID: optionalString(from: statement, at: 4),
                                parentName: optionalString(from: statement, at: 5),
                                title: string(from: statement, at: 6),
                                url: url
                            )
                        )
                    )
                case nil:
                    continue
                }
            case SQLITE_DONE:
                return items
            default:
                return []
            }
        }
    }
    
    private func nodeTypeLocked(guid: String) -> BookmarkNodeType? {
        guard let statement = prepareStatementLocked(
   """
   SELECT type
   FROM \(Constants.bookmarkTableName)
   WHERE guid = ?
   LIMIT 1;
   """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(guid, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return BookmarkNodeType(rawValue: sqlite3_column_int64(statement, 0))
    }
    
    private func isBookmarkTableEmptyLocked() -> Bool {
        guard let statement = prepareStatementLocked(
   """
   SELECT COUNT(*)
   FROM \(Constants.bookmarkTableName);
   """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return false
        }
        
        return sqlite3_column_int64(statement, 0) == 0
    }
    
    // MARK: - Transactions
    
    private func isProtectedFolderGUID(_ guid: String) -> Bool {
        return guid == Constants.rootFolderGUID || guid == Constants.favoritesFolderGUID
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
    
    // MARK: - Helpers
    
    private func bookmarkTitle(_ title: String, fallbackURL: URL) -> String {
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
    
    private func normalizedFolderTitle(_ title: String) -> String {
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func resolvedParentGUID(for parentGUID: String?) -> String {
        guard let parentGUID,
              !parentGUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Constants.rootFolderGUID
        }
        
        return parentGUID
    }
    
    private func escapedLikePattern(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
    
    private func makeGUID() -> String {
        return UUID().uuidString.lowercased()
    }
    
    private func postDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bookmarkStoreDidChange, object: self)
        }
    }
}
