//
//  NavigationState.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

struct NavigationAvailability: Equatable {
    let canGoBack: Bool
    let canGoForward: Bool
}

enum SessionNavigationAvailability: Equatable {
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

enum NavigationAction {
    case session
    case load(String)
}

struct NavigationTransition {
    let action: NavigationAction
    let availability: NavigationAvailability
}
