//
//  NavigationHistoryStore.swift
//  Reynard
//
//  Created by Minh Ton on 17/5/26.
//

import Foundation

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

    private let thumbnailJPEGQuality = 0.8
    private let maximumPreviewBytes = 1024 * 1024
    private let fileManager: FileManager
    private let storageURL: URL
    private let maximumEntryCount: Int
    private let maximumCachedTabCount: Int
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
    private var persistenceScheduled = false

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        maximumEntryCount: Int = 200,
        maximumCachedTabCount: Int = 24
    ) {
        self.fileManager = fileManager
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumCachedTabCount = max(1, maximumCachedTabCount)

        if let storageURL {
            self.storageURL = storageURL
        } else {
            guard let applicationSupportDirectoryURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                fatalError("Application Support directory is unavailable")
            }
            self.storageURL = applicationSupportDirectoryURL
                .appendingPathComponent("AppData", isDirectory: true)
                .appendingPathComponent("TabSessions", isDirectory: true)
        }

        queue.sync {
            createStorageDirectory()
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
            guard !tombstones.contains(tabID) else {
                return snapshot(from: emptyHistory(), previews: .empty)
            }
            var history = loadHistory(for: tabID)
            var previews = loadPreviews(for: tabID)
            guard history.currentURL != url else {
                return snapshot(from: history, previews: previews)
            }

            if let currentURL = history.currentURL, !currentURL.isEmpty {
                history.backHistory.append(NavigationEntry(url: currentURL))
                trimOldestEntries(in: &history.backHistory)
            }

            history.currentURL = url
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
            guard !tombstones.contains(tabID) else {
                return snapshot(from: emptyHistory(), previews: .empty)
            }
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
            .flatMap { $0.count <= maximumPreviewBytes ? $0 : nil }
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
            pendingWrites.removeValue(forKey: tabID)
            historyCache.removeValue(forKey: tabID)
            previewCache.removeValue(forKey: tabID)
            cacheOrder.removeAll { $0 == tabID }

            let historyURL = self.historyURL(for: tabID)
            let previewDirectoryURL = self.previewDirectoryURL(for: tabID)
            persistenceQueue.async {
                try? self.fileManager.removeItem(at: historyURL)
                try? self.fileManager.removeItem(at: previewDirectoryURL)
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
                pendingWriteCount: pendingWrites.count
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

    private func createStorageDirectory() {
        try? fileManager.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
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
        let fileURL = historyURL(for: tabID)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(StoredHistory.self, from: data) {
            history = decoded
        } else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
            history = emptyHistory()
        }

        historyCache[tabID] = history
        touchCache(tabID)
        return history
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
        let fileURL = previewDirectoryURL(for: tabID)
            .appendingPathComponent("\(name).jpg")
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count <= maximumPreviewBytes else {
            return nil
        }
        return data
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
        pendingWrites[tabID] = PendingWrite(
            generation: generations[tabID] ?? 0,
            history: history,
            previews: previews
        )
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
        let writes = Array(pendingWrites)
        pendingWrites.removeAll(keepingCapacity: true)
        return writes
    }

    private func persist(_ item: (key: UUID, value: PendingWrite)) {
        let tabID = item.key
        let write = item.value
        let isCurrent = queue.sync {
            !tombstones.contains(tabID) && generations[tabID] == write.generation
        }
        guard isCurrent, let data = try? JSONEncoder().encode(write.history) else {
            return
        }

        createStorageDirectory()
        try? data.write(to: historyURL(for: tabID), options: .atomic)

        let previewDirectoryURL = previewDirectoryURL(for: tabID)
        if write.previews.byteCount == 0 {
            try? fileManager.removeItem(at: previewDirectoryURL)
            return
        }
        try? fileManager.createDirectory(
            at: previewDirectoryURL,
            withIntermediateDirectories: true
        )
        persistPreview(write.previews.current, named: "current", in: previewDirectoryURL)
        persistPreview(write.previews.back, named: "back", in: previewDirectoryURL)
        persistPreview(write.previews.forward, named: "forward", in: previewDirectoryURL)
    }

    private func persistPreview(_ data: Data?, named name: String, in directoryURL: URL) {
        let fileURL = directoryURL.appendingPathComponent("\(name).jpg")
        if let data {
            try? data.write(to: fileURL, options: .atomic)
        } else {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func touchCache(_ tabID: UUID) {
        cacheOrder.removeAll { $0 == tabID }
        cacheOrder.append(tabID)
        while cacheOrder.count > maximumCachedTabCount {
            let evicted = cacheOrder.removeFirst()
            historyCache.removeValue(forKey: evicted)
            previewCache.removeValue(forKey: evicted)
            if let pending = pendingWrites[evicted] {
                pendingWrites[evicted] = PendingWrite(
                    generation: pending.generation,
                    history: pending.history,
                    previews: .empty
                )
            }
        }
    }

    private func persistedTabIDs() -> [UUID] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return fileURLs.compactMap { UUID(uuidString: $0.lastPathComponent) }
    }

    private func trimOldestEntries(in entries: inout [NavigationEntry]) {
        let overflow = entries.count - maximumEntryCount
        if overflow > 0 {
            entries.removeFirst(overflow)
        }
    }

    private func trimNewestEntries(in entries: inout [NavigationEntry]) {
        let overflow = entries.count - maximumEntryCount
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

    private func historyURL(for tabID: UUID) -> URL {
        storageURL.appendingPathComponent(tabID.uuidString, isDirectory: false)
    }

    private func previewDirectoryURL(for tabID: UUID) -> URL {
        storageURL.appendingPathComponent("\(tabID.uuidString).previews", isDirectory: true)
    }
}
