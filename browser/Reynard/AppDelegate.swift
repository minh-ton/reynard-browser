//
//  AppDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        guard !ReynardStartupMode.current.usesUIKitOnlyStartup else {
            return true
        }
        Task {
            do {
                try await AddonPackageStagingService.shared.removeStaleFiles()
            } catch {
                AddonPackageStagingLog.error("Unable to clean staged add-on packages", error: error)
            }
        }
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    func applicationWillTerminate(_ application: UIApplication) {
        guard !ReynardStartupMode.current.usesUIKitOnlyStartup else {
            return
        }
        NavigationHistoryStore.shared.flushPendingWrites()
    }
}
