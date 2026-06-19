//
//  FaviconStore.swift
//  Reynard
//
//  Created by Minh Ton on 23/4/26.
//

import CryptoKit
import Foundation
import SQLite3
import UIKit

final class FaviconStore {
    static let shared = FaviconStore()
    
    private static let expirationDays = 30
    private static let databaseName = "Favicons"
    private static let imageFilePrefix = "img-"
    private static let maxHTMLBytes = 768 * 1024
    private static let maxImageBytes = 2 * 1024 * 1024
    private static let maxRedirectDepth = 3
    
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
            cachedImageLocked(for: pageURL, now: Date())
        }
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
            updated_at REAL NOT NULL
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
    }
    
    // MARK: - Cache Lookup
    
    private func cachedImageLocked(for pageURL: URL, now: Date) -> UIImage? {
        pruneExpiredEntriesLocked(now: now)
        
        guard let association = lookupAssociationLocked(for: pageURL),
              let image = loadImageLocked(for: association.imageKey) else {
            return nil
        }
        
        _ = updateTimestampsLocked(scopeKey: association.scopeKey, imageKey: association.imageKey, now: now)
        return image
    }
    
    private func fetchAndCacheFavicon(for pageURL: URL) async -> UIImage? {
        var candidates: [URL] = []
        
        if let document = await fetchHTMLDocument(for: pageURL, redirectDepth: 0) {
            candidates.append(contentsOf: iconURLs(in: document.html, baseURL: document.url))
        }
        
        if let fallbackURL = defaultFaviconURL(for: pageURL) {
            candidates.append(fallbackURL)
        }
        
        var seenCandidateURLs = Set<String>()
        for candidateURL in candidates {
            guard !Task.isCancelled else {
                return nil
            }
            
            let normalizedCandidateURL = candidateURL.absoluteString.lowercased()
            guard seenCandidateURLs.insert(normalizedCandidateURL).inserted else {
                continue
            }
            
            if let cachedImage = associateExistingIconIfPresent(candidateURL, with: pageURL) {
                return cachedImage
            }
            
            guard let remoteImage = await fetchRemoteImage(from: candidateURL) else {
                continue
            }
            
            stateQueue.sync {
                storeLocked(remoteImage: remoteImage, for: pageURL, now: Date())
            }
            return remoteImage.image
        }
        
        return nil
    }
    
    private func associateExistingIconIfPresent(_ iconURL: URL, with pageURL: URL) -> UIImage? {
        stateQueue.sync {
            let now = Date()
            pruneExpiredEntriesLocked(now: now)
            
            guard let imageKey = imageKeyLocked(forSourceURL: iconURL.absoluteString),
                  let image = loadImageLocked(for: imageKey) else {
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
        
        if !fileManager.fileExists(atPath: imageURL.path) {
            try? remoteImage.data.write(to: imageURL, options: .atomic)
        }
        
        let scopeKey = faviconScopeKey(for: pageURL, iconURL: remoteImage.url)
        guard executeLocked("BEGIN IMMEDIATE TRANSACTION;") else {
            return
        }
        
        guard upsertImageLocked(imageKey: imageKey, now: now),
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
    
    private func upsertImageLocked(imageKey: String, now: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO favicon_images (image_key, updated_at)
            VALUES (?, ?)
            ON CONFLICT(image_key) DO UPDATE SET
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(imageKey, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
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
    
    private func defaultFaviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
    
    // MARK: - Networking
    
    private func fetchHTMLDocument(for pageURL: URL, redirectDepth: Int) async -> HTMLDocument? {
        var request = URLRequest(url: pageURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        
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
    
    private func iconURLs(in html: String, baseURL: URL) -> [URL] {
        let nsHTML = html as NSString
        let matches = linkTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var candidates: [URL] = []
        
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let rel = attributes["rel"]?.lowercased() ?? ""
            let href = attributes["href"] ?? ""
            
            guard !href.isEmpty,
                  rel.contains("icon"),
                  !rel.contains("mask-icon"),
                  let url = URL(string: decodeHTMLEntities(in: href), relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            
            candidates.append(url)
        }
        
        return candidates
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
           let encoding = String.Encoding(ianaCharsetName: encodingName),
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

private extension String.Encoding {
    init?(ianaCharsetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }
        
        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
