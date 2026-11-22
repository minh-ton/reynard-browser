//
//  GeckoSessionState.swift
//  Reynard
//
//  Created by Minh Ton on 31/8/26.
//

import Foundation

nonisolated public struct GeckoSessionHistoryIdentifier: Codable, Hashable, Sendable {
    public let id: Int
    public let docshellUUID: String
}

nonisolated public struct GeckoSessionHistoryItem {
    public let identifier: GeckoSessionHistoryIdentifier?
    public let url: String
    public let title: String?
}

public final class GeckoSessionState {
    // MARK: - State
    
    private var payload: [String: Any]
    
    public var history: [GeckoSessionHistoryItem] {
        return historyEntries.compactMap { entry -> GeckoSessionHistoryItem? in
            guard let url = entry["url"] as? String else {
                return nil
            }
            let identifier: GeckoSessionHistoryIdentifier?
            if let id = PayloadValue.int(entry["ID"]),
               let docshellUUID = entry["docshellUUID"] as? String {
                identifier = GeckoSessionHistoryIdentifier(id: id, docshellUUID: docshellUUID)
            } else {
                identifier = nil
            }
            return GeckoSessionHistoryItem(
                identifier: identifier,
                url: url,
                title: entry["title"] as? String
            )
        }
    }
    
    public var currentHistoryIndex: Int? {
        guard let history = payload["history"] as? [String: Any],
              let index = PayloadValue.int(history["index"]) else {
            return nil
        }
        return index - 1
    }
    
    public var backHistory: [GeckoSessionHistoryItem] {
        guard let currentHistoryIndex else {
            return []
        }
        return history.prefix(currentHistoryIndex).reversed()
    }
    
    public var forwardHistory: [GeckoSessionHistoryItem] {
        guard let currentHistoryIndex else {
            return []
        }
        return Array(history.dropFirst(currentHistoryIndex + 1))
    }
    
    public var isEmpty: Bool {
        return historyEntries.isEmpty
    }
    
    var restorePayload: [String: Any] {
        return payload
    }
    
    private var historyEntries: [[String: Any]] {
        guard let history = payload["history"] as? [String: Any] else {
            return []
        }
        return history["entries"] as? [[String: Any]] ?? []
    }
    
    // MARK: - Initialization
    
    init() {
        payload = [:]
    }
    
    private init(payload: [String: Any]) {
        self.payload = payload
    }
    
    public convenience init(copying state: GeckoSessionState) {
        self.init(payload: state.payload)
    }
    
    public convenience init?(serializedString: String) {
        guard let value = try? JSONSerialization.jsonObject(
            with: Data(serializedString.utf8)
        ),
              let payload = value as? [String: Any] else {
            return nil
        }
        self.init(payload: payload)
    }
    
    // MARK: - Serialization
    
    public func serializedString() -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
    
    // MARK: - State Updates
    
    func replace(with state: GeckoSessionState) {
        payload = state.payload
    }
    
    func update(with stateUpdate: [String: Any]) {
        if let historyChange = stateUpdate["historychange"] as? [String: Any] {
            updateHistory(with: historyChange)
        }
        if let scroll = stateUpdate["scroll"] as? [String: Any] {
            payload["scrolldata"] = scroll
        }
        if let formData = stateUpdate["formdata"] as? [String: Any] {
            payload["formdata"] = formData
        }
    }
    
    private func updateHistory(with historyChange: [String: Any]) {
        let lastHistoryIndex = Int(Int32.max) - 1
        let fromIndex = PayloadValue.int(historyChange["fromIdx"]) ?? -1
        var updatedHistory = historyChange
        
        guard fromIndex != -1 else {
            payload["history"] = updatedHistory
            return
        }
        
        updatedHistory.removeValue(forKey: "fromIdx")
        let updatedEntries = updatedHistory["entries"] as? [[String: Any]] ?? []
        if fromIndex >= lastHistoryIndex {
            let history = payload["history"] as? [String: Any]
            updatedHistory["entries"] = history?["entries"] as? [[String: Any]] ?? []
        } else if let history = payload["history"] as? [String: Any],
                  let historyEntries = history["entries"] as? [[String: Any]] {
            let retainedCount = max(fromIndex + 1, 0)
            let retainedEntries = Array(historyEntries.prefix(retainedCount))
            updatedHistory["entries"] = retainedEntries + updatedEntries
        } else {
            updatedHistory["entries"] = []
        }
        payload["history"] = updatedHistory
    }
}
