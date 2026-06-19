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
        let usesStoredHistory: Bool
        
        var canGoBack: Bool {
            return !backHistory.isEmpty
        }
        
        var canGoForward: Bool {
            return !forwardHistory.isEmpty
        }
    }
    
    private struct StoredHistory: Codable {
        var currentURL: String?
        var backHistory: [String]
        var forwardHistory: [String]
        var usesStoredHistory: Bool?
        
        private enum CodingKeys: String, CodingKey {
            case currentURL
            case backHistory = "backList"
            case forwardHistory = "forwardList"
            case usesStoredHistory = "ownsNav"
        }
    }
    
    private let fileManager: FileManager
    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.minh-ton.Reynard.NavigationHistoryStore.Queue", qos: .userInitiated)
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        self.storageURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("TabSessions", isDirectory: true)
        
        queue.sync {
            createStorageDirectory()
        }
    }
    
    func currentSnapshot(for tabID: UUID) -> Snapshot {
        queue.sync {
            let history = loadHistory(for: tabID)
            return Snapshot(
                currentURL: history.currentURL,
                backHistory: history.backHistory,
                forwardHistory: history.forwardHistory,
                usesStoredHistory: history.usesStoredHistory ?? false
            )
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
                history.backHistory.append(currentURL)
            }
            
            history.currentURL = url
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
            guard let targetURL = history.backHistory.popLast() else {
                return nil
            }
            
            if let currentURL = history.currentURL,
               !currentURL.isEmpty {
                history.forwardHistory.insert(currentURL, at: 0)
            }
            
            history.currentURL = targetURL
            saveHistory(history, for: tabID)
            return targetURL
        }
    }
    
    func goForward(for tabID: UUID) -> String? {
        queue.sync {
            var history = loadHistory(for: tabID)
            guard !history.forwardHistory.isEmpty else {
                return nil
            }
            
            let targetURL = history.forwardHistory.removeFirst()
            if let currentURL = history.currentURL,
               !currentURL.isEmpty {
                history.backHistory.append(currentURL)
            }
            
            history.currentURL = targetURL
            saveHistory(history, for: tabID)
            return targetURL
        }
    }
    
    func removeNavigationHistory(for tabID: UUID) {
        queue.async {
            let fileURL = self.historyURL(for: tabID)
            guard self.fileManager.fileExists(atPath: fileURL.path) else {
                return
            }
            
            try? self.fileManager.removeItem(at: fileURL)
        }
    }
    
    private func createStorageDirectory() {
        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }
    
    private func loadHistory(for tabID: UUID) -> StoredHistory {
        guard let data = try? Data(contentsOf: historyURL(for: tabID)),
              let decoded = try? JSONDecoder().decode(StoredHistory.self, from: data) else {
            return StoredHistory(
                currentURL: nil,
                backHistory: [],
                forwardHistory: [],
                usesStoredHistory: nil
            )
        }
        
        return decoded
    }
    
    private func saveHistory(_ history: StoredHistory, for tabID: UUID) {
        guard let data = try? JSONEncoder().encode(history) else {
            return
        }
        
        try? data.write(to: historyURL(for: tabID), options: .atomic)
    }
    
    private func snapshot(from history: StoredHistory) -> Snapshot {
        Snapshot(
            currentURL: history.currentURL,
            backHistory: history.backHistory,
            forwardHistory: history.forwardHistory,
            usesStoredHistory: history.usesStoredHistory ?? false
        )
    }
    
    private func historyURL(for tabID: UUID) -> URL {
        storageURL.appendingPathComponent(tabID.uuidString, isDirectory: false)
    }
}
