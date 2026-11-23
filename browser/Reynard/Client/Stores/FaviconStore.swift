//
//  FaviconStore.swift
//  Reynard
//
//  Created by Minh Ton on 23/4/26.
//

import CryptoKit
import Darwin
import Foundation
import ObjectiveC.runtime
import SQLite3
import UIKit

final class FaviconStore {
    private typealias TransparencyAnalysisFunction = @convention(c) (AnyObject, Selector) -> Int
    
    struct FaviconPresentation {
        let image: UIImage
        let shouldInset: Bool
    }
    
    static let shared = FaviconStore()
    
    private static let expirationDays = 30
    private static let databaseName = "Favicons"
    private static let imageFilePrefix = "img-"
    private static let maxHTMLBytes = 768 * 1024
    private static let maxImageBytes = 2 * 1024 * 1024
    private static let maxRedirectDepth = 3
    private static let minimumTouchIconSideLength = 57
    private static let safariSharedUIFramework = dlopen(
        "/System/Library/PrivateFrameworks/SafariSharedUI.framework/SafariSharedUI",
        RTLD_LAZY
    )
    private static let transparencyAnalysisSelector = NSSelectorFromString("safari_transparencyAnalysisResult")
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }
    
    private struct SiteAssociation {
        let scopeKey: String
        let imageKey: String
    }
    
    private struct HTMLDocument {
        let html: String
        let url: URL
    }
    
    private enum IconKind {
        case favicon
        case touch
        case touchPrecomposed
        
        var isTouchIcon: Bool {
            return self != .favicon
        }
    }
    
    private struct IconCandidate {
        let url: URL
        let kind: IconKind
        let declaredSize: Int
        let documentOrder: Int
    }
    
    private struct FetchCandidate {
        let url: URL
        let requiresTouchIconSize: Bool
    }
    
    private struct ManifestIcon {
        let url: URL
        let declaredSize: Int
        let purposes: Set<String>
        let documentOrder: Int
    }
    
    private struct RemoteImage {
        let image: UIImage
        let data: Data
        let url: URL
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.FaviconStore.Queue", qos: .utility)
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
    private lazy var metadataUserAgent: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let operatingSystemVersion = "\(version.majorVersion)_\(version.minorVersion)"
        let safariVersion = "\(version.majorVersion).\(version.minorVersion)"
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad; CPU OS" : "iPhone; CPU iPhone OS"
        return "Mozilla/5.0 (\(device) \(operatingSystemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }()
    
    private lazy var linkTagExpression = try! NSRegularExpression(
        pattern: "(?is)<link\\b[^>]*>",
        options: []
    )
    private lazy var metaTagExpression = try! NSRegularExpression(
        pattern: "(?is)<meta\\b[^>]*>",
        options: []
    )
    private lazy var attributeExpression = try! NSRegularExpression(
        pattern: "(?is)([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
        options: []
    )
    
    private var activeRequests: [String: Task<UIImage?, Never>] = [:]
    
    // MARK: - Lifecycle
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
        
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent(Self.databaseName, isDirectory: false)
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
            pruneExpiredEntriesLocked(now: Date())
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
    
    // MARK: - Favicons
    
    func cachedFavicon(for pageURL: URL) -> UIImage? {
        stateQueue.sync {
            cachedAssociationImageLocked(for: pageURL, now: Date())?.image
        }
    }
    
    func cachedFavicon(for pageURLString: String?) -> UIImage? {
        guard let pageURL = URLUtils.webURL(from: pageURLString) else {
            return nil
        }
        
        return cachedFavicon(for: pageURL)
    }
    
    func cachedFaviconPresentation(for pageURL: URL) -> FaviconPresentation? {
        stateQueue.sync {
            guard let cached = cachedAssociationImageLocked(for: pageURL, now: Date()) else {
                return nil
            }
            
            let analysisResult = transparencyAnalysisResultLocked(
                for: cached.image,
                imageKey: cached.association.imageKey
            )
            return FaviconPresentation(
                image: cached.image,
                shouldInset: Self.shouldInsetIcon(forTransparencyAnalysisResult: analysisResult)
            )
        }
    }
    
    func faviconPresentation(for image: UIImage) -> FaviconPresentation {
        let analysisResult = Self.transparencyAnalysisResult(for: image)
        return FaviconPresentation(
            image: image,
            shouldInset: Self.shouldInsetIcon(forTransparencyAnalysisResult: analysisResult)
        )
    }
    
    func favicon(for pageURL: URL) async -> UIImage? {
        guard URLUtils.isWebURL(pageURL) else {
            return nil
        }
        
        if let cachedImage = cachedFavicon(for: pageURL) {
            return cachedImage
        }
        
        let requestKey = requestScopeKey(for: pageURL)
        if let activeRequest = stateQueue.sync(execute: { activeRequests[requestKey] }) {
            return await activeRequest.value
        }
        
        let task = Task<UIImage?, Never>(priority: .utility) { [weak self] in
            guard let self else {
                return nil
            }
            
            let image = await self.fetchAndCacheFavicon(for: pageURL)
            self.stateQueue.async {
                self.activeRequests[requestKey] = nil
            }
            return image
        }
        
        stateQueue.sync {
            activeRequests[requestKey] = task
        }
        return await task.value
    }
    
    func favicon(for pageURL: URL, webAppManifest: Any) async -> UIImage? {
        let manifestURLs = manifestIconURLs(from: webAppManifest, baseURL: pageURL)
        let candidates = manifestURLs.map {
            FetchCandidate(url: $0, requiresTouchIconSize: true)
        }
        
        if let image = await fetchAndCacheFirstCandidate(candidates, for: pageURL) {
            return image
        }
        return await favicon(for: pageURL)
    }
    
    func clearCache() {
        stateQueue.async {
            self.activeRequests.values.forEach { $0.cancel() }
            self.activeRequests.removeAll()
            
            let imageKeys = self.fetchImageKeysLocked()
            _ = self.executeLocked(
                """
                DELETE FROM favicon_associations;
                DELETE FROM favicon_sources;
                DELETE FROM favicon_images;
                """
            )
            
            for imageKey in imageKeys {
                let imageURL = self.imageFileURL(for: imageKey)
                if self.fileManager.fileExists(atPath: imageURL.path) {
                    try? self.fileManager.removeItem(at: imageURL)
                }
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
            assertionFailure("Failed to open Favicons database")
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
        CREATE TABLE IF NOT EXISTS favicon_images (
            image_key TEXT PRIMARY KEY,
            updated_at REAL NOT NULL,
            transparency_analysis_result INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS favicon_sources (
            source_url TEXT PRIMARY KEY,
            image_key TEXT NOT NULL REFERENCES favicon_images(image_key) ON DELETE CASCADE
        );
        
        CREATE TABLE IF NOT EXISTS favicon_associations (
            scope_key TEXT PRIMARY KEY,
            image_key TEXT NOT NULL REFERENCES favicon_images(image_key) ON DELETE CASCADE,
            icon_url TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_favicon_images_updated_at ON favicon_images(updated_at);
        CREATE INDEX IF NOT EXISTS idx_favicon_sources_image_key ON favicon_sources(image_key);
        CREATE INDEX IF NOT EXISTS idx_favicon_associations_image_key ON favicon_associations(image_key);
        CREATE INDEX IF NOT EXISTS idx_favicon_associations_updated_at ON favicon_associations(updated_at);
        """
        
        _ = executeLocked(sql)
        ensureColumnLocked(name: "transparency_analysis_result", table: "favicon_images", definition: "INTEGER")
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
    
    // MARK: - Cache Lookup
    
    private func cachedAssociationImageLocked(
        for pageURL: URL,
        now: Date
    ) -> (association: SiteAssociation, image: UIImage)? {
        pruneExpiredEntriesLocked(now: now)
        
        guard let association = lookupAssociationLocked(for: pageURL),
              let image = loadImageLocked(for: association.imageKey) else {
            return nil
        }
        
        _ = updateTimestampsLocked(scopeKey: association.scopeKey, imageKey: association.imageKey, now: now)
        return (association: association, image: image)
    }
    
    private func transparencyAnalysisResultLocked(for image: UIImage, imageKey: String) -> Int {
        var storedAnalysisResult: Int?
        if let statement = prepareStatementLocked(
            "SELECT transparency_analysis_result FROM favicon_images WHERE image_key = ? LIMIT 1;"
        ) {
            bind(imageKey, to: statement, at: 1)
            if sqlite3_step(statement) == SQLITE_ROW,
               sqlite3_column_type(statement, 0) != SQLITE_NULL {
                storedAnalysisResult = Int(sqlite3_column_int64(statement, 0))
            }
            sqlite3_finalize(statement)
        }
        
        if let storedAnalysisResult {
            return storedAnalysisResult
        }
        
        let analysisResult = Self.transparencyAnalysisResult(for: image)
        guard let statement = prepareStatementLocked(
            "UPDATE favicon_images SET transparency_analysis_result = ? WHERE image_key = ?;"
        ) else {
            return analysisResult
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, sqlite3_int64(analysisResult))
        bind(imageKey, to: statement, at: 2)
        _ = sqlite3_step(statement)
        return analysisResult
    }
    
    private static func transparencyAnalysisResult(for image: UIImage) -> Int {
        _ = safariSharedUIFramework
        let selector = transparencyAnalysisSelector
        guard image.responds(to: selector),
              let method = class_getInstanceMethod(UIImage.self, selector) else {
            assertionFailure("SafariSharedUI transparency analysis is unavailable")
            return 1
        }
        
        let function = unsafeBitCast(method_getImplementation(method), to: TransparencyAnalysisFunction.self)
        return function(image, selector)
    }
    
    private static func shouldInsetIcon(forTransparencyAnalysisResult result: Int) -> Bool {
        return result == 0 || result == 2
    }
    
    private func fetchAndCacheFavicon(for pageURL: URL) async -> UIImage? {
        var candidates: [FetchCandidate] = []
        var fallbackPageURL = pageURL
        var declaredCandidates: [IconCandidate] = []
        
        if let document = await fetchHTMLDocument(for: pageURL, redirectDepth: 0) {
            declaredCandidates = iconCandidates(in: document.html, baseURL: document.url)
            fallbackPageURL = document.url
            
            if let manifestURL = manifestURL(in: document.html, baseURL: document.url) {
                candidates.append(contentsOf: await manifestIconURLs(from: manifestURL).map {
                    FetchCandidate(url: $0, requiresTouchIconSize: true)
                })
            }
        }
        
        candidates.append(contentsOf: declaredCandidates.filter(\.kind.isTouchIcon).map {
            FetchCandidate(url: $0.url, requiresTouchIconSize: true)
        })
        candidates.append(contentsOf: deviceTouchIconURLs(for: fallbackPageURL).map {
            FetchCandidate(url: $0, requiresTouchIconSize: true)
        })
        candidates.append(contentsOf: defaultTouchIconURLs(for: fallbackPageURL).map {
            FetchCandidate(url: $0, requiresTouchIconSize: true)
        })
        candidates.append(contentsOf: declaredCandidates.filter { !$0.kind.isTouchIcon }.map {
            FetchCandidate(url: $0.url, requiresTouchIconSize: false)
        })
        
        if let fallbackURL = defaultIconURL(path: "/favicon.ico", for: fallbackPageURL) {
            candidates.append(FetchCandidate(url: fallbackURL, requiresTouchIconSize: false))
        }
        
        return await fetchAndCacheFirstCandidate(candidates, for: pageURL)
    }
    
    private func fetchAndCacheFirstCandidate(_ candidates: [FetchCandidate], for pageURL: URL) async -> UIImage? {
        var seenCandidateURLs = Set<String>()
        for candidate in candidates {
            guard !Task.isCancelled else {
                return nil
            }
            
            let candidateURL = candidate.url
            let normalizedCandidateURL = candidateURL.absoluteString.lowercased()
            guard seenCandidateURLs.insert(normalizedCandidateURL).inserted else {
                continue
            }
            
            if let cachedImage = associateExistingIconIfPresent(
                candidateURL,
                with: pageURL,
                requiringTouchIconSize: candidate.requiresTouchIconSize
            ) {
                return cachedImage
            }
            
            guard let remoteImage = await fetchRemoteImage(from: candidateURL),
                  !candidate.requiresTouchIconSize || isAcceptableTouchIcon(remoteImage.image),
                  !Task.isCancelled else {
                continue
            }
            
            stateQueue.sync {
                storeLocked(remoteImage: remoteImage, for: pageURL, now: Date())
            }
            return remoteImage.image
        }
        
        return nil
    }
    
    private func associateExistingIconIfPresent(
        _ iconURL: URL,
        with pageURL: URL,
        requiringTouchIconSize: Bool
    ) -> UIImage? {
        stateQueue.sync {
            let now = Date()
            pruneExpiredEntriesLocked(now: now)
            
            guard let imageKey = imageKeyLocked(forSourceURL: iconURL.absoluteString),
                  let image = loadImageLocked(for: imageKey),
                  !requiringTouchIconSize || isAcceptableTouchIcon(image) else {
                return nil
            }
            
            let scopeKey = faviconScopeKey(for: pageURL, iconURL: iconURL)
            guard upsertAssociationLocked(scopeKey: scopeKey, imageKey: imageKey, iconURL: iconURL.absoluteString, now: now),
                  updateImageTimestampLocked(imageKey: imageKey, now: now) else {
                return nil
            }
            
            return image
        }
    }
    
    // MARK: - Cache Persistence
    
    private func storeLocked(remoteImage: RemoteImage, for pageURL: URL, now: Date) {
        let imageKey = Self.sha256(remoteImage.data)
        let imageURL = imageFileURL(for: imageKey)
        let transparencyAnalysisResult = Self.transparencyAnalysisResult(for: remoteImage.image)
        
        if !fileManager.fileExists(atPath: imageURL.path) {
            try? remoteImage.data.write(to: imageURL, options: .atomic)
        }
        
        let scopeKey = faviconScopeKey(for: pageURL, iconURL: remoteImage.url)
        guard executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
            return
        }
        
        guard upsertImageLocked(
            imageKey: imageKey,
            transparencyAnalysisResult: transparencyAnalysisResult,
            now: now
        ),
              upsertSourceURLLocked(remoteImage.url.absoluteString, imageKey: imageKey),
              upsertAssociationLocked(scopeKey: scopeKey, imageKey: imageKey, iconURL: remoteImage.url.absoluteString, now: now) else {
            _ = executeLocked("ROLLBACK TRANSACTION;")
            return
        }
        
        guard executeLocked("COMMIT TRANSACTION;") else {
            _ = executeLocked("ROLLBACK TRANSACTION;")
            return
        }
    }
    
    // MARK: - Cache Maintenance
    
    private func pruneExpiredEntriesLocked(now: Date) {
        let imageKeysBeforePruning = Set(fetchImageKeysLocked())
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cutoff = (Calendar.current.date(byAdding: .day, value: 1 - Self.expirationDays, to: startOfToday) ?? startOfToday).timeIntervalSince1970
        
        _ = deleteExpiredAssociationsLocked(cutoff: cutoff)
        _ = deleteExpiredImagesLocked(cutoff: cutoff)
        _ = executeLocked(
            """
            DELETE FROM favicon_images
            WHERE image_key NOT IN (
                SELECT image_key
                FROM favicon_associations
            );
            """
        )
        
        let imageKeysAfterPruning = Set(fetchImageKeysLocked())
        for imageKey in imageKeysBeforePruning where !imageKeysAfterPruning.contains(imageKey) {
            let imageURL = imageFileURL(for: imageKey)
            if fileManager.fileExists(atPath: imageURL.path) {
                try? fileManager.removeItem(at: imageURL)
            }
        }
    }
    
    private func lookupAssociationLocked(for pageURL: URL) -> SiteAssociation? {
        for lookupKey in faviconLookupKeys(for: pageURL) {
            if let association = associationLocked(scopeKey: lookupKey) {
                return association
            }
        }
        return nil
    }
    
    private func associationLocked(scopeKey: String) -> SiteAssociation? {
        guard let statement = prepareStatementLocked(
            """
            SELECT scope_key, image_key
            FROM favicon_associations
            WHERE scope_key = ?
            LIMIT 1;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(scopeKey, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return SiteAssociation(
            scopeKey: string(from: statement, at: 0),
            imageKey: string(from: statement, at: 1)
        )
    }
    
    private func imageKeyLocked(forSourceURL sourceURL: String) -> String? {
        guard let statement = prepareStatementLocked(
            """
            SELECT image_key
            FROM favicon_sources
            WHERE source_url = ?
            LIMIT 1;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(sourceURL, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return string(from: statement, at: 0)
    }
    
    private func loadImageLocked(for imageKey: String) -> UIImage? {
        let imageURL = imageFileURL(for: imageKey)
        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else {
            removeImageLocked(imageKey)
            return nil
        }
        return image
    }
    
    private func removeImageLocked(_ imageKey: String) {
        guard let statement = prepareStatementLocked(
            "DELETE FROM favicon_images WHERE image_key = ?;"
        ) else {
            let imageURL = imageFileURL(for: imageKey)
            if fileManager.fileExists(atPath: imageURL.path) {
                try? fileManager.removeItem(at: imageURL)
            }
            return
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(imageKey, to: statement, at: 1)
        _ = sqlite3_step(statement)
        
        let imageURL = imageFileURL(for: imageKey)
        if fileManager.fileExists(atPath: imageURL.path) {
            try? fileManager.removeItem(at: imageURL)
        }
    }
    
    private func upsertImageLocked(imageKey: String, transparencyAnalysisResult: Int, now: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO favicon_images (image_key, updated_at, transparency_analysis_result)
            VALUES (?, ?, ?)
            ON CONFLICT(image_key) DO UPDATE SET
                updated_at = excluded.updated_at,
                transparency_analysis_result = excluded.transparency_analysis_result;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(imageKey, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(transparencyAnalysisResult))
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func upsertSourceURLLocked(_ sourceURL: String, imageKey: String) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO favicon_sources (source_url, image_key)
            VALUES (?, ?)
            ON CONFLICT(source_url) DO UPDATE SET
                image_key = excluded.image_key;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(sourceURL, to: statement, at: 1)
        bind(imageKey, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func upsertAssociationLocked(scopeKey: String, imageKey: String, iconURL: String, now: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO favicon_associations (scope_key, image_key, icon_url, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(scope_key) DO UPDATE SET
                image_key = excluded.image_key,
                icon_url = excluded.icon_url,
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(scopeKey, to: statement, at: 1)
        bind(imageKey, to: statement, at: 2)
        bind(iconURL, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, now.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func updateTimestampsLocked(scopeKey: String, imageKey: String, now: Date) -> Bool {
        guard executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
            return false
        }
        
        guard updateAssociationTimestampLocked(scopeKey: scopeKey, now: now),
              updateImageTimestampLocked(imageKey: imageKey, now: now) else {
            _ = executeLocked("ROLLBACK TRANSACTION;")
            return false
        }
        
        guard executeLocked("COMMIT TRANSACTION;") else {
            _ = executeLocked("ROLLBACK TRANSACTION;")
            return false
        }
        
        return true
    }
    
    private func updateAssociationTimestampLocked(scopeKey: String, now: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            "UPDATE favicon_associations SET updated_at = ? WHERE scope_key = ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        bind(scopeKey, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func updateImageTimestampLocked(imageKey: String, now: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            "UPDATE favicon_images SET updated_at = ? WHERE image_key = ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        bind(imageKey, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func fetchImageKeysLocked() -> [String] {
        guard let statement = prepareStatementLocked(
            "SELECT image_key FROM favicon_images;"
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var imageKeys: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            imageKeys.append(string(from: statement, at: 0))
        }
        return imageKeys
    }
    
    private func deleteExpiredAssociationsLocked(cutoff: TimeInterval) -> Bool {
        guard let statement = prepareStatementLocked(
            "DELETE FROM favicon_associations WHERE updated_at < ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, cutoff)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func deleteExpiredImagesLocked(cutoff: TimeInterval) -> Bool {
        guard let statement = prepareStatementLocked(
            "DELETE FROM favicon_images WHERE updated_at < ?;"
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_double(statement, 1, cutoff)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    // MARK: - Cache Keys And URLs
    
    private func imageFileURL(for imageKey: String) -> URL {
        storage.directoryURL.appendingPathComponent(Self.imageFilePrefix + imageKey, isDirectory: false)
    }
    
    private func requestScopeKey(for pageURL: URL) -> String {
        faviconLookupKeys(for: pageURL).first ?? pageURL.absoluteString.lowercased()
    }
    
    private func faviconLookupKeys(for pageURL: URL) -> [String] {
        guard let origin = URLUtils.httpOriginString(for: pageURL) else {
            return []
        }
        
        let pathComponents = pageURL.path.split(separator: "/").map(String.init)
        guard !pathComponents.isEmpty else {
            return [origin]
        }
        
        var keys = stride(from: pathComponents.count, through: 1, by: -1).map {
            origin + "/" + pathComponents.prefix($0).joined(separator: "/")
        }
        keys.append(origin)
        return keys
    }
    
    private func faviconScopeKey(for pageURL: URL, iconURL: URL) -> String {
        guard let origin = URLUtils.httpOriginString(for: pageURL),
              let pageHost = URLUtils.normalizedHost(pageURL.host) else {
            return pageURL.absoluteString
        }
        
        guard URLUtils.normalizedHost(iconURL.host) == pageHost else {
            return origin
        }
        
        let pagePath = pageURL.path.split(separator: "/").map(String.init)
        var iconDirectory = iconURL.path.split(separator: "/").map(String.init)
        if !iconURL.path.hasSuffix("/"), !iconDirectory.isEmpty {
            iconDirectory.removeLast()
        }
        
        var sharedPath: [String] = []
        for (pageComponent, iconComponent) in zip(pagePath, iconDirectory) {
            guard pageComponent == iconComponent else {
                break
            }
            sharedPath.append(pageComponent)
        }
        return sharedPath.isEmpty ? origin : origin + "/" + sharedPath.joined(separator: "/")
    }
    
    private func defaultTouchIconURLs(for pageURL: URL) -> [URL] {
        [
            defaultIconURL(path: "/apple-touch-icon-precomposed.png", for: pageURL),
            defaultIconURL(path: "/apple-touch-icon.png", for: pageURL),
        ].compactMap { $0 }
    }
    
    private func deviceTouchIconURLs(for pageURL: URL) -> [URL] {
        let sideLength: Int
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            sideLength = UIScreen.main.scale == 1 ? 57 : 120
        case .pad:
            sideLength = UIScreen.main.scale == 1 ? 76 : 152
        default:
            sideLength = 57
        }
        
        let size = "\(sideLength)x\(sideLength)"
        return [
            defaultIconURL(path: "/apple-touch-icon-\(size)-precomposed.png", for: pageURL),
            defaultIconURL(path: "/apple-touch-icon-\(size).png", for: pageURL),
        ].compactMap { $0 }
    }
    
    private func defaultIconURL(path: String, for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
    
    // MARK: - Networking
    
    private func fetchHTMLDocument(for pageURL: URL, redirectDepth: Int) async -> HTMLDocument? {
        var request = URLRequest(url: pageURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(metadataUserAgent, forHTTPHeaderField: "User-Agent")
        
        guard let (data, response) = await data(for: request),
              data.count <= Self.maxHTMLBytes else {
            return nil
        }
        
        let mimeType = (response.mimeType ?? "").lowercased()
        guard mimeType.isEmpty || mimeType.contains("html") || mimeType.contains("xml") else {
            return nil
        }
        
        let html = string(from: data, response: response)
        guard !html.isEmpty else {
            return nil
        }
        
        let finalURL = response.url ?? pageURL
        if redirectDepth < Self.maxRedirectDepth,
           let redirectURL = metaRefreshRedirectURL(in: html, baseURL: finalURL),
           redirectURL != finalURL {
            return await fetchHTMLDocument(for: redirectURL, redirectDepth: redirectDepth + 1)
        }
        
        return HTMLDocument(html: html, url: finalURL)
    }
    
    private func fetchRemoteImage(from url: URL) async -> RemoteImage? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        guard let (data, response) = await data(for: request),
              data.count <= Self.maxImageBytes,
              let image = UIImage(data: data) else {
            return nil
        }
        
        return RemoteImage(image: image, data: data, url: response.url ?? url)
    }
    
    private func manifestIconURLs(from manifestURL: URL) async -> [URL] {
        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.setValue("application/manifest+json,application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, response) = await data(for: request),
              data.count <= Self.maxHTMLBytes,
              let manifest = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        
        let baseURL = response.url ?? manifestURL
        return manifestIconURLs(from: manifest, baseURL: baseURL)
    }
    
    private func manifestIconURLs(from manifestObject: Any, baseURL: URL) -> [URL] {
        guard let manifest = manifestObject as? [String: Any],
              let icons = manifest["icons"] as? [[String: Any]] else {
            return []
        }
        
        let candidates = icons.enumerated().compactMap { documentOrder, icon -> ManifestIcon? in
            guard let source = icon["src"] as? String,
                  let url = URL(string: source, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }
            
            let purposes = Set(manifestTokens(from: icon["purpose"], defaultValue: "any"))
            return ManifestIcon(
                url: url,
                declaredSize: declaredManifestIconSize(from: icon["sizes"]),
                purposes: purposes,
                documentOrder: documentOrder
            )
        }
        
        guard !candidates.isEmpty else {
            return []
        }
        
        let preferredPurpose = candidates.max {
            if $0.declaredSize != $1.declaredSize {
                return $0.declaredSize < $1.declaredSize
            }
            return manifestPurposeRank($0.purposes) > manifestPurposeRank($1.purposes)
        }.map { primaryManifestPurpose($0.purposes) } ?? "any"
        
        let preferredCandidates = candidates.filter {
            $0.purposes.contains(preferredPurpose)
            || ($0.purposes.isEmpty && preferredPurpose == "any")
        }
        let filteredCandidates = preferredCandidates.isEmpty ? candidates : preferredCandidates
        return filteredCandidates.sorted {
            if $0.declaredSize != $1.declaredSize {
                return $0.declaredSize > $1.declaredSize
            }
            return $0.documentOrder < $1.documentOrder
        }.map(\.url)
    }
    
    private func isAcceptableTouchIcon(_ image: UIImage) -> Bool {
        let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
        return min(pixelWidth, pixelHeight) >= Self.minimumTouchIconSideLength
    }
    
    private func data(for request: URLRequest) async -> (Data, URLResponse)? {
        await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                guard error == nil,
                      let data,
                      let response else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
    
    // MARK: - HTML Parsing
    
    private func manifestURL(in html: String, baseURL: URL) -> URL? {
        let nsHTML = html as NSString
        let matches = linkTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let relTokens = Set((attributes["rel"]?.lowercased() ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            
            guard relTokens.contains("manifest"),
                  let href = attributes["href"],
                  let url = URL(string: decodeHTMLEntities(in: href), relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            
            return url
        }
        
        return nil
    }
    
    private func iconCandidates(in html: String, baseURL: URL) -> [IconCandidate] {
        let nsHTML = html as NSString
        let matches = linkTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var candidates: [IconCandidate] = []
        
        for (documentOrder, match) in matches.enumerated() {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let relTokens = Set((attributes["rel"]?.lowercased() ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            let href = attributes["href"] ?? ""
            
            let kind: IconKind
            if relTokens.contains("apple-touch-icon-precomposed") {
                kind = .touchPrecomposed
            } else if relTokens.contains("apple-touch-icon") {
                kind = .touch
            } else if relTokens.contains("icon") {
                kind = .favicon
            } else {
                continue
            }
            
            guard !href.isEmpty,
                  let url = URL(string: decodeHTMLEntities(in: href), relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            
            candidates.append(
                IconCandidate(
                    url: url,
                    kind: kind,
                    declaredSize: declaredIconSize(from: attributes["sizes"], kind: kind),
                    documentOrder: documentOrder
                )
            )
        }
        
        return candidates.sorted {
            if $0.kind.isTouchIcon != $1.kind.isTouchIcon {
                return $0.kind.isTouchIcon
            }
            
            if $0.declaredSize != $1.declaredSize {
                return $0.declaredSize > $1.declaredSize
            }
            
            if $0.kind != $1.kind {
                return $0.kind == .touchPrecomposed
            }
            
            return $0.documentOrder < $1.documentOrder
        }
    }
    
    private func declaredIconSize(from sizes: String?, kind: IconKind) -> Int {
        if let firstSize = sizes?.split(whereSeparator: \.isWhitespace).first {
            let width = firstSize.prefix(while: \.isNumber)
            if let size = Int(width) {
                return size
            }
        }
        
        return kind.isTouchIcon ? 60 : 0
    }
    
    private func declaredManifestIconSize(from sizes: Any?) -> Int {
        return manifestTokens(from: sizes)
            .compactMap { size -> Int? in
                guard size != "any" else {
                    return Int.max
                }
                
                let dimensions = size.split(separator: "x", maxSplits: 1)
                guard dimensions.count == 2,
                      let width = Int(dimensions[0]),
                      let height = Int(dimensions[1]) else {
                    return nil
                }
                
                return max(width, height)
            }
            .max() ?? 0
    }
    
    private func manifestTokens(from value: Any?, defaultValue: String? = nil) -> [String] {
        let values: [String]
        if let value = value as? String {
            values = [value]
        } else if let value = value as? [String] {
            values = value
        } else if let value = value as? [Any] {
            values = value.compactMap { $0 as? String }
        } else {
            values = defaultValue.map { [$0] } ?? []
        }
        
        return values.flatMap {
            $0.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        }
    }
    
    private func primaryManifestPurpose(_ purposes: Set<String>) -> String {
        if purposes.contains("monochrome") {
            return "monochrome"
        }
        if purposes.contains("maskable") {
            return "maskable"
        }
        return "any"
    }
    
    private func manifestPurposeRank(_ purposes: Set<String>) -> Int {
        switch primaryManifestPurpose(purposes) {
        case "monochrome":
            return 4
        case "maskable":
            return 2
        default:
            return 1
        }
    }
    
    private func attributes(in tag: String) -> [String: String] {
        let nsTag = tag as NSString
        let matches = attributeExpression.matches(in: tag, range: NSRange(location: 0, length: nsTag.length))
        var result: [String: String] = [:]
        
        for match in matches {
            guard match.numberOfRanges >= 6 else {
                continue
            }
            
            let name = nsTag.substring(with: match.range(at: 1)).lowercased()
            let value: String
            if match.range(at: 3).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 3))
            } else if match.range(at: 4).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 4))
            } else if match.range(at: 5).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 5))
            } else {
                value = ""
            }
            
            result[name] = value
        }
        
        return result
    }
    
    private func metaRefreshRedirectURL(in html: String, baseURL: URL) -> URL? {
        let nsHTML = html as NSString
        let matches = metaTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let httpEquiv = attributes["http-equiv"]?.lowercased() ?? ""
            guard httpEquiv == "refresh",
                  let content = attributes["content"] else {
                continue
            }
            
            let parts = content.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }
            
            let redirectPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard redirectPart.lowercased().hasPrefix("url=") else {
                continue
            }
            
            let value = redirectPart.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            let unquotedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let redirectURL = URL(string: decodeHTMLEntities(in: unquotedValue), relativeTo: baseURL)?.absoluteURL {
                return redirectURL
            }
        }
        
        return nil
    }
    
    private func string(from data: Data, response: URLResponse) -> String {
        if let encodingName = response.textEncodingName,
           let encoding = String.Encoding.ianaCharacterSetName(encodingName),
           let string = String(data: data, encoding: encoding) {
            return string
        }
        
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        
        return ""
    }
    
    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
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
    
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
