//
//  SessionManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView
import UIKit

protocol SessionManagerApplicationStateObserver: AnyObject {
    func sessionManagerDidChangeApplicationState(_ sessionManager: SessionManager)
    func sessionManagerWillResignActive(_ sessionManager: SessionManager)
}

protocol SessionManagerPictureInPictureHandler: AnyObject {
    func stopPresenting(_ session: GeckoSession) -> Bool
}

final class SessionManager {
    private let sessionSettings: SessionSettingsManager
    private let history: NavigationHistory
    private let permissionStore: SitePermissionStore
    
    private var sessionsRequestedActive: [ObjectIdentifier: GeckoSession] = [:]
    private var isApplicationForeground = true
    private weak var pictureInPictureSession: GeckoSession?
    private var pendingCleanup: (
        session: GeckoSession,
        perform: (SessionManager) -> Void
    )?
    weak var applicationStateObserver: SessionManagerApplicationStateObserver?
    weak var pictureInPictureHandler: SessionManagerPictureInPictureHandler?
    
    var isForeground: Bool {
        return isApplicationForeground
    }
    
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
        session.historyDelegate = delegates.history
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
        if pictureInPictureSession === session {
            return
        }
        session.setActive(false)
    }
    
    func setApplicationForeground(_ isForeground: Bool) {
        guard isApplicationForeground != isForeground else {
            return
        }
        isApplicationForeground = isForeground
        for session in sessionsRequestedActive.values {
            session.setActive(isForeground || pictureInPictureSession === session)
            if pictureInPictureSession === session {
                session.setFocused(isForeground)
            }
        }
        if let pictureInPictureSession,
           sessionsRequestedActive[ObjectIdentifier(pictureInPictureSession)] == nil {
            pictureInPictureSession.setFocused(false)
            pictureInPictureSession.setActive(true)
        }
        applicationStateObserver?.sessionManagerDidChangeApplicationState(self)
    }
    
    func applicationWillResignActive() {
        applicationStateObserver?.sessionManagerWillResignActive(self)
    }
    
    func applicationDidBecomeActive() {
        applicationStateObserver?.sessionManagerDidChangeApplicationState(self)
    }
    
    func close(_ session: GeckoSession) {
        performCleanup(for: session) { manager in
            manager.closeImmediately(session)
        }
    }
    
    func discard(_ session: GeckoSession, forTab tabID: UUID, keepingHistory: Bool = false) {
        performCleanup(for: session) { manager in
            manager.discardImmediately(
                session,
                forTab: tabID,
                keepingHistory: keepingHistory
            )
        }
    }
    
    // MARK: - Picture in Picture
    
    func setPictureInPictureSession(_ session: GeckoSession) {
        pictureInPictureSession = session
        if !isApplicationForeground {
            session.setFocused(false)
        }
        session.setActive(true)
    }
    
    func pictureInPicturePresentationDidEnd(_ session: GeckoSession) {
        clearPictureInPictureSession(session)
        executePendingCleanup(for: session)
    }
    
    private func clearPictureInPictureSession(_ session: GeckoSession) {
        guard pictureInPictureSession === session else {
            return
        }
        pictureInPictureSession = nil
        if isApplicationForeground,
           sessionsRequestedActive[ObjectIdentifier(session)] != nil {
            session.setActive(true)
            session.setFocused(true)
        } else {
            session.setFocused(false)
            session.setActive(false)
        }
    }
    
    private func performCleanup(
        for session: GeckoSession,
        _ perform: @escaping (SessionManager) -> Void
    ) {
        if let pendingCleanup {
            if pendingCleanup.session !== session {
                perform(self)
            }
            return
        }
        pendingCleanup = (session, perform)
        if pictureInPictureHandler?.stopPresenting(session) != true {
            executePendingCleanup(for: session)
        }
    }
    
    private func executePendingCleanup(for session: GeckoSession) {
        guard let cleanup = pendingCleanup,
              cleanup.session === session else {
            return
        }
        pendingCleanup = nil
        cleanup.perform(self)
    }
    
    private func closeImmediately(_ session: GeckoSession) {
        deactivate(session)
        permissionStore.removePrivateActions(for: session)
        session.close()
    }
    
    private func discardImmediately(
        _ session: GeckoSession,
        forTab tabID: UUID,
        keepingHistory: Bool
    ) {
        sessionSettings.websiteMode.clearWebsiteOverrides(for: tabID)
        if !keepingHistory {
            history.removeHistory(for: tabID)
        }
        closeImmediately(session)
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
    
    func updateCurrentHistoryThumbnail(_ image: UIImage?, for tabID: UUID, matching url: String) {
        history.updateCurrentHistoryThumbnail(image, for: tabID, matching: url)
    }
    
    func navigationPreviewImages(for tabID: UUID) -> NavigationPreviewImages {
        return history.previewImages(for: tabID)
    }
    
    func invalidateNavigationThumbnails() {
        history.invalidateThumbnails()
    }
}
