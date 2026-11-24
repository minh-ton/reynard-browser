//
//  BrowserWindow.swift
//  Reynard
//
//  Created by Minh Ton on 24/11/26.
//

import UIKit

final class BrowserWindow {
    let window: UIWindow
    private let rootViewController: BrowserViewController
    
    var browser: BrowserViewController {
        return rootViewController.contentBrowserViewController
    }
    
    init(windowScene: UIWindowScene, startup: TabStartup) {
        rootViewController = BrowserViewController(startup: startup)
        rootViewController.sessionManager.setApplicationForeground(windowScene.activationState != .background)
        
        let window = InteractionTrackingWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = AppAppearanceController.userInterfaceStyle(for: Prefs.AppearanceSettings.appAppearance)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        self.window = window
        
        window.onUserInteraction = { [weak self] in
            guard let self else {
                return
            }
            BrowserWindowManager.shared.activate(self)
        }
    }
    
    // MARK: - Scene Lifecycle
    
    func sceneDidBecomeActive() {
        rootViewController.screenOrientationController.start()
        browser.sessionManager.applicationDidBecomeActive()
        browser.tabManager.applicationDidBecomeActive()
    }
    
    func sceneWillResignActive() {
        rootViewController.screenOrientationController.stop()
        browser.sessionManager.applicationWillResignActive()
    }
    
    func setForeground(_ isForeground: Bool) {
        browser.sessionManager.setApplicationForeground(isForeground)
    }
    
    func interfaceOrientationDidChange(to interfaceOrientation: UIInterfaceOrientation) {
        rootViewController.screenOrientationController.screenOrientationChanged(to: interfaceOrientation)
    }
    
    func openExternalURL(_ url: URL) {
        DispatchQueue.main.async { [self] in
            rootViewController.loadViewIfNeeded()
            rootViewController.sidebarCoordinator.loadContentIfNeeded()
            rootViewController.sidebarCoordinator.openExternalURL(url)
        }
    }
}

private final class InteractionTrackingWindow: UIWindow {
    var onUserInteraction: (() -> Void)?
    
    override func sendEvent(_ event: UIEvent) {
        let beginsTouch = event.allTouches?.contains { $0.phase == .began } == true
        if beginsTouch || event.type == .presses {
            onUserInteraction?()
        }
        super.sendEvent(event)
    }
}
