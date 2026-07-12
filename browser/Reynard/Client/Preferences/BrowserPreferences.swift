//
//  BrowserPreferences.swift
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

import Foundation
import UIKit

typealias Prefs = BrowserPreferences

final class BrowserPreferences {
    static var shared = BrowserPreferences()
    
    let profile: String
    
    init(profile: String = "default") {
        self.profile = profile
        registerDefaults()
    }
    
    // Possible future work
    static func useProfile(_ name: String) {
        shared = BrowserPreferences(profile: name)
    }
    
    func key(_ setting: String, _ name: String) -> String {
        "\(profile).\(setting).\(name)"
    }
    
    func registerDefaults() {
        let donationRecommendationShowTimeKey = key("HomepageSettings", "donationRecommendationShowTime")
        if UserDefaults.standard.object(forKey: donationRecommendationShowTimeKey) == nil {
            let delay = TimeInterval.random(in: (3 * 86_400)...(5 * 86_400))
            UserDefaults.standard.set(Date().addingTimeInterval(delay).timeIntervalSince1970, forKey: donationRecommendationShowTimeKey)
        }
        
        UserDefaults.standard.register(defaults: [
            // Search
            key("SearchSettings", "searchEngine"): SearchEngine.google.rawValue,
            key("SearchSettings", "customSearchTemplate"): "",
            key("SearchSettings", "searchSuggestionProvider"): SearchCompletion.Provider.google.rawValue,
            key("SearchSettings", "showSearchSuggestions"): true,
            key("SearchSettings", "showSearchSuggestionsInPrivateBrowsing"): true,
            key("SearchSettings", "searchBrowsingHistory"): true,
            key("SearchSettings", "searchBookmarks"): true,
            key("SearchSettings", "searchOpenedTabs"): true,
            
            // JIT
            key("JITSettings", "isJITEnabled"): false,
            
            // Compatibility
            key("CompatibilitySettings", "androidUserAgentDomains"): [],
            key("CompatibilitySettings", "useAndroidUserAgent"): true,
            
            // Browsing
            key("BrowsingSettings", "requestDesktopWebsite"): UIDevice.current.userInterfaceIdiom == .pad,
            key("BrowsingSettings", "showLinkPreviews"): true,
            key("BrowsingSettings", "showImagePreviews"): true,
            
            // New Tab
            key("NewTabSettings", "newTabDisplayOption"): NewTabDisplayOption.homepage.rawValue,
            key("NewTabSettings", "customNewTabURL"): "",
            key("NewTabSettings", "automaticallyOpensKeyboard"): false,
            
            // Homepage
            key("HomepageSettings", "openingScreen"): HomepageOpeningScreen.homepage.rawValue,
            key("HomepageSettings", "showsFavorites"): true,
            key("HomepageSettings", "showsFavoritesInPrivateBrowsing"): false,
            key("HomepageSettings", "favoriteRowCount"): 2,
            key("HomepageSettings", "showsFrequentlyVisited"): true,
            key("HomepageSettings", "showsFrequentlyVisitedInPrivateBrowsing"): false,
            key("HomepageSettings", "frequentlyVisitedSiteCount"): 8,
            key("HomepageSettings", "showsRecentlyClosedTabs"): true,
            key("HomepageSettings", "recentlyClosedTabLimit"): 10,
            key("HomepageSettings", "donationRecommendationMultiplier"): 1,
            
            // Appearance
            key("AppearanceSettings", "appAppearance"): AppAppearance.system.rawValue,
            key("AppearanceSettings", "addressBarPosition"): BrowserChromePosition.bottom.rawValue,
            key("AppearanceSettings", "showsFullWebsiteAddress"): false,
            key("AppearanceSettings", "showsLandscapeTabBar"): true,
            key("AppearanceSettings", "defaultPageZoomLevel"): PageZoomLevels.defaultLevel,
            
            // Languages
            key("LanguageSettings", "websiteLanguages"): (try? JSONEncoder().encode(WebsiteLanguageCatalog.defaultLanguageCodes())) ?? Data(),
            
            // Bookmarks
            key("BookmarkSettings", "placeFoldersOnTop"): true,
            key("BookmarkSettings", "sortOrders"): BookmarkSortOrder.none.rawValue,
            
            // Add-ons
            key("AddonSettings", "lastGlobalCheckAt"): "",
            key("AddonSettings", "pendingApprovalAddonIDs"): Data(),
            
            // Site Permissions
            key("SitePermissionSettings", "defaultAutoplayPermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultCameraPermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultMicrophonePermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultLocationPermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultPersistentStoragePermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultCrossOriginStorageAccessPermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultLocalDeviceAccessPermission"): SitePermissionAction.askToAllow.rawValue,
            key("SitePermissionSettings", "defaultLocalNetworkAccessPermission"): SitePermissionAction.askToAllow.rawValue,
            
            // Clear Browsing Data
            key("ClearBrowsingData", "clearsBrowsingHistory"): true,
            key("ClearBrowsingData", "clearsCookiesAndSiteData"): true,
            key("ClearBrowsingData", "clearsCachedImagesAndFiles"): true,
            key("ClearBrowsingData", "clearsDownloadedFiles"): false,
            key("ClearBrowsingData", "clearsSitePermissions"): true,
            key("ClearBrowsingData", "clearsOpenedTabs"): true,
        ])
    }
    
    func bool(forSetting setting: String, key name: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(setting, name))
    }
    
    func string(forSetting setting: String, key name: String) -> String? {
        UserDefaults.standard.string(forKey: key(setting, name))
    }
    
    func data(forSetting setting: String, key name: String) -> Data? {
        UserDefaults.standard.data(forKey: key(setting, name))
    }
    
    func double(forSetting setting: String, key name: String) -> Double {
        UserDefaults.standard.double(forKey: key(setting, name))
    }
    
    func integer(forSetting setting: String, key name: String) -> Int {
        UserDefaults.standard.integer(forKey: key(setting, name))
    }
    
    func set(_ value: Bool, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: String?, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: Data?, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: Double, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: Int, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    // MARK: - Search
    struct SearchSettings {
        static var searchEngine: SearchEngine {
            get {
                let rawValue = prefs.string(forSetting: "SearchSettings", key: "searchEngine") ?? SearchEngine.google.rawValue
                return SearchEngine(rawValue: rawValue) ?? .google
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SearchSettings", key: "searchEngine")
            }
        }
        
        static var customSearchTemplate: String {
            get {
                return prefs.string(forSetting: "SearchSettings", key: "customSearchTemplate") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "SearchSettings", key: "customSearchTemplate")
            }
        }
        
        static var searchSuggestionProvider: SearchCompletion.Provider {
            get {
                let rawValue = prefs.string(forSetting: "SearchSettings", key: "searchSuggestionProvider") ?? SearchCompletion.Provider.google.rawValue
                return SearchCompletion.Provider(rawValue: rawValue) ?? .google
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SearchSettings", key: "searchSuggestionProvider")
            }
        }
        
        static var showSearchSuggestions: Bool {
            get {
                return prefs.bool(forSetting: "SearchSettings", key: "showSearchSuggestions")
            }
            set {
                prefs.set(newValue, forSetting: "SearchSettings", key: "showSearchSuggestions")
            }
        }
        
        static var showSearchSuggestionsInPrivateBrowsing: Bool {
            get {
                return prefs.bool(forSetting: "SearchSettings", key: "showSearchSuggestionsInPrivateBrowsing")
            }
            set {
                prefs.set(newValue, forSetting: "SearchSettings", key: "showSearchSuggestionsInPrivateBrowsing")
            }
        }
        
        static var searchBrowsingHistory: Bool {
            get {
                return prefs.bool(forSetting: "SearchSettings", key: "searchBrowsingHistory")
            }
            set {
                prefs.set(newValue, forSetting: "SearchSettings", key: "searchBrowsingHistory")
            }
        }
        
        static var searchBookmarks: Bool {
            get {
                return prefs.bool(forSetting: "SearchSettings", key: "searchBookmarks")
            }
            set {
                prefs.set(newValue, forSetting: "SearchSettings", key: "searchBookmarks")
            }
        }
        
        static var searchOpenedTabs: Bool {
            get {
                return prefs.bool(forSetting: "SearchSettings", key: "searchOpenedTabs")
            }
            set {
                prefs.set(newValue, forSetting: "SearchSettings", key: "searchOpenedTabs")
            }
        }
    }
    
    // MARK: - Browsing
    struct BrowsingSettings {
        static var requestDesktopWebsite: Bool {
            get {
                return prefs.bool(forSetting: "BrowsingSettings", key: "requestDesktopWebsite")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "requestDesktopWebsite")
            }
        }
        
        static var showLinkPreviews: Bool {
            get {
                return prefs.bool(forSetting: "BrowsingSettings", key: "showLinkPreviews")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "showLinkPreviews")
            }
        }
        
        static var showImagePreviews: Bool {
            get {
                return prefs.bool(forSetting: "BrowsingSettings", key: "showImagePreviews")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "showImagePreviews")
            }
        }
    }
    
    // MARK: - Clear Browsing Data
    struct ClearBrowsingData {
        static var clearsBrowsingHistory: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsBrowsingHistory")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsBrowsingHistory")
            }
        }
        
        static var clearsCookiesAndSiteData: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsCookiesAndSiteData")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsCookiesAndSiteData")
            }
        }
        
        static var clearsCachedImagesAndFiles: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsCachedImagesAndFiles")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsCachedImagesAndFiles")
            }
        }
        
        static var clearsDownloadedFiles: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsDownloadedFiles")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsDownloadedFiles")
            }
        }
        
        static var clearsSitePermissions: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsSitePermissions")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsSitePermissions")
            }
        }
        
        static var clearsOpenedTabs: Bool {
            get {
                return prefs.bool(forSetting: "ClearBrowsingData", key: "clearsOpenedTabs")
            }
            set {
                prefs.set(newValue, forSetting: "ClearBrowsingData", key: "clearsOpenedTabs")
            }
        }
    }
    
    // MARK: - New Tab
    struct NewTabSettings {
        static var newTabDisplayOption: NewTabDisplayOption {
            get {
                let rawValue = prefs.string(forSetting: "NewTabSettings", key: "newTabDisplayOption") ?? NewTabDisplayOption.homepage.rawValue
                return NewTabDisplayOption(rawValue: rawValue) ?? .homepage
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "NewTabSettings", key: "newTabDisplayOption")
                NotificationCenter.default.post(name: .newTabDisplayOptionDidChange, object: nil)
            }
        }
        
        static var customNewTabURL: String {
            get {
                return prefs.string(forSetting: "NewTabSettings", key: "customNewTabURL") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "NewTabSettings", key: "customNewTabURL")
            }
        }

        static var automaticallyOpensKeyboard: Bool {
            get {
                return prefs.bool(forSetting: "NewTabSettings", key: "automaticallyOpensKeyboard")
            }
            set {
                prefs.set(newValue, forSetting: "NewTabSettings", key: "automaticallyOpensKeyboard")
            }
        }
    }
    
    // MARK: - Homepage
    struct HomepageSettings {
        static var openingScreen: HomepageOpeningScreen {
            get {
                let rawValue = prefs.string(forSetting: "HomepageSettings", key: "openingScreen") ?? HomepageOpeningScreen.homepage.rawValue
                return HomepageOpeningScreen(rawValue: rawValue) ?? .homepage
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "HomepageSettings", key: "openingScreen")
            }
        }
        
        static var showsFavorites: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsFavorites")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsFavorites")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var favoriteRowCount: Int {
            get {
                return prefs.integer(forSetting: "HomepageSettings", key: "favoriteRowCount")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "favoriteRowCount")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsFavoritesInPrivateBrowsing: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsFavoritesInPrivateBrowsing")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsFavoritesInPrivateBrowsing")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsFrequentlyVisited: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsFrequentlyVisited")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsFrequentlyVisited")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsFrequentlyVisitedInPrivateBrowsing: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsFrequentlyVisitedInPrivateBrowsing")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsFrequentlyVisitedInPrivateBrowsing")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var frequentlyVisitedSiteCount: Int {
            get {
                return prefs.integer(forSetting: "HomepageSettings", key: "frequentlyVisitedSiteCount")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "frequentlyVisitedSiteCount")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsRecentlyClosedTabs: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsRecentlyClosedTabs")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsRecentlyClosedTabs")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var recentlyClosedTabLimit: Int {
            get {
                return prefs.integer(forSetting: "HomepageSettings", key: "recentlyClosedTabLimit")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "recentlyClosedTabLimit")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var donationRecommendationShowTime: Date {
            get {
                return Date(timeIntervalSince1970: prefs.double(forSetting: "HomepageSettings", key: "donationRecommendationShowTime"))
            }
            set {
                prefs.set(newValue.timeIntervalSince1970, forSetting: "HomepageSettings", key: "donationRecommendationShowTime")
            }
        }
        
        static var donationRecommendationMultiplier: Int {
            get {
                return prefs.integer(forSetting: "HomepageSettings", key: "donationRecommendationMultiplier")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "donationRecommendationMultiplier")
            }
        }
    }
    
    // MARK: - Site Permissions
    struct SitePermissionSettings {
        static var defaultAutoplayPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultAutoplayPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultAutoplayPermission")
            }
        }
        
        static var defaultCameraPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultCameraPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultCameraPermission")
            }
        }
        
        static var defaultMicrophonePermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultMicrophonePermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultMicrophonePermission")
            }
        }
        
        static var defaultLocationPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultLocationPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultLocationPermission")
            }
        }
        
        static var defaultPersistentStoragePermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultPersistentStoragePermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultPersistentStoragePermission")
            }
        }
        
        static var defaultCrossOriginStorageAccessPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultCrossOriginStorageAccessPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultCrossOriginStorageAccessPermission")
            }
        }
        
        static var defaultLocalDeviceAccessPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultLocalDeviceAccessPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultLocalDeviceAccessPermission")
            }
        }
        
        static var defaultLocalNetworkAccessPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultLocalNetworkAccessPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultLocalNetworkAccessPermission")
            }
        }
    }
    
    // MARK: - Compatibility
    struct CompatibilitySettings {
        static var androidUserAgentDomains: [String] {
            get {
                guard let data = prefs.data(forSetting: "CompatibilitySettings", key: "androidUserAgentDomains"),
                      let list = try? JSONDecoder().decode([String].self, from: data) else {
                    return []
                }
                return list
            }
            set {
                let data = try? JSONEncoder().encode(newValue)
                prefs.set(data, forSetting: "CompatibilitySettings", key: "androidUserAgentDomains")
            }
        }
        
        static var useAndroidUserAgent: Bool {
            get {
                prefs.bool(forSetting: "CompatibilitySettings", key: "useAndroidUserAgent")
            }
            set {
                prefs.set(newValue, forSetting: "CompatibilitySettings", key: "useAndroidUserAgent")
            }
        }
    }
    
    // MARK: - Appearance
    struct AppearanceSettings {
        static var appAppearance: AppAppearance {
            get {
                let rawValue = prefs.string(forSetting: "AppearanceSettings", key: "appAppearance") ?? AppAppearance.system.rawValue
                return AppAppearance(rawValue: rawValue) ?? .system
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "AppearanceSettings", key: "appAppearance")
            }
        }
        
        static var addressBarPosition: BrowserChromePosition {
            get {
                let rawValue = prefs.string(forSetting: "AppearanceSettings", key: "addressBarPosition") ?? BrowserChromePosition.bottom.rawValue
                return BrowserChromePosition(rawValue: rawValue) ?? .bottom
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "AppearanceSettings", key: "addressBarPosition")
                NotificationCenter.default.post(name: .addressBarPositionDidChange, object: nil)
            }
        }
        
        static var showsLandscapeTabBar: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "showsLandscapeTabBar")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "showsLandscapeTabBar")
                NotificationCenter.default.post(name: .landscapeTabBarDidChange, object: nil)
            }
        }
        
        static var showsFullWebsiteAddress: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "showsFullWebsiteAddress")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "showsFullWebsiteAddress")
                NotificationCenter.default.post(name: .showFullWebsiteAddressDidChange, object: nil)
            }
        }
        
        static var defaultPageZoomLevel: Int {
            get {
                let level = prefs.integer(forSetting: "AppearanceSettings", key: "defaultPageZoomLevel")
                return PageZoomLevels.all.contains(level) ? level : PageZoomLevels.defaultLevel
            }
            set {
                guard PageZoomLevels.all.contains(newValue) else {
                    return
                }
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "defaultPageZoomLevel")
            }
        }
    }
    
    // MARK: - JIT
    struct JITSettings {
        static var hasPairingFile: Bool {
            FileManager.default.fileExists(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("pairingFile.plist", isDirectory: false).path)
        }
        
        static var isJITEnabled: Bool {
            get {
                guard hasPairingFile else {
                    return false
                }
                return prefs.bool(forSetting: "JITSettings", key: "isJITEnabled")
            }
            set {
                prefs.set(hasPairingFile && newValue, forSetting: "JITSettings", key: "isJITEnabled")
            }
        }
    }
    
    // MARK: - Bookmarks
    struct BookmarkSettings {
        static var placeFoldersOnTop: Bool {
            get {
                prefs.bool(forSetting: "BookmarkSettings", key: "placeFoldersOnTop")
            }
            set {
                prefs.set(newValue, forSetting: "BookmarkSettings", key: "placeFoldersOnTop")
            }
        }
        
        static var sortOrders: BookmarkSortOrder {
            get {
                let rawValue = prefs.string(forSetting: "BookmarkSettings", key: "sortOrders") ?? BookmarkSortOrder.none.rawValue
                return BookmarkSortOrder(rawValue: rawValue) ?? .none
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "BookmarkSettings", key: "sortOrders")
            }
        }
    }
    
    // MARK: - Languages
    struct LanguageSettings {
        static var websiteLanguages: [String] {
            get {
                guard let data = prefs.data(forSetting: "LanguageSettings", key: "websiteLanguages"),
                      let values = try? JSONDecoder().decode([String].self, from: data) else {
                    return WebsiteLanguageCatalog.defaultLanguageCodes()
                }
                return WebsiteLanguageCatalog.sanitizedLanguageCodes(values)
            }
            set {
                let values = WebsiteLanguageCatalog.sanitizedLanguageCodes(newValue)
                let data = try? JSONEncoder().encode(values)
                prefs.set(data, forSetting: "LanguageSettings", key: "websiteLanguages")
            }
        }
    }
    
    // MARK: - Add-ons
    struct AddonSettings {
        static var lastGlobalCheckAt: Date? {
            get {
                guard let value = prefs.string(forSetting: "AddonSettings", key: "lastGlobalCheckAt"),
                      !value.isEmpty else {
                    return nil
                }
                return ISO8601DateFormatter().date(from: value)
            }
            set {
                prefs.set(newValue.map { ISO8601DateFormatter().string(from: $0) }, forSetting: "AddonSettings", key: "lastGlobalCheckAt")
            }
        }
        
        static var pendingApprovalAddonIDs: [String] {
            get {
                guard let data = prefs.data(forSetting: "AddonSettings", key: "pendingApprovalAddonIDs"),
                      !data.isEmpty,
                      let values = try? JSONDecoder().decode([String].self, from: data) else {
                    return []
                }
                return values
            }
            set {
                let data = try? JSONEncoder().encode(newValue)
                prefs.set(data, forSetting: "AddonSettings", key: "pendingApprovalAddonIDs")
            }
        }
    }
}

private var prefs: BrowserPreferences { BrowserPreferences.shared }
