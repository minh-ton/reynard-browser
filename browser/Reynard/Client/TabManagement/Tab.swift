//
//  Tab.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import GeckoView
import UIKit

final class Tab {
    let id: UUID
    var session: GeckoSession
    var title: String
    var url: String?
    let createdAt: Date?
    var isPrivate: Bool
    var favicon: UIImage?
    var thumbnail: UIImage?
    var isMuted: Bool
    let state = TabSessionState()
    
    var mode: TabMode {
        return isPrivate ? .private : .regular
    }
    
    var sessionHandler: TabSessionHandler {
        didSet {
            sessionHandler.tab = self
        }
    }
    
    init(
        id: UUID = UUID(),
        session: GeckoSession,
        sessionHandler: TabSessionHandler,
        title: String = "",
        url: String? = nil,
        createdAt: Date? = Date(),
        favicon: UIImage? = nil,
        thumbnail: UIImage? = nil,
        isMuted: Bool = false,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.session = session
        self.sessionHandler = sessionHandler
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.favicon = favicon
        self.thumbnail = thumbnail
        self.isMuted = isMuted
        self.isPrivate = isPrivate
        
        sessionHandler.tab = self
    }
}

extension Tab {
    var displayedURL: String? {
        switch state.displayState {
        case let .pending(pendingURL):
            return URLUtils.restorableURL(from: pendingURL)
        case .committed:
            return URLUtils.restorableURL(from: url)
        }
    }
    
    var shareableURL: URL? {
        guard let value = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "about:blank",
              let url = URL(string: value),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }
    
    var displayedSessionState: GeckoSessionState? {
        guard state.displayedHistoryEntry != nil,
              state.matchingHistoryEntry == state.displayedHistoryEntry else {
            return nil
        }
        return state.tabSessionState
    }
    
    var navigationPreviewImages: NavigationPreviewImages {
        guard let sessionState = displayedSessionState else {
            return NavigationPreviewImages(backImage: nil, forwardImage: nil)
        }
        
        let navigationHistoryStore = NavigationHistoryStore.shared
        return NavigationPreviewImages(
            backImage: navigationHistoryStore.thumbnail(for: sessionState.backHistory.first?.identifier, in: id),
            forwardImage: navigationHistoryStore.thumbnail(for: sessionState.forwardHistory.first?.identifier, in: id)
        )
    }
}
