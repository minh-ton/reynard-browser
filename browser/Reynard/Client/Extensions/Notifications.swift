//
//  Notifications.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

extension Notification.Name {
    static let addressBarPositionDidChange = Notification.Name("addressBarPositionChanged")
    static let landscapeTabBarDidChange = Notification.Name("landscapeTabBarChanged")
    static let appUpdateAvailable = Notification.Name("me.minh-ton.reynard.update-available")
    static let bookmarkStoreDidChange = Notification.Name("me.minh-ton.reynard.bookmark-store-did-change")
    static let downloadStoreDidChange = Notification.Name("me.minh-ton.reynard.download-store-did-change")
    static let downloadStoreDidStartDownload = Notification.Name("me.minh-ton.reynard.download-store-did-start-download")
    static let historyStoreDidChange = Notification.Name("me.minh-ton.reynard.history-store-did-change")
    static let geckoRuntimeChildProcessDidStart = Notification.Name("GeckoRuntimeChildProcessDidStart")
    static let jitEndpointMonitorDidFail = Notification.Name("me-minh-ton.jit.endpoint-monitor-failed")
    static let jitlessModeDidActivate = Notification.Name("me.minh-ton.reynard.jitless-mode-activated")
}
