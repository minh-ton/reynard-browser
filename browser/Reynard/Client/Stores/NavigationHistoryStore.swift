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
    
    private struct NavigationEntry: Codable {
        var url: String
        var thumbnailData: Data?
    }
    
    private struct StoredHistory: Codable {
        var currentURL: String?
        var currentThumbnailData: Data?
        var backHistory: [NavigationEntry]
        var forwardHistory: [NavigationEntry]
        var usesStoredHistory: Bool?
        
        private enum CodingKeys: String, CodingKey {
            case currentURL
            case currentThumbnailData = "currentThumbnail"
            case backHistory = "backList"
            case forwardHistory = "forwardList"
            case usesStoredHistory = "ownsNav"
        }
        
        init(
            currentURL: String?,
            currentThumbnailData: Data?,
            backHistory: [NavigationEntry],
            forwardHistory: [NavigationEntry],
            usesStoredHistory: Bool?
        ) {
            self.currentURL = currentURL
            self.currentThumbnailData = currentThumbnailData
            self.backHistory = backHistory
            self.forwardHistory = forwardHistory
            self.usesStoredHistory = usesStoredHistory
        }
        
    }
    
    private let thumbnailJPEGQuality = 0.8
    private let fileManager: FileManager
    private let storageURL: URL
    private let maximumEntryCount: Int
    private let queue = DispatchQueue(label: "com.minh-ton.Reynard.NavigationHistoryStore.Queue", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "com.minh-ton.Reynard.NavigationHistoryStore.Persistence", qos: .utility)
    private var historyCache: [UUID: StoredHistory] = [:]
    
    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        maximumEntryCount: Int = 200
    ) {
        self.fileManager = fileManager
        self.maximumEntryCount = max(1, maximumEntryCount)
        
        if let storageURL {
            self.storageURL = storageURL
        } else {
            guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
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
            return snapshot(from: history)
        }
    }
    
    func recordNavigation(to url: String, for tabID: UUID) -> Snapshot {
        queue.sync {
            var history = loadHistory(for: tabID)
            guard history.currentURL != url else {
                return snapshot(from: history)
            }
            
            if let currentURL = history.currentURL,
               !currentURL.isEmpty {
                history.backHistory.append(NavigationEntry(
                    url: currentURL,
                    thumbnailData: history.currentThumbnailData
                ))
                trimOldestEntries(in: &history.backHistory)
            }
            
            history.currentURL = url
            history.currentThumbnailData = nil
            history.forwardHistory.removeAll(keepingCapacity: false)
            saveHistory(history, for: tabID)
            return snapshot(from: history)
        }
    }
    
    func setUsesPersistedHistory(_ usesPersistedHistory: Bool, for tabID: UUID) -> Snapshot {
        queue.sync {
            var history = loadHistory(for: tabID)
            history.usesStoredHistory = usesPersistedHistory
            saveHistory(history, for: tabID)
            return snapshot(from: history)
        }
    }
    
    func goBack(for tabID: UUID) -> String? {
        queue.sync {
            var history = loadHistory(for: tabID)
            guard let target = history.backHistory.popLast() else {
                return nil
            }
            
            if let currentURL = history.currentURL,
               !currentURL.isEmpty {
                history.forwardHistory.insert(NavigationEntry(
                    url: currentURL,
                    thumbnailData: history.currentThumbnailData
                ), at: 0)
                trimNewestEntries(in: &history.forwardHistory)
            }
            
            history.currentURL = target.url
            history.currentThumbnailData = target.thumbnailData
            saveHistory(history, for: tabID)
            return target.url
        }
    }
    
    func goForward(for tabID: UUID) -> String? {
        queue.sync {
            var history = loadHistory(for: tabID)
            guard !history.forwardHistory.isEmpty else {
                return nil
            }
            
            let target = history.forwardHistory.removeFirst()
            if let currentURL = history.currentURL,
               !currentURL.isEmpty {
                history.backHistory.append(NavigationEntry(
                    url: currentURL,
                    thumbnailData: history.currentThumbnailData
                ))
                trimOldestEntries(in: &history.backHistory)
            }
            
            history.currentURL = target.url
            history.currentThumbnailData = target.thumbnailData
            saveHistory(history, for: tabID)
            return target.url
        }
    }
    
    func updateCurrentHistoryThumbnail(_ image: NavigationPreviewImage?, for tabID: UUID, matching url: String) {
        queue.async {
            var history = self.loadHistory(for: tabID)
            guard history.currentURL == url else {
                return
            }
            
            history.currentThumbnailData = image?.jpegData(compressionQuality: self.thumbnailJPEGQuality)
            self.saveHistory(history, for: tabID)
        }
    }
    
    func invalidateThumbnails() {
        queue.sync {
            guard let fileURLs = try? self.fileManager.contentsOfDirectory(
                at: self.storageURL,
                includingPropertiesForKeys: nil
            ) else {
                return
            }
            
            fileURLs.forEach { fileURL in
                guard let tabID = UUID(uuidString: fileURL.lastPathComponent) else {
                    return
                }
                
                var history = self.loadHistory(for: tabID)
                history.currentThumbnailData = nil
                history.backHistory = history.backHistory.map {
                    NavigationEntry(url: $0.url, thumbnailData: nil)
                }
                history.forwardHistory = history.forwardHistory.map {
                    NavigationEntry(url: $0.url, thumbnailData: nil)
                }
                self.saveHistory(history, for: tabID)
            }
        }
    }
    
    func removeNavigationHistory(for tabID: UUID) {
        queue.sync {
            self.historyCache.removeValue(forKey: tabID)
            let fileURL = self.historyURL(for: tabID)
            self.persistenceQueue.async {
                guard self.fileManager.fileExists(atPath: fileURL.path) else {
                    return
                }
                try? self.fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    private func createStorageDirectory() {
        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }
    
    private func loadHistory(for tabID: UUID) -> StoredHistory {
        if let history = historyCache[tabID] {
            return history
        }
        let history: StoredHistory
        guard let data = try? Data(contentsOf: historyURL(for: tabID)),
              let decoded = try? JSONDecoder().decode(StoredHistory.self, from: data) else {
            history = StoredHistory(
                currentURL: nil,
                currentThumbnailData: nil,
                backHistory: [],
                forwardHistory: [],
                usesStoredHistory: nil
            )
            historyCache[tabID] = history
            return history
        }
        history = decoded
        historyCache[tabID] = history
        return history
    }
    
    private func saveHistory(_ history: StoredHistory, for tabID: UUID) {
        historyCache[tabID] = history
        guard let data = try? JSONEncoder().encode(history) else {
            return
        }
        let fileURL = historyURL(for: tabID)
        persistenceQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
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

    func flushPendingWritesForTesting() {
        persistenceQueue.sync {}
    }
    
    private func snapshot(from history: StoredHistory) -> Snapshot {
        Snapshot(
            currentURL: history.currentURL,
            backHistory: history.backHistory.map(\.url),
            forwardHistory: history.forwardHistory.map(\.url),
            canGoBack: !history.backHistory.isEmpty,
            canGoForward: !history.forwardHistory.isEmpty,
            backPreviewImage: history.backHistory.last?.thumbnailData.flatMap(NavigationPreviewImage.init(data:)),
            forwardPreviewImage: history.forwardHistory.first?.thumbnailData.flatMap(NavigationPreviewImage.init(data:)),
            usesStoredHistory: history.usesStoredHistory ?? false
        )
    }
    
    private func historyURL(for tabID: UUID) -> URL {
        storageURL.appendingPathComponent(tabID.uuidString, isDirectory: false)
    }
}
