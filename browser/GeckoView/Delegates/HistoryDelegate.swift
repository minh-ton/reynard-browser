//
//  HistoryDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 11/7/26.
//

import Foundation

// MARK: - History Delegate

public protocol HistoryDelegate {
    func onVisited(session: GeckoSession, url: String, lastVisitedURL: String?, flags: Int) async -> Bool
    func getVisited(session: GeckoSession, urls: [String]) async -> [Bool]?
}

public extension HistoryDelegate {
    func onVisited(session: GeckoSession, url: String, lastVisitedURL: String?, flags: Int) async -> Bool {
        return false
    }
    
    func getVisited(session: GeckoSession, urls: [String]) async -> [Bool]? {
        return nil
    }
}

// MARK: - History Events

enum HistoryEvents: String, CaseIterable {
    case onVisited = "GeckoView:OnVisited"
    case getVisited = "GeckoView:GetVisited"
}

// MARK: - History Handler

func newHistoryHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewHistory",
        events: HistoryEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = HistoryEvents(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        let delegate = delegate as? HistoryDelegate
        switch event {
        case .onVisited:
            guard let url = message?["url"] as? String else {
                return false
            }
            
            return await delegate?.onVisited(
                session: session,
                url: url,
                lastVisitedURL: message?["lastVisitedURL"] as? String,
                flags: PayloadValue.int(message?["flags"]) ?? 0
            ) ?? false
            
        case .getVisited:
            let urls = PayloadValue.strings(message?["urls"])
            return await delegate?.getVisited(session: session, urls: urls)
        }
    }
}
