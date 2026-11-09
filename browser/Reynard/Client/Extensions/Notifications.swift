//
//  Notifications.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

extension Notification.Name {
    static let addressBarPositionDidChange = Notification.Name("Chrome.AddressBarPositionDidChange")
    static let landscapeTabBarDidChange = Notification.Name("Chrome.LandscapeTabBarDidChange")
    static let showFullWebsiteAddressDidChange = Notification.Name("Chrome.ShowFullWebsiteAddressDidChange")
    static let appearanceGestureSettingsDidChange = Notification.Name("Appearance.GestureSettingsDidChange")
    static let newTabDisplayOptionDidChange = Notification.Name("Browsing.NewTabDisplayOptionDidChange")
    static let privateBrowsingSettingsDidChange = Notification.Name("Browsing.PrivateBrowsingSettingsDidChange")
    static let homepageSettingsDidChange = Notification.Name("Homepage.SettingsDidChange")
    static let appUpdateAvailable = Notification.Name("Settings.AppUpdateAvailable")
    static let bookmarkStoreDidChange = Notification.Name("BookmarkStore.DidChange")
    static let downloadStoreDidChange = Notification.Name("DownloadStore.DidChange")
    static let downloadStoreDidStartDownload = Notification.Name("DownloadStore.DidStartDownload")
    static let historyStoreDidChange = Notification.Name("HistoryStore.DidChange")
    static let geckoRuntimeChildProcessDidStart = Notification.Name("GeckoRuntime.ChildProcessDidStart")
    static let selectionSystemUIDidDismiss = Notification.Name("Selection.SystemUIDidDismiss")
    static let jitEndpointMonitorDidFail = Notification.Name("JIT.EndpointMonitorDidFail")
    static let jitlessModeDidActivate = Notification.Name("JITless.ModeDidActivate")
}
