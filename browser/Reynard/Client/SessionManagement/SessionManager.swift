//
//  SessionManager.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView
import UIKit

final class SessionManager {
    private let sessionSettings: SessionSettingsManager
    private let history: NavigationHistory
    private let tabStore: TabManagementStore
    private let permissionStore: SitePermissionStore
    let universalLinkManager = UniversalLinkManager()
    let trackingProtection: TrackingProtectionManager
    
    private var sessionsRequestedActive: [ObjectIdentifier: GeckoSession] = [:]
    private var pageBackgroundColors: [ObjectIdentifier: UIColor] = [:]
    private var isApplicationForeground = true
    private(set) var isApplicationActive = true
    private var sessionStateBackgroundTask = UIBackgroundTaskIdentifier.invalid
    private var externalResponseReferenceCounts: [ObjectIdentifier: Int] = [:]
    private var deferredExternalResponseCleanups: [ObjectIdentifier: (
        session: GeckoSession,
        perform: (SessionManager) -> Void
    )] = [:]
    
    var isForeground: Bool {
        return isApplicationForeground
    }
    
    init(
        sessionSettings: SessionSettingsManager = SessionSettingsManager(),
        history: NavigationHistory = NavigationHistory(),
        tabStore: TabManagementStore = .shared,
        permissionStore: SitePermissionStore = .shared,
        trackingProtection: TrackingProtectionManager = TrackingProtectionManager()
    ) {
        self.sessionSettings = sessionSettings
        self.history = history
        self.tabStore = tabStore
        self.permissionStore = permissionStore
        self.trackingProtection = trackingProtection
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
        session.contentBlockingDelegate = trackingProtection
        session.navigationDelegate = delegates.navigation
        session.historyDelegate = delegates.history
        session.permissionDelegate = delegates.permission
        session.progressDelegate = delegates.progress
        session.scrollDelegate = delegates.scroll
        session.promptDelegate = delegates.prompt
        session.printDelegate = delegates.print
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
    
    // MARK: - Application Lifecycle
    
    func setApplicationForeground(_ isForeground: Bool) {
        guard isApplicationForeground != isForeground else {
            return
        }
        isApplicationForeground = isForeground
        for session in sessionsRequestedActive.values {
            session.setActive(isForeground)
        }
    }
    
    func applicationWillResignActive() {
        history.flushPendingWrites()
        isApplicationActive = false
        persistSessionState()
    }
    
    func applicationDidBecomeActive() {
        isApplicationActive = true
    }
    
    // MARK: - Session State Persistence
    
    private func persistSessionState() {
        guard sessionStateBackgroundTask == .invalid else {
            return
        }
        let sessions = Array(sessionsRequestedActive.values)
        sessionStateBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Session State Persistence"
        ) { [weak self] in
            self?.endSessionStateBackgroundTask()
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                endSessionStateBackgroundTask()
            }
            do {
                for session in sessions where session.isOpen() {
                    try await session.flushSessionState()
                }
                tabStore.flushPendingWrites()
            } catch {
                NSLog("Failed to persist session state before suspension: %@", "\(error)")
            }
        }
    }
    
    private func endSessionStateBackgroundTask() {
        guard sessionStateBackgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(sessionStateBackgroundTask)
        sessionStateBackgroundTask = .invalid
    }
    
    // MARK: - External Responses
    
    private func keepSessionActiveForExternalResponse(_ session: GeckoSession) {
        guard session.isOpen() else {
            return
        }
        sessionsRequestedActive[ObjectIdentifier(session)] = session
        session.setActive(isApplicationForeground)
        session.setFocused(false)
    }
    
    func retainExternalResponse(for session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        externalResponseReferenceCounts[identifier, default: 0] += 1
    }
    
    func releaseExternalResponse(for session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        guard let count = externalResponseReferenceCounts[identifier] else {
            return
        }
        
        if count > 1 {
            externalResponseReferenceCounts[identifier] = count - 1
            return
        }
        
        externalResponseReferenceCounts.removeValue(forKey: identifier)
        guard let cleanup = deferredExternalResponseCleanups.removeValue(forKey: identifier) else {
            return
        }
        
        scheduleSessionCleanup(for: cleanup.session, cleanup.perform)
    }
    
    func clearExternalResponseRetention(for session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        externalResponseReferenceCounts.removeValue(forKey: identifier)
        deferredExternalResponseCleanups.removeValue(forKey: identifier)
    }
    
    // MARK: - Session Cleanup
    
    func close(_ session: GeckoSession) {
        scheduleSessionCleanup(for: session) { manager in
            manager.closeImmediately(session)
        }
    }
    
    func discard(_ session: GeckoSession, forTab tabID: UUID, keepingHistory: Bool = false) {
        scheduleSessionCleanup(for: session) { manager in
            manager.discardImmediately(
                session,
                forTab: tabID,
                keepingHistory: keepingHistory
            )
        }
    }
    
    private func scheduleSessionCleanup(
        for session: GeckoSession,
        _ perform: @escaping (SessionManager) -> Void
    ) {
        let identifier = ObjectIdentifier(session)
        if externalResponseReferenceCounts[identifier] != nil {
            if deferredExternalResponseCleanups[identifier] == nil {
                deferredExternalResponseCleanups[identifier] = (session, perform)
            }
            keepSessionActiveForExternalResponse(session)
            return
        }
        
        perform(self)
    }
    
    private func closeImmediately(_ session: GeckoSession) {
        deactivate(session)
        trackingProtection.removeSession(session)
        permissionStore.removePrivateActions(for: session)
        pageBackgroundColors.removeValue(forKey: ObjectIdentifier(session))
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
    
    // MARK: - Page Background Color
    
    func pageBackgroundColor(for session: GeckoSession) -> UIColor {
        return pageBackgroundColors[ObjectIdentifier(session)] ?? .systemBackground
    }
    
    func setPageBackgroundColor(_ color: UIColor, for session: GeckoSession) {
        pageBackgroundColors[ObjectIdentifier(session)] = color
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
    
    func websiteModeNeedsUpdate(of session: GeckoSession, for url: String, tabID: UUID?) -> Bool {
        return session.settings.websiteMode != sessionSettings.settings(for: url, tabID: tabID).websiteMode
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
    
    func navigationHistory(for tabID: UUID) -> NavigationHistoryStore.Snapshot {
        return history.snapshot(for: tabID)
    }
    
    func usesStoredNavigationHistory(for tabID: UUID) -> Bool {
        return history.usesStoredHistory(for: tabID)
    }
    
    func recordNavigation(
        to url: String,
        title: String,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        return history.record(to: url, title: title, for: tabID, sessionState: sessionState)
    }
    
    func goBack(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goBack(for: tabID, sessionState: sessionState)
    }
    
    func goBack(
        to index: Int,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goBack(to: index, for: tabID, sessionState: sessionState)
    }
    
    func goForward(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goForward(for: tabID, sessionState: sessionState)
    }
    
    func goForward(
        to index: Int,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        return history.goForward(to: index, for: tabID, sessionState: sessionState)
    }
    
    func useStoredNavigationHistory(for tabID: UUID) -> NavigationAvailability {
        return history.useStoredHistory(for: tabID)
    }
    
    func updateCurrentHistoryTitle(_ title: String, for tabID: UUID, matching url: String) {
        history.updateCurrentHistoryTitle(title, for: tabID, matching: url)
    }
    
    func updateCurrentHistoryThumbnail(
        _ image: UIImage?,
        for tabID: UUID,
        matching url: String,
        completion: @escaping () -> Void
    ) {
        history.updateCurrentHistoryThumbnail(image, for: tabID, matching: url, completion: completion)
    }
    
    func navigationPreviewImages(for tabID: UUID) -> NavigationPreviewImages {
        return history.previewImages(for: tabID)
    }
    
    func invalidateNavigationThumbnails() {
        history.invalidateThumbnails()
    }
}
