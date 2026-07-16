//
//  NavigationHistoryStore.swift
//  Reynard
//
//  Created by Minh Ton on 17/5/26.
//

import Foundation

protocol NavigationHistoryFileSystem {
    func applicationSupportDirectoryURL() -> URL?
    func createDirectory(at url: URL) throws
    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func removeItem(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func fileExists(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

struct FoundationNavigationHistoryFileSystem: NavigationHistoryFileSystem {
    private let fileManager: FileManager
    private let directories: ReynardDirectories

    init(
        fileManager: FileManager = .default,
        directories: ReynardDirectories = .shared
    ) {
        self.fileManager = fileManager
        self.directories = directories
    }

    func applicationSupportDirectoryURL() -> URL? {
        directories.applicationSupport
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func readData(at url: URL, options: Data.ReadingOptions = []) throws -> Data {
        try Data(contentsOf: url, options: options)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}

final class NavigationHistoryStore {
    static let shared = NavigationHistoryStore()

    struct Snapshot {
        let currentURL: String?
        let backHistory: [String]
        let forwardHistory: [String]
        let canGoBack: Bool
        let canGoForward: Bool
        let backPreviewImage: NavigationPreviewImage?
        let forwardPreviewImage: NavigationPreviewImage?
        let usesStoredHistory: Bool
    }

    struct CacheMetrics {
        let cachedTabCount: Int
        let previewByteCount: Int
        let pendingWriteCount: Int
        let trackedGenerationCount: Int
        let tombstoneCount: Int
        let persistenceFailureCount: Int
        let droppedWriteCount: Int
        let isPersistenceAvailable: Bool
    }

    private struct NavigationEntry: Codable {
        var url: String
    }

    private struct StoredHistory: Codable {
        var currentURL: String?
        var backHistory: [NavigationEntry]
        var forwardHistory: [NavigationEntry]
        var usesStoredHistory: Bool?

        private enum CodingKeys: String, CodingKey {
            case currentURL
            case backHistory = "backList"
            case forwardHistory = "forwardList"
            case usesStoredHistory = "ownsNav"
        }
    }

    private struct StoredDocument: Codable {
        static let currentVersion = 1

        let version: Int
        let history: StoredHistory
    }

    private struct PreviewSet {
        var current: Data?
        var back: Data?
        var forward: Data?

        static let empty = PreviewSet(current: nil, back: nil, forward: nil)

        var byteCount: Int {
            return (current?.count ?? 0) + (back?.count ?? 0) + (forward?.count ?? 0)
        }
    }

    private struct PendingWrite {
        let generation: UInt64
        let history: StoredHistory
        let previews: PreviewSet
    }

    private enum StorageValidationError: Error {
        case unsupportedVersion
        case invalidURL
    }

    private let thumbnailJPEGQuality = 0.8
    private let fileSystem: NavigationHistoryFileSystem
    private let storageURL: URL?
    private let now: () -> Date
    private let configuration: NavigationHistoryConfiguration
    private let persistencePolicy: NavigationPersistencePolicy
    private let queue = DispatchQueue(
        label: "com.minh-ton.Reynard.NavigationHistoryStore.Queue",
        qos: .userInitiated
    )
    private let persistenceQueue = DispatchQueue(
        label: "com.minh-ton.Reynard.NavigationHistoryStore.Persistence",
        qos: .utility
    )

    private var historyCache: [UUID: StoredHistory] = [:]
    private var previewCache: [UUID: PreviewSet] = [:]
    private var cacheOrder: [UUID] = []
    private var generations: [UUID: UInt64] = [:]
    private var tombstones: Set<UUID> = []
    private var pendingWrites: [UUID: PendingWrite] = [:]
    private var pendingWriteOrder: [UUID] = []
    private var persistenceScheduled = false
    private var persistenceAvailable: Bool
    private var persistenceFailureCount = 0
    private var droppedWriteCount = 0

    init(
        fileSystem: NavigationHistoryFileSystem = FoundationNavigationHistoryFileSystem(),
        storageURL: URL? = nil,
        configuration: NavigationHistoryConfiguration = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileSystem = fileSystem
        self.configuration = configuration
        self.persistencePolicy = NavigationPersistencePolicy(configuration: configuration)
        self.now = now

        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = fileSystem.applicationSupportDirectoryURL()?
                .appendingPathComponent("AppData", isDirectory: true)
                .appendingPathComponent("TabSessions", isDirectory: true)
        }
        self.persistenceAvailable = self.storageURL != nil

        queue.sync {
            prepareStorageDirectory()
        }
    }

    func currentSnapshot(for tabID: UUID) -> Snapshot {
        queue.sync {
            let history = loadHistory(for: tabID)
            return snapshot(from: history, previews: loadPreviews(for: tabID))
        }
    }

    func recordNavigation(to url: String, for tabID: UUID) -> Snapshot {
        queue.sync {
            beginMutation(for: tabID)
            var history = loadHistory(for: tabID)
            var previews = loadPreviews(for: tabID)
            // Consecutive commits of the same URL are one browser-history entry.
            guard let persistableURL = persistencePolicy.persistableURL(from: url),
                  history.currentURL != persistableURL else {
                return snapshot(from: history, previews: previews)
            }

            if let currentURL = history.currentURL, !currentURL.isEmpty {
                history.backHistory.append(NavigationEntry(url: currentURL))
                trimOldestEntries(in: &history.backHistory)
            }

            history.currentURL = persistableURL
            history.forwardHistory.removeAll(keepingCapacity: false)
            previews.back = previews.current
            previews.current = nil
            previews.forward = nil
            saveHistory(history, previews: previews, for: tabID)
            return snapshot(from: history, previews: previews)
        }
    }

    func setUsesPersistedHistory(_ usesPersistedHistory: Bool, for tabID: UUID) -> Snapshot {
        queue.sync {
            beginMutation(for: tabID)
            var history = loadHistory(for: tabID)
            let previews = loadPreviews(for: tabID)
            history.usesStoredHistory = usesPersistedHistory
            saveHistory(history, previews: previews, for: tabID)
            return snapshot(from: history, previews: previews)
        }
    }

    func goBack(for tabID: UUID) -> String? {
        queue.sync {
            guard !tombstones.contains(tabID) else {
                return nil
            }
            var history = loadHistory(for: tabID)
            var previews = loadPreviews(for: tabID)
            guard let target = history.backHistory.popLast() else {
                return nil
            }

            if let currentURL = history.currentURL, !currentURL.isEmpty {
                history.forwardHistory.insert(NavigationEntry(url: currentURL), at: 0)
                trimNewestEntries(in: &history.forwardHistory)
            }

            history.currentURL = target.url
            previews.forward = previews.current
            previews.current = previews.back
            previews.back = nil
            saveHistory(history, previews: previews, for: tabID)
            return target.url
        }
    }

    func goForward(for tabID: UUID) -> String? {
        queue.sync {
            guard !tombstones.contains(tabID) else {
                return nil
            }
            var history = loadHistory(for: tabID)
            var previews = loadPreviews(for: tabID)
            guard !history.forwardHistory.isEmpty else {
                return nil
            }

            let target = history.forwardHistory.removeFirst()
            if let currentURL = history.currentURL, !currentURL.isEmpty {
                history.backHistory.append(NavigationEntry(url: currentURL))
                trimOldestEntries(in: &history.backHistory)
            }

            history.currentURL = target.url
            previews.back = previews.current
            previews.current = previews.forward
            previews.forward = nil
            saveHistory(history, previews: previews, for: tabID)
            return target.url
        }
    }

    func updateCurrentHistoryThumbnail(
        _ image: NavigationPreviewImage?,
        for tabID: UUID,
        matching url: String
    ) {
        let data = image?
            .jpegData(compressionQuality: thumbnailJPEGQuality)
            .flatMap { $0.count <= configuration.maximumPreviewBytes ? $0 : nil }
        queue.async {
            guard !self.tombstones.contains(tabID) else {
                return
            }
            let history = self.loadHistory(for: tabID)
            guard history.currentURL == url else {
                return
            }

            var previews = self.loadPreviews(for: tabID)
            previews.current = data
            self.saveHistory(history, previews: previews, for: tabID)
        }
    }

    func invalidateThumbnails() {
        queue.sync {
            let tabIDs = Set(historyCache.keys).union(persistedTabIDs())
            for tabID in tabIDs where !tombstones.contains(tabID) {
                let history = loadHistory(for: tabID)
                saveHistory(history, previews: .empty, for: tabID)
            }
        }
    }

    func removeNavigationHistory(for tabID: UUID) {
        queue.sync {
            tombstones.insert(tabID)
            generations[tabID, default: 0] &+= 1
            let deletionGeneration = generations[tabID] ?? 0
            pendingWrites.removeValue(forKey: tabID)
            pendingWriteOrder.removeAll { $0 == tabID }
            historyCache.removeValue(forKey: tabID)
            previewCache.removeValue(forKey: tabID)
            cacheOrder.removeAll { $0 == tabID }

            guard let historyURL = self.historyURL(for: tabID),
                  let previewDirectoryURL = self.previewDirectoryURL(for: tabID),
                  persistenceAvailable else {
                finishDeletion(for: tabID, generation: deletionGeneration)
                return
            }
            persistenceQueue.async {
                do {
                    try self.removeIfPresent(at: historyURL)
                    try self.removeIfPresent(at: previewDirectoryURL)
                } catch {
                    self.registerPersistenceFailure()
                }
                self.queue.async {
                    self.finishDeletion(for: tabID, generation: deletionGeneration)
                }
            }
        }
    }

    func flushPendingWrites() {
        while true {
            let writes = queue.sync { drainPendingWrites() }
            if !writes.isEmpty {
                persistenceQueue.sync {
                    writes.forEach(persist)
                }
                continue
            }
            persistenceQueue.sync {}
            if queue.sync(execute: { pendingWrites.isEmpty }) {
                return
            }
        }
    }

    func flushPendingWritesForTesting() {
        flushPendingWrites()
    }

    func cacheMetricsForTesting() -> CacheMetrics {
        queue.sync {
            CacheMetrics(
                cachedTabCount: historyCache.count,
                previewByteCount: previewCache.values.reduce(0) { $0 + $1.byteCount },
                pendingWriteCount: pendingWrites.count,
                trackedGenerationCount: generations.count,
                tombstoneCount: tombstones.count,
                persistenceFailureCount: persistenceFailureCount,
                droppedWriteCount: droppedWriteCount,
                isPersistenceAvailable: persistenceAvailable
            )
        }
    }

    private func emptyHistory() -> StoredHistory {
        return StoredHistory(
            currentURL: nil,
            backHistory: [],
            forwardHistory: [],
            usesStoredHistory: nil
        )
    }

    private func beginMutation(for tabID: UUID) {
        if tombstones.remove(tabID) != nil {
            generations[tabID, default: 0] &+= 1
            historyCache[tabID] = emptyHistory()
            previewCache[tabID] = .empty
        }
    }

    private func finishDeletion(for tabID: UUID, generation: UInt64) {
        guard generations[tabID] == generation,
              pendingWrites[tabID] == nil else {
            return
        }
        tombstones.remove(tabID)
        generations.removeValue(forKey: tabID)
    }

    private func prepareStorageDirectory() {
        guard persistenceAvailable, let storageURL else {
            return
        }
        do {
            try fileSystem.createDirectory(at: storageURL)
        } catch {
            persistenceAvailable = false
            persistenceFailureCount += 1
        }
    }

    private func loadHistory(for tabID: UUID) -> StoredHistory {
        guard !tombstones.contains(tabID) else {
            return emptyHistory()
        }
        if let history = historyCache[tabID] {
            touchCache(tabID)
            return history
        }

        let history: StoredHistory
        guard persistenceAvailable, let fileURL = historyURL(for: tabID) else {
            historyCache[tabID] = emptyHistory()
            touchCache(tabID)
            return emptyHistory()
        }
        if !fileSystem.fileExists(at: fileURL) {
            history = emptyHistory()
        } else {
            do {
                let data = try fileSystem.readData(at: fileURL, options: .mappedIfSafe)
                history = try decodeHistory(from: data)
            } catch is DecodingError {
                quarantineCorruptHistory(at: fileURL)
                history = emptyHistory()
            } catch is StorageValidationError {
                quarantineCorruptHistory(at: fileURL)
                history = emptyHistory()
            } catch {
                persistenceAvailable = false
                persistenceFailureCount += 1
                history = emptyHistory()
            }
        }

        historyCache[tabID] = history
        touchCache(tabID)
        return history
    }

    private func decodeHistory(from data: Data) throws -> StoredHistory {
        let decoder = JSONDecoder()
        let decodedHistory: StoredHistory
        if let document = try? decoder.decode(StoredDocument.self, from: data) {
            guard document.version == StoredDocument.currentVersion else {
                throw StorageValidationError.unsupportedVersion
            }
            decodedHistory = document.history
        } else {
            decodedHistory = try decoder.decode(StoredHistory.self, from: data)
        }

        let allURLs = [decodedHistory.currentURL].compactMap { $0 } +
            decodedHistory.backHistory.map(\.url) +
            decodedHistory.forwardHistory.map(\.url)
        guard allURLs.allSatisfy({ persistencePolicy.persistableURL(from: $0) != nil }) else {
            throw StorageValidationError.invalidURL
        }

        var validatedHistory = decodedHistory
        trimOldestEntries(in: &validatedHistory.backHistory)
        trimNewestEntries(in: &validatedHistory.forwardHistory)
        return validatedHistory
    }

    private func quarantineCorruptHistory(at fileURL: URL) {
        let timestamp = Int(now().timeIntervalSince1970 * 1_000)
        let quarantineURL = fileURL.appendingPathExtension("corrupt-\(timestamp)")
        do {
            try removeIfPresent(at: quarantineURL)
            try fileSystem.moveItem(at: fileURL, to: quarantineURL)
        } catch {
            persistenceAvailable = false
            persistenceFailureCount += 1
        }
    }

    private func loadPreviews(for tabID: UUID) -> PreviewSet {
        guard !tombstones.contains(tabID) else {
            return .empty
        }
        if let previews = previewCache[tabID] {
            touchCache(tabID)
            return previews
        }

        let previews = PreviewSet(
            current: loadPreview(named: "current", for: tabID),
            back: loadPreview(named: "back", for: tabID),
            forward: loadPreview(named: "forward", for: tabID)
        )
        previewCache[tabID] = previews
        touchCache(tabID)
        return previews
    }

    private func loadPreview(named name: String, for tabID: UUID) -> Data? {
        guard persistenceAvailable,
              let fileURL = previewDirectoryURL(for: tabID)?
                .appendingPathComponent("\(name).jpg"),
              fileSystem.fileExists(at: fileURL) else {
            return nil
        }
        do {
            let data = try fileSystem.readData(at: fileURL, options: .mappedIfSafe)
            return data.count <= configuration.maximumPreviewBytes ? data : nil
        } catch {
            persistenceAvailable = false
            persistenceFailureCount += 1
            return nil
        }
    }

    private func saveHistory(
        _ history: StoredHistory,
        previews: PreviewSet,
        for tabID: UUID
    ) {
        guard !tombstones.contains(tabID) else {
            return
        }
        historyCache[tabID] = history
        previewCache[tabID] = previews
        touchCache(tabID)

        generations[tabID, default: 0] &+= 1
        if pendingWrites[tabID] == nil {
            pendingWriteOrder.append(tabID)
        }
        pendingWrites[tabID] = PendingWrite(
            generation: generations[tabID] ?? 0,
            history: history,
            previews: previews
        )
        trimPendingWritesIfNeeded()
        schedulePersistenceIfNeeded()
    }

    private func schedulePersistenceIfNeeded() {
        guard !persistenceScheduled else {
            return
        }
        persistenceScheduled = true
        persistenceQueue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }
            let writes = self.queue.sync { self.drainPendingWrites() }
            writes.forEach(self.persist)
        }
    }

    private func drainPendingWrites() -> [(UUID, PendingWrite)] {
        persistenceScheduled = false
        let writes = pendingWriteOrder.compactMap { tabID in
            pendingWrites[tabID].map { (tabID, $0) }
        }
        pendingWrites.removeAll(keepingCapacity: true)
        pendingWriteOrder.removeAll(keepingCapacity: true)
        return writes
    }

    private func trimPendingWritesIfNeeded() {
        while pendingWriteOrder.count > configuration.maximumPendingWriteCount {
            let droppedTabID = pendingWriteOrder.removeFirst()
            pendingWrites.removeValue(forKey: droppedTabID)
            droppedWriteCount += 1
            if historyCache[droppedTabID] == nil && !tombstones.contains(droppedTabID) {
                generations.removeValue(forKey: droppedTabID)
            }
        }
    }

    private func registerPersistenceFailure() {
        queue.sync {
            persistenceAvailable = false
            persistenceFailureCount += 1
        }
    }

    private func removeIfPresent(at url: URL) throws {
        guard fileSystem.fileExists(at: url) else {
            return
        }
        try fileSystem.removeItem(at: url)
    }

    private func persist(_ item: (key: UUID, value: PendingWrite)) {
        let tabID = item.key
        let write = item.value
        let isCurrent = queue.sync {
            persistenceAvailable &&
                !tombstones.contains(tabID) &&
                generations[tabID] == write.generation
        }
        guard isCurrent, let historyURL = historyURL(for: tabID) else {
            return
        }

        do {
            let document = StoredDocument(
                version: StoredDocument.currentVersion,
                history: write.history
            )
            let data = try JSONEncoder().encode(document)
            guard let storageURL else {
                return
            }
            try fileSystem.createDirectory(at: storageURL)
            try fileSystem.writeData(data, to: historyURL, options: .atomic)

            guard let previewDirectoryURL = previewDirectoryURL(for: tabID) else {
                return
            }
            if write.previews.byteCount == 0 {
                try removeIfPresent(at: previewDirectoryURL)
                return
            }
            try fileSystem.createDirectory(at: previewDirectoryURL)
            try persistPreview(write.previews.current, named: "current", in: previewDirectoryURL)
            try persistPreview(write.previews.back, named: "back", in: previewDirectoryURL)
            try persistPreview(write.previews.forward, named: "forward", in: previewDirectoryURL)
        } catch {
            registerPersistenceFailure()
        }
    }

    private func persistPreview(_ data: Data?, named name: String, in directoryURL: URL) throws {
        let fileURL = directoryURL.appendingPathComponent("\(name).jpg")
        if let data {
            try fileSystem.writeData(data, to: fileURL, options: .atomic)
        } else {
            try removeIfPresent(at: fileURL)
        }
    }

    private func touchCache(_ tabID: UUID) {
        cacheOrder.removeAll { $0 == tabID }
        cacheOrder.append(tabID)
        while cacheOrder.count > configuration.maximumCachedTabCount {
            let evicted = cacheOrder.removeFirst()
            historyCache.removeValue(forKey: evicted)
            previewCache.removeValue(forKey: evicted)
            if let pending = pendingWrites[evicted] {
                pendingWrites[evicted] = PendingWrite(
                    generation: pending.generation,
                    history: pending.history,
                    previews: .empty
                )
            } else if !tombstones.contains(evicted) {
                generations.removeValue(forKey: evicted)
            }
        }
    }

    private func persistedTabIDs() -> [UUID] {
        guard persistenceAvailable, let storageURL else {
            return []
        }
        do {
            return try fileSystem.contentsOfDirectory(at: storageURL)
                .compactMap { UUID(uuidString: $0.lastPathComponent) }
        } catch {
            persistenceAvailable = false
            persistenceFailureCount += 1
            return []
        }
    }

    private func trimOldestEntries(in entries: inout [NavigationEntry]) {
        let overflow = entries.count - configuration.maximumEntryCount
        if overflow > 0 {
            entries.removeFirst(overflow)
        }
    }

    private func trimNewestEntries(in entries: inout [NavigationEntry]) {
        let overflow = entries.count - configuration.maximumEntryCount
        if overflow > 0 {
            entries.removeLast(overflow)
        }
    }

    private func snapshot(from history: StoredHistory, previews: PreviewSet) -> Snapshot {
        return Snapshot(
            currentURL: history.currentURL,
            backHistory: history.backHistory.map(\.url),
            forwardHistory: history.forwardHistory.map(\.url),
            canGoBack: !history.backHistory.isEmpty,
            canGoForward: !history.forwardHistory.isEmpty,
            backPreviewImage: previews.back.flatMap(NavigationPreviewImage.init(data:)),
            forwardPreviewImage: previews.forward.flatMap(NavigationPreviewImage.init(data:)),
            usesStoredHistory: history.usesStoredHistory ?? false
        )
    }

    private func historyURL(for tabID: UUID) -> URL? {
        storageURL?.appendingPathComponent(tabID.uuidString, isDirectory: false)
    }

    private func previewDirectoryURL(for tabID: UUID) -> URL? {
        storageURL?.appendingPathComponent("\(tabID.uuidString).previews", isDirectory: true)
    }
}
