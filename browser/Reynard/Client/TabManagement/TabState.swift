//
//  TabState.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

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
    var isSuppressingInitialBlankPageLoad = false
    var sessionNavigationAvailability = SessionNavigationAvailability.unavailable
    var navigationState = NavigationAvailability(canGoBack: false, canGoForward: false)
    var loadingState = TabLoadingState.idle
}
