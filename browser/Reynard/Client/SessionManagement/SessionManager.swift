//
//  SessionManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView

final class SessionManager {
    private let sessionSettings: SessionSettingsManager
    private let history: NavigationHistory
    private let permissionStore: SitePermissionStore
    
    private var sessionsRequestedActive: [ObjectIdentifier: GeckoSession] = [:]
    private var isApplicationForeground = true
    
    init(
        sessionSettings: SessionSettingsManager = SessionSettingsManager(),
        history: NavigationHistory = NavigationHistory(),
        permissionStore: SitePermissionStore = .shared
    ) {
        self.sessionSettings = sessionSettings
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
        let session = GeckoSession(
            settings: sessionSettings.settings(for: url, tabID: tabID),
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
        updateSettings(of: session, for: url, tabID: tabID)
    }
    
    // MARK: - Session Lifecycle
    
    func open(_ session: GeckoSession, windowID: String? = nil) {
        session.open(windowId: windowID)
    }
    
    func activate(_ session: GeckoSession) {
        guard session.isOpen() else {
            return
        }
        sessionsRequestedActive[ObjectIdentifier(session)] = session
        session.setActive(isApplicationForeground)
        session.setFocused(true)
    }
    
    func deactivate(_ session: GeckoSession) {
        sessionsRequestedActive.removeValue(forKey: ObjectIdentifier(session))
        guard session.isOpen() else {
            return
        }
        session.setFocused(false)
        session.setActive(false)
    }
    
    func setApplicationForeground(_ isForeground: Bool) {
        guard isApplicationForeground != isForeground else {
            return
        }
        isApplicationForeground = isForeground
        for session in sessionsRequestedActive.values {
            session.setActive(isForeground)
        }
    }
    
    func close(_ session: GeckoSession) {
        deactivate(session)
        permissionStore.removePrivateActions(for: session)
        session.close()
    }
    
    func discard(_ session: GeckoSession, forTab tabID: UUID, keepingHistory: Bool = false) {
        sessionSettings.websiteMode.clearWebsiteOverrides(for: tabID)
        if !keepingHistory {
            history.removeHistory(for: tabID)
        }
        close(session)
    }
    
    // MARK: - Addon Tab State
    
    func setAddonTabActive(_ active: Bool, for session: GeckoSession) {
        session.setAddonTabActive(active)
    }
    
    func transferAddonTabActivation(from previousSession: GeckoSession, to replacementSession: GeckoSession) {
        setAddonTabActive(false, for: previousSession)
        setAddonTabActive(true, for: replacementSession)
    }
    
    // MARK: - Website Settings
    
    func updateSettings(of session: GeckoSession, for url: String, tabID: UUID?) {
        session.updateSettings(sessionSettings.settings(for: url, tabID: tabID))
    }
    
    func setPageZoom(_ level: Int, of session: GeckoSession, for url: String, tabID: UUID?) {
        sessionSettings.pageZoom.save(level, for: url)
        updateSettings(of: session, for: url, tabID: tabID)
    }
    
    func isDesktopMode(for url: String, tabID: UUID) -> Bool? {
        return sessionSettings.websiteMode.isDesktopMode(for: url, tabID: tabID)
    }
    
    func toggleWebsiteMode(for url: String, tabID: UUID) -> WebsiteModeAction? {
        return sessionSettings.websiteMode.toggleWebsiteMode(for: url, tabID: tabID)
    }
    
    func needsSettingsUpdate(
        to session: GeckoSession,
        currentURL: String?,
        requestedURL: String,
        tabID: UUID
    ) -> Bool {
        sessionSettings.needsUpdate(
            for: session,
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
