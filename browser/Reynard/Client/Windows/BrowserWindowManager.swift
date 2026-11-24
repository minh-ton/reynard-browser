//
//  BrowserWindowManager.swift
//  Reynard
//
//  Created by Minh Ton on 24/11/26.
//

import UIKit

final class BrowserWindowManager {
    static let shared = BrowserWindowManager()
    
    private let tabStore = TabManagementStore.shared
    private var windows: [BrowserWindow] = []
    
    var browsers: [BrowserViewController] {
        return windows.map(\.browser)
    }
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: .sceneSessionsDidDiscard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeDiscardedWindows()
        }
    }
    
    // MARK: - Window Lifecycle
    
    func connect(_ windowScene: UIWindowScene, draggedTabID: UUID?) -> BrowserWindow {
        if windows.isEmpty {
            removeDiscardedWindows()
        }
        
        let sceneID = windowScene.session.persistentIdentifier
        let startup: TabStartup
        if let draggedTabID,
           let transfer = detachTab(withID: draggedTabID, from: browsers) {
            startup = TabStartup(windowID: tabStore.createWindow(sceneID: sceneID), transfer: transfer)
        } else {
            startup = TabStartup(windowID: tabStore.windowID(forSceneID: sceneID), transfer: nil)
        }
        
        let window = BrowserWindow(windowScene: windowScene, startup: startup)
        windows.append(window)
        return window
    }
    
    func activate(_ window: BrowserWindow) {
        guard let index = windows.firstIndex(where: { $0 === window }) else {
            return
        }
        windows.insert(windows.remove(at: index), at: 0)
    }
    
    func disconnect(_ window: BrowserWindow) {
        windows.removeAll { $0 === window }
        window.browser.tabManager.discardAllTabs()
    }
    
    private func removeDiscardedWindows() {
        let application = UIApplication.shared
        tabStore.removeWindows(
            notMatchingSceneIDs: Set(application.openSessions.map(\.persistentIdentifier)),
            supportsMultipleScenes: application.supportsMultipleScenes
        )
    }
    
    // MARK: - Tabs
    
    func removeAllTabs() {
        for browser in browsers {
            browser.tabManager.removeAllTabs(mode: .regular)
            browser.tabManager.removeAllTabs(mode: .private)
            browser.tabManager.createTab(selecting: true, mode: .regular)
        }
        
        let application = UIApplication.shared
        tabStore.removeWindows(
            notMatchingSceneIDs: Set(application.connectedScenes.map(\.session.persistentIdentifier)),
            supportsMultipleScenes: application.supportsMultipleScenes
        )
    }
    
    func moveTab(withID tabID: UUID, to browser: BrowserViewController, at index: Int) {
        guard let transfer = detachTab(withID: tabID, from: browsers.filter { $0 !== browser }) else {
            return
        }
        
        browser.tabManager.adopt(transfer, at: index)
    }
    
    private func detachTab(withID tabID: UUID, from browsers: [BrowserViewController]) -> TabTransfer? {
        for browser in browsers {
            if let transfer = browser.tabManager.detachTab(withID: tabID) {
                return transfer
            }
        }
        return nil
    }
}
