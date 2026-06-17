//
//  TabState.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

enum TabNavigationState: Equatable {
    case session(back: Bool, forward: Bool)
    case history(back: Bool, forward: Bool)
    
    var canGoBack: Bool {
        switch self {
        case let .session(back, _), let .history(back, _):
            return back
        }
    }
    
    var canGoForward: Bool {
        switch self {
        case let .session(_, forward), let .history(_, forward):
            return forward
        }
    }
}

enum TabSessionNavigationState: Equatable {
    case unavailable
    case available(back: Bool, forward: Bool)
    
    var canGoBack: Bool {
        guard case let .available(back, _) = self else {
            return false
        }
        return back
    }
    
    var canGoForward: Bool {
        guard case let .available(_, forward) = self else {
            return false
        }
        return forward
    }
}

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
    case pending(String)
}

enum TabDisplayState: Equatable {
    case committed
    case pending(String)
}

enum TabInsertionTarget: Equatable {
    case end
    case afterSelected
    case index(Int)
}

final class TabSessionState {
    var restoreState: TabRestoreState = .none
    var displayState: TabDisplayState = .committed
    var selectionOrder = 0
    var suppressInitialNavigation = true
    var sessionNavigationState = TabSessionNavigationState.unavailable
    var navigationState = TabNavigationState.session(back: false, forward: false)
    var loadingState = TabLoadingState.idle
}
