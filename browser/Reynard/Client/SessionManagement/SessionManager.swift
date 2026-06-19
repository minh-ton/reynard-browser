//
//  SessionManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView

final class SessionManager {
    private let settings: SessionSettingsManager
    private let history: NavigationHistory
    private let permissionStore: SitePermissionStore
    
    init(
        settings: SessionSettingsManager = SessionSettingsManager(),
        history: NavigationHistory = NavigationHistory(),
        permissionStore: SitePermissionStore = .shared
    ) {
        self.settings = settings
        self.history = history
        self.permissionStore = permissionStore
    }
    
    // MARK: - Session Creation
    
    func createSession(
        url: String?,
        tabID: UUID?,
        isPrivate: Bool,
        isAddonPopup: Bool = false,
        opening: SessionOpening,
        delegates: SessionDelegates
    ) -> GeckoSession {
        let initialSettings = url.map { settings.settings(for: $0, tabID: tabID) } ?? .default
        let session = GeckoSession(
            settings: initialSettings,
            isPrivateMode: isPrivate,
            isAddonPopup: isAddonPopup
        )
        bindDelegates(to: session, delegates: delegates)
        
        if case let .immediate(windowID) = opening {
            session.open(windowId: windowID)
            deactivate(session)
        }
        return session
    }
    
    func bindDelegates(to session: GeckoSession, delegates: SessionDelegates) {
        session.contentDelegate = delegates.content
        session.navigationDelegate = delegates.navigation
        session.permissionDelegate = delegates.permission
        session.progressDelegate = delegates.progress
        session.promptDelegate = delegates.prompt
        session.selectionActionDelegate = delegates.selectionAction
        session.mediaSessionDelegate = delegates.mediaSession
    }
    
    func adopt(
        _ session: GeckoSession,
        asTab tabID: UUID,
        url: String,
        delegates: SessionDelegates
    ) {
        deactivate(session)
        bindDelegates(to: session, delegates: delegates)
        settings.update(session, for: url, tabID: tabID)
    }
    
    // MARK: - Session Lifecycle
    
    func open(_ session: GeckoSession, windowID: String? = nil) {
        session.open(windowId: windowID)
    }
    
    func activate(_ session: GeckoSession) {
        guard session.isOpen() else {
            return
        }
        session.setActive(true)
        session.setFocused(true)
    }
    
    func deactivate(_ session: GeckoSession) {
        guard session.isOpen() else {
            return
        }
        session.setFocused(false)
        session.setActive(false)
    }
    
    func close(_ session: GeckoSession) {
        deactivate(session)
        permissionStore.removePrivateActions(for: session)
        session.close()
    }
    
    func discard(_ session: GeckoSession, forTab tabID: UUID) {
        settings.clearWebsiteOverrides(for: tabID)
        history.removeHistory(for: tabID)
        close(session)
    }
    
    // MARK: - Settings
    
    func updateSettings(of session: GeckoSession, for url: String, tabID: UUID?) {
        settings.update(session, for: url, tabID: tabID)
    }
    
    func isDesktopMode(for url: String, tabID: UUID) -> Bool? {
        return settings.isDesktopMode(for: url, tabID: tabID)
    }
    
    func toggleWebsiteMode(for url: String, tabID: UUID) -> WebsiteModeAction? {
        return settings.toggleWebsiteMode(for: url, tabID: tabID)
    }
    
    func needsSettingsUpdate(
        to session: GeckoSession,
        currentURL: String?,
        requestedURL: String,
        tabID: UUID
    ) -> Bool {
        settings.needsUpdate(
            to: session,
            currentURL: currentURL,
            requestedURL: requestedURL,
            tabID: tabID
        )
    }
    
    // MARK: - Navigation
    
    func restoreNavigation(for tabID: UUID) -> NavigationAvailability {
        return history.restoreState(for: tabID)
    }
    
    func navigationAvailability(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        return history.availability(for: tabID, sessionState: sessionState)
    }
    
    func recordNavigation(
        to url: String,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        return history.record(to: url, for: tabID, sessionState: sessionState)
    }
    
    func goBack(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goBack(for: tabID, sessionState: sessionState)
    }
    
    func goForward(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goForward(for: tabID, sessionState: sessionState)
    }
    
    func useStoredNavigationHistory(for tabID: UUID) -> NavigationAvailability {
        return history.useStoredHistory(for: tabID)
    }
}
