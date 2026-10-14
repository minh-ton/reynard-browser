//
//  SyncManager.swift
//  Reynard
//
//  Firefox Sync for Reynard:
//  - clients:   uploads this device's record so other Firefoxes list it
//  - tabs:      uploads open tabs, downloads other devices' tabs
//  - history:   two-way (download + merge, upload new local visits; never deletes)
//  - bookmarks: one-way mirror of your Firefox bookmarks into a "Firefox Bookmarks" folder
//

import Foundation
import UIKit

struct SyncLocalTab {
    let title: String
    let url: String
    let lastUsed: Date
}

protocol SyncLocalTabsSource: AnyObject {
    var syncLocalTabs: [SyncLocalTab] { get }
}

final class SyncManager {
    static let shared = SyncManager()

    enum Reason {
        case signIn
        case user
        case foreground
        case background
    }

    private struct CollectionKeys {
        let defaultBundle: SyncKeyBundle
        let collectionBundles: [String: SyncKeyBundle]

        func bundle(for collection: String) -> SyncKeyBundle {
            collectionBundles[collection] ?? defaultBundle
        }
    }

    private final class WeakTabSource {
        weak var value: SyncLocalTabsSource?
        init(_ value: SyncLocalTabsSource) {
            self.value = value
        }
    }

    private enum Limits {
        static let firstHistoryDownload = 5_000
        static let historyDownload = 20_000
        static let historyUploadWindow: TimeInterval = 30 * 86_400
        static let historyUploadBatch = 2_000
        static let visitsPerRecord = 20
        static let tabsPayloadBytes = 400_000
        static let foregroundInterval: TimeInterval = 10 * 60
        static let backgroundInterval: TimeInterval = 2 * 60
    }

    private(set) var isSyncing = false
    private(set) var remoteClients: [RemoteClientTabs]
    private var syncTask: Task<Void, Never>?
    private var pendingResync = false
    private var lastAttempt: Date?
    private var backoffUntil: Date?
    private var cachedClient: SyncStorageClient?
    private var tabSources: [WeakTabSource] = []

    private init() {
        remoteClients = SyncMetadataStore.shared.loadRemoteTabs()
    }

    // MARK: - Public

    func registerTabSource(_ source: SyncLocalTabsSource) {
        tabSources.removeAll { $0.value == nil || $0.value === source }
        tabSources.append(WeakTabSource(source))
    }

    func requestSync(reason: Reason) {
        let accounts = FxAAccountManager.shared
        guard accounts.isSignedIn, !accounts.needsReauthentication else {
            return
        }

        let isUserInitiated = reason == .user || reason == .signIn
        if let backoffUntil, backoffUntil > Date(), !isUserInitiated {
            return
        }
        if let lastAttempt {
            let elapsed = Date().timeIntervalSince(lastAttempt)
            if reason == .foreground, elapsed < Limits.foregroundInterval {
                return
            }
            if reason == .background, elapsed < Limits.backgroundInterval {
                return
            }
        }
        if syncTask != nil {
            if isUserInitiated {
                pendingResync = true
            }
            return
        }

        lastAttempt = Date()
        isSyncing = true
        postStatus()

        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Firefox Sync")
        syncTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performSync()
            self.syncTask = nil
            self.isSyncing = false
            self.postStatus()
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            if self.pendingResync {
                self.pendingResync = false
                self.requestSync(reason: .user)
            }
        }
    }

    func handleSignOut() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        cachedClient = nil
        remoteClients = []
        SyncMetadataStore.shared.reset()
        BookmarkStore.shared.removeSyncedBookmarks()
        NotificationCenter.default.post(name: .syncedTabsDidChange, object: self)
        postStatus()
    }

    // MARK: - Sync

    private func performSync() async {
        do {
            let client = try await storageClient()
            let info = try await client.infoCollections()
            let keys = try await collectionKeys(client: client)

            var failures: [String] = []
            func run(_ name: String, _ work: () async throws -> Void) async {
                do {
                    try await work()
                } catch {
                    NSLog("Reynard Sync: %@ failed: %@", name, error.localizedDescription)
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }

            await run(NSLocalizedString("Devices", comment: "")) {
                try await self.uploadClientRecord(client: client, keys: keys)
            }
            if SyncPreferences.isEnabled(.tabs) {
                await run(NSLocalizedString("Tabs", comment: "")) {
                    try await self.syncTabs(client: client, keys: keys)
                }
            }
            if SyncPreferences.isEnabled(.history) {
                await run(NSLocalizedString("History", comment: "")) {
                    try await self.syncHistory(client: client, keys: keys, info: info)
                }
            }
            if SyncPreferences.isEnabled(.bookmarks) {
                await run(NSLocalizedString("Bookmarks", comment: "")) {
                    try await self.syncBookmarks(client: client, keys: keys, info: info)
                }
            }

            SyncPreferences.lastSyncDate = Date()
            SyncPreferences.lastSyncError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        } catch {
            if case let SyncStorageError.serverBackoff(seconds) = error {
                backoffUntil = Date().addingTimeInterval(TimeInterval(seconds))
            }
            if case SyncStorageError.unauthorized = error {
                cachedClient = nil
            }
            NSLog("Reynard Sync: sync failed: %@", error.localizedDescription)
            SyncPreferences.lastSyncError = error.localizedDescription
        }
    }

    private func storageClient() async throws -> SyncStorageClient {
        if let cachedClient, cachedClient.token.expiresAt.timeIntervalSinceNow > 60 {
            return cachedClient
        }

        let accounts = FxAAccountManager.shared
        guard let account = accounts.account else {
            throw FxAAccountError.notSignedIn
        }
        let config = await FxAConfig.discover()

        let token: SyncToken
        do {
            token = try await SyncStorageClient.fetchToken(
                tokenServerURL: config.tokenServerURL,
                accessToken: try await accounts.accessToken(),
                keyID: account.syncKey.kid
            )
        } catch SyncStorageError.unauthorized {
            // The cached access token may have been revoked; get a fresh one once.
            do {
                token = try await SyncStorageClient.fetchToken(
                    tokenServerURL: config.tokenServerURL,
                    accessToken: try await accounts.accessToken(forceRefresh: true),
                    keyID: account.syncKey.kid
                )
            } catch SyncStorageError.unauthorized {
                accounts.markNeedsReauthentication()
                throw FxAAccountError.reauthenticationRequired
            }
        }

        let client = SyncStorageClient(token: token)
        cachedClient = client
        return client
    }

    private func collectionKeys(client: SyncStorageClient) async throws -> CollectionKeys {
        guard let meta = try await client.getRecord(collection: "meta", id: "global"),
              let metaData = meta.payload.data(using: .utf8),
              let metaJSON = try JSONSerialization.jsonObject(with: metaData) as? [String: Any] else {
            throw SyncStorageError.notSetUp
        }

        let storageVersion = (metaJSON["storageVersion"] as? NSNumber)?.intValue ?? 0
        guard storageVersion == 5 else {
            throw SyncStorageError.unsupportedStorageVersion(storageVersion)
        }

        if let syncID = metaJSON["syncID"] as? String, syncID != SyncPreferences.globalSyncID {
            // The server was wiped or the account moved to a new storage node.
            if SyncPreferences.globalSyncID != nil {
                SyncPreferences.resetCollectionTimestamps()
                SyncMetadataStore.shared.reset()
            }
            SyncPreferences.globalSyncID = syncID
        }

        guard let keysRecord = try await client.getRecord(collection: "crypto", id: "keys") else {
            throw SyncStorageError.notSetUp
        }

        let rootBundle = try FxAAccountManager.shared.syncKeyBundle()
        let cleartext: [String: Any]
        do {
            cleartext = try rootBundle.decrypt(payload: keysRecord.payload)
        } catch {
            throw SyncStorageError.keysUnavailable
        }

        guard let defaultPair = Self.stringArray(cleartext["default"]),
              let defaultBundle = try? SyncKeyBundle(base64Pair: defaultPair) else {
            throw SyncStorageError.keysUnavailable
        }

        var collectionBundles: [String: SyncKeyBundle] = [:]
        if let collections = cleartext["collections"] as? [String: Any] {
            for (name, value) in collections {
                if let pair = Self.stringArray(value), let bundle = try? SyncKeyBundle(base64Pair: pair) {
                    collectionBundles[name] = bundle
                }
            }
        }
        return CollectionKeys(defaultBundle: defaultBundle, collectionBundles: collectionBundles)
    }

    // MARK: - Clients

    private func uploadClientRecord(client: SyncStorageClient, keys: CollectionKeys) async throws {
        guard let account = FxAAccountManager.shared.account else {
            return
        }
        var record: [String: Any] = [
            "id": account.clientRecordID,
            "name": SyncPreferences.deviceName,
            "type": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile",
            "commands": [Any](),
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            "protocols": ["1.5"],
            "os": "iOS",
            "application": "Reynard",
        ]
        if let deviceID = account.deviceID {
            record["fxaDeviceId"] = deviceID
        }

        let payload = try keys.bundle(for: "clients").encrypt(record)
        _ = try await client.post(
            collection: "clients",
            records: [SyncBSO(id: account.clientRecordID, payload: payload, ttl: SyncStorageClient.recordTTL)]
        )
    }

    // MARK: - Tabs

    private func syncTabs(client: SyncStorageClient, keys: CollectionKeys) async throws {
        guard let account = FxAAccountManager.shared.account else {
            return
        }
        let bundle = keys.bundle(for: "tabs")

        // Upload ours.
        var seenURLs = Set<String>()
        let localTabs = tabSources
            .compactMap(\.value)
            .flatMap(\.syncLocalTabs)
            .filter { tab in
                guard let scheme = URL(string: tab.url)?.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else {
                    return false
                }
                return seenURLs.insert(tab.url).inserted
            }
            .sorted { $0.lastUsed > $1.lastUsed }

        var tabRecords: [[String: Any]] = []
        var payloadBytes = 0
        for tab in localTabs {
            let title = tab.title.isEmpty ? tab.url : tab.title
            let entry: [String: Any] = [
                "title": String(title.prefix(512)),
                "urlHistory": [tab.url],
                "lastUsed": Int64(tab.lastUsed.timeIntervalSince1970),
            ]
            payloadBytes += tab.url.utf8.count + title.utf8.count + 64
            if payloadBytes > Limits.tabsPayloadBytes {
                break
            }
            tabRecords.append(entry)
        }

        let record: [String: Any] = [
            "id": account.clientRecordID,
            "clientName": SyncPreferences.deviceName,
            "tabs": tabRecords,
        ]
        let payload = try bundle.encrypt(record)
        _ = try await client.post(
            collection: "tabs",
            records: [SyncBSO(id: account.clientRecordID, payload: payload, ttl: SyncStorageClient.recordTTL)]
        )

        // Download everyone else's.
        let result = try await client.getCollection("tabs")
        let decrypted = await Self.decrypt(result.records, with: bundle)
        let ownID = account.clientRecordID

        var clients: [RemoteClientTabs] = []
        for (bso, json) in decrypted where bso.id != ownID {
            let rawTabs = json["tabs"] as? [[String: Any]] ?? []
            let tabs: [RemoteClientTabs.RemoteTab] = rawTabs.compactMap { tab in
                guard let url = Self.stringArray(tab["urlHistory"])?.first, !url.isEmpty else {
                    return nil
                }
                let lastUsed = (tab["lastUsed"] as? NSNumber)?.doubleValue ?? 0
                let title = tab["title"] as? String ?? ""
                return RemoteClientTabs.RemoteTab(
                    title: title.isEmpty ? url : title,
                    url: url,
                    lastUsed: Date(timeIntervalSince1970: lastUsed)
                )
            }
            guard !tabs.isEmpty else {
                continue
            }
            clients.append(RemoteClientTabs(
                clientID: bso.id,
                name: json["clientName"] as? String ?? NSLocalizedString("Unknown Device", comment: ""),
                lastModified: Date(timeIntervalSince1970: bso.modified),
                tabs: tabs.sorted { $0.lastUsed > $1.lastUsed }
            ))
        }
        clients.sort { $0.lastModified > $1.lastModified }

        remoteClients = clients
        SyncMetadataStore.shared.saveRemoteTabs(clients)
        NotificationCenter.default.post(name: .syncedTabsDidChange, object: self)
    }

    // MARK: - History

    private func syncHistory(client: SyncStorageClient, keys: CollectionKeys, info: [String: Double]) async throws {
        let bundle = keys.bundle(for: "history")
        let syncStartedAt = Date()
        let lastModified = SyncPreferences.lastModified("history")

        // 1. Download.
        if let serverModified = info["history"], serverModified > lastModified {
            let isFirstSync = lastModified == 0
            let result = try await client.getCollection(
                "history",
                newer: isFirstSync ? nil : lastModified,
                sort: "newest",
                pageSize: 1_000,
                maxRecords: isFirstSync ? Limits.firstHistoryDownload : Limits.historyDownload
            )
            let decrypted = await Self.decrypt(result.records, with: bundle)

            var entries: [HistoryStore.SyncedVisits] = []
            var guidMap: [String: String] = [:]
            for (bso, json) in decrypted {
                if json["deleted"] as? Bool == true {
                    continue
                }
                guard let uri = json["histUri"] as? String,
                      let url = URL(string: uri),
                      URLUtils.isWebURL(url) else {
                    continue
                }
                let visits = (json["visits"] as? [[String: Any]] ?? []).compactMap { visit -> Date? in
                    guard let micros = (visit["date"] as? NSNumber)?.doubleValue, micros > 0 else {
                        return nil
                    }
                    return Date(timeIntervalSince1970: micros / 1_000_000)
                }
                guard !visits.isEmpty else {
                    continue
                }
                guidMap[uri] = bso.id
                entries.append(HistoryStore.SyncedVisits(
                    url: url,
                    title: json["title"] as? String ?? "",
                    visits: Array(visits.sorted(by: >).prefix(Limits.visitsPerRecord))
                ))
            }

            SyncMetadataStore.shared.setHistoryGUIDs(guidMap)
            _ = await HistoryStore.shared.importSyncedVisits(entries)
            // If we hit the record cap on the first sync, still move forward:
            // older history isn't worth an unbounded download on a phone.
            SyncPreferences.setLastModified(max(result.lastModified, serverModified), for: "history")
        }

        // 2. Upload local visits made since the last upload.
        let uploadSince = SyncPreferences.lastHistoryUpload
            ?? syncStartedAt.addingTimeInterval(-Limits.historyUploadWindow)
        let local = await HistoryStore.shared.visitsForSync(since: uploadSince, limit: Limits.historyUploadBatch * 5)
        guard !local.isEmpty else {
            SyncPreferences.lastHistoryUpload = syncStartedAt
            return
        }

        let urls = local.map(\.url.absoluteString)
        var guids = SyncMetadataStore.shared.historyGUIDs(for: urls)

        // Records we already know about must be merged with the server copy,
        // otherwise our upload would replace visits made on other devices.
        let knownIDs = Array(Set(guids.values))
        var serverVisits: [String: [Int64]] = [:]
        var serverTitles: [String: String] = [:]
        for chunk in stride(from: 0, to: knownIDs.count, by: 100).map({ Array(knownIDs[$0..<min($0 + 100, knownIDs.count)]) }) {
            let existing = try await client.getCollection("history", ids: chunk, pageSize: 100, maxRecords: 100)
            for (bso, json) in await Self.decrypt(existing.records, with: bundle) {
                serverVisits[bso.id] = (json["visits"] as? [[String: Any]] ?? []).compactMap {
                    ($0["date"] as? NSNumber)?.int64Value
                }
                serverTitles[bso.id] = json["title"] as? String
            }
        }

        var newMappings: [String: String] = [:]
        var records: [SyncBSO] = []
        for entry in local.prefix(Limits.historyUploadBatch) {
            let uri = entry.url.absoluteString
            let guid: String
            if let known = guids[uri] {
                guid = known
            } else {
                guid = FxACrypto.makeSyncGUID()
                guids[uri] = guid
                newMappings[uri] = guid
            }

            var micros = Set(serverVisits[guid] ?? [])
            for visit in entry.visits {
                micros.insert(Int64((visit.timeIntervalSince1970 * 1_000_000).rounded()))
            }
            let visits = micros.sorted(by: >).prefix(Limits.visitsPerRecord).map { ["date": $0, "type": 1] as [String: Any] }
            let title = entry.title.isEmpty ? (serverTitles[guid] ?? "") : entry.title

            let cleartext: [String: Any] = [
                "id": guid,
                "histUri": uri,
                "title": String(title.prefix(512)),
                "visits": Array(visits),
            ]
            records.append(SyncBSO(id: guid, payload: try bundle.encrypt(cleartext)))
        }

        let posted = try await client.post(collection: "history", records: records)
        SyncMetadataStore.shared.setHistoryGUIDs(newMappings)
        if posted.lastModified > 0 {
            // Don't re-download what we just wrote.
            SyncPreferences.setLastModified(max(posted.lastModified, SyncPreferences.lastModified("history")), for: "history")
        }
        SyncPreferences.lastHistoryUpload = syncStartedAt
    }

    // MARK: - Bookmarks (download only)

    private func syncBookmarks(client: SyncStorageClient, keys: CollectionKeys, info: [String: Double]) async throws {
        guard let serverModified = info["bookmarks"] else {
            return
        }
        guard serverModified > SyncPreferences.lastModified("bookmarks") else {
            return
        }

        let result = try await client.getCollection("bookmarks", pageSize: 1_000, maxRecords: 100_000)
        let decrypted = await Self.decrypt(result.records, with: keys.bundle(for: "bookmarks"))

        var recordsByID: [String: [String: Any]] = [:]
        for (bso, json) in decrypted where json["deleted"] as? Bool != true {
            recordsByID[bso.id] = json
        }

        let rootTitles: [(id: String, title: String)] = [
            ("toolbar", NSLocalizedString("Bookmarks Toolbar", comment: "")),
            ("menu", NSLocalizedString("Bookmarks Menu", comment: "")),
            ("unfiled", NSLocalizedString("Other Bookmarks", comment: "")),
            ("mobile", NSLocalizedString("Mobile Bookmarks", comment: "")),
        ]

        var visited = Set<String>()
        func node(for id: String, depth: Int) -> BookmarkStore.SyncedBookmarkNode? {
            guard depth < 32, visited.insert(id).inserted, let record = recordsByID[id] else {
                return nil
            }
            let title = record["title"] as? String ?? ""
            let dateAdded = (record["dateAdded"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1_000)
            } ?? Date()

            switch record["type"] as? String {
            case "bookmark":
                guard let uri = record["bmkUri"] as? String,
                      let url = URL(string: uri),
                      URLUtils.isAbsoluteURL(url) else {
                    return nil
                }
                return BookmarkStore.SyncedBookmarkNode(title: title, dateAdded: dateAdded, kind: .bookmark(url))
            case "folder":
                let children = (Self.stringArray(record["children"]) ?? []).compactMap { node(for: $0, depth: depth + 1) }
                return BookmarkStore.SyncedBookmarkNode(title: title, dateAdded: dateAdded, kind: .folder(children))
            default:
                // Separators, queries and livemarks have no Reynard equivalent.
                return nil
            }
        }

        var roots: [BookmarkStore.SyncedBookmarkNode] = []
        for root in rootTitles {
            guard let rootNode = node(for: root.id, depth: 0),
                  case let .folder(children) = rootNode.kind,
                  !children.isEmpty else {
                continue
            }
            roots.append(BookmarkStore.SyncedBookmarkNode(title: root.title, dateAdded: rootNode.dateAdded, kind: .folder(children)))
        }

        let didReplace = await BookmarkStore.shared.replaceSyncedBookmarks(
            folderTitle: NSLocalizedString("Firefox Bookmarks", comment: ""),
            roots: roots
        )
        if didReplace {
            SyncPreferences.setLastModified(max(result.lastModified, serverModified), for: "bookmarks")
        }
    }

    // MARK: - Helpers

    /// Decrypts records off the main thread. Records that fail to decrypt are skipped.
    private static func decrypt(_ records: [SyncBSO], with bundle: SyncKeyBundle) async -> [(SyncBSO, [String: Any])] {
        let box = await Task.detached(priority: .utility) { () -> DecryptedRecords in
            DecryptedRecords(SyncManager.decryptRecords(records, with: bundle))
        }.value
        return box.records
    }

    private nonisolated static func decryptRecords(_ records: [SyncBSO], with bundle: SyncKeyBundle) -> [(SyncBSO, [String: Any])] {
        var result: [(SyncBSO, [String: Any])] = []
        result.reserveCapacity(records.count)
        for record in records {
            guard let json = try? bundle.decrypt(payload: record.payload) else {
                continue
            }
            // A record whose cleartext ID doesn't match its envelope was tampered with or misfiled.
            if let id = json["id"] as? String, id != record.id {
                continue
            }
            result.append((record, json))
        }
        return result
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? [Any] {
            let strings = array.compactMap { $0 as? String }
            return strings.count == array.count ? strings : nil
        }
        return nil
    }

    private func postStatus() {
        NotificationCenter.default.post(name: .syncStatusDidChange, object: self)
    }
}

/// Carries decrypted JSON (not Sendable) back from the background decrypt task.
private nonisolated final class DecryptedRecords: @unchecked Sendable {
    let records: [(SyncBSO, [String: Any])]
    
    init(_ records: [(SyncBSO, [String: Any])]) {
        self.records = records
    }
}
