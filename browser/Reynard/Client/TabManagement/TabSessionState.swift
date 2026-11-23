//
//  TabSessionState.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation
import GeckoView

enum TabLoadingState: Equatable {
    case idle
    case loading(progress: Float)
    
    var isLoading: Bool {
        switch self {
        case .idle:
            return false
        case .loading:
            return true
        }
    }
    
    var progress: Float {
        switch self {
        case .idle:
            return 0
        case let .loading(progress):
            return progress
        }
    }
}

enum TabRestoreState: Equatable {
    case none
    case pendingSession
    case pendingURL(String)
}

enum TabDisplayState: Equatable {
    case committed
    case pending(String)
}

final class TabSessionState {
    var readerMode = ReaderModeState()
    var tabSessionState: GeckoSessionState?
    var restoreState: TabRestoreState = .none
    var suppressInitialNavigation = true
    var isSuppressingInitialBlankPageLoad = false
    var openerTabID: UUID?
    var navigationState = NavigationAvailability(canGoBack: false, canGoForward: false)
    var preparedNavigationThumbnailURL: String?
    var committedEngineURL: String?
    var displayedHistoryEntry: GeckoSessionHistoryIdentifier?
    var displayState: TabDisplayState = .committed
    var loadingState = TabLoadingState.idle
    var loadError: WebRequestError?
    var isPlayingAudio = false
    var showsStartupHomepage = false
    var selectionOrder = 0
}

extension TabSessionState {
    var matchingHistoryEntry: GeckoSessionHistoryIdentifier? {
        guard let tabSessionState,
              let currentHistoryIndex = tabSessionState.currentHistoryIndex,
              let entry = tabSessionState.history[safe: currentHistoryIndex],
              entry.url == committedEngineURL else {
            return nil
        }
        return entry.identifier
    }
}
