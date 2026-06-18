//
//  NavigationHistory.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation

final class NavigationHistory {
    private let store: NavigationHistoryStore

    init(store: NavigationHistoryStore = .shared) {
        self.store = store
    }

    func restoreState(for tabID: UUID) -> NavigationAvailability {
        let snapshot = store.loadSnapshot(for: tabID)
        if snapshot.canGoBack || snapshot.canGoForward {
            _ = store.setUsesStoredHistory(true, for: tabID)
        }
        return availability(for: tabID, sessionState: .unavailable)
    }

    func availability(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        let snapshot = store.loadSnapshot(for: tabID)
        if snapshot.usesStoredHistory {
            return NavigationAvailability(
                canGoBack: snapshot.canGoBack,
                canGoForward: snapshot.canGoForward
            )
        }
        return NavigationAvailability(
            canGoBack: snapshot.canGoBack || sessionState.canGoBack,
            canGoForward: snapshot.canGoForward || sessionState.canGoForward
        )
    }

    func record(
        to url: String,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              trimmedURL.lowercased() != "about:blank" else {
            return availability(for: tabID, sessionState: sessionState)
        }
        _ = store.record(trimmedURL, for: tabID)
        return availability(for: tabID, sessionState: sessionState)
    }

    func goBack(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        let snapshot = store.loadSnapshot(for: tabID)
        if !snapshot.usesStoredHistory && sessionState.canGoBack {
            _ = store.moveBack(for: tabID)
            return NavigationTransition(
                action: .session,
                availability: availability(for: tabID, sessionState: sessionState)
            )
        }

        guard let url = store.moveBack(for: tabID) else {
            return nil
        }
        _ = store.setUsesStoredHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }

    func goForward(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        let snapshot = store.loadSnapshot(for: tabID)
        if !snapshot.usesStoredHistory && sessionState.canGoForward {
            _ = store.moveForward(for: tabID)
            return NavigationTransition(
                action: .session,
                availability: availability(for: tabID, sessionState: sessionState)
            )
        }

        guard let url = store.moveForward(for: tabID) else {
            return nil
        }
        _ = store.setUsesStoredHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }

    func useStoredHistory(for tabID: UUID) -> NavigationAvailability {
        _ = store.setUsesStoredHistory(true, for: tabID)
        return availability(for: tabID, sessionState: .unavailable)
    }

    func removeHistory(for tabID: UUID) {
        store.removeHistory(for: tabID)
    }
}
