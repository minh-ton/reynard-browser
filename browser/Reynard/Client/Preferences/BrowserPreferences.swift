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
            
            // Experimental
            
            // Compatibility
            key("CompatibilitySettings", "androidUserAgentDomains"): [],
            key("CompatibilitySettings", "useAndroidUserAgent"): true,
            key("CompatibilitySettings", "customUserAgent"): "",
            key("CompatibilitySettings", "customPlatform"): "",
            key("CompatibilitySettings", "customAppVersion"): "",
            key("CompatibilitySettings", "customOscpu"): "",
            key("CompatibilitySettings", "customBuildID"): "",
            
            // Developer
            key("DeveloperSettings", "remoteDebuggingEnabled"): false,
            key("DeveloperSettings", "remoteDebuggingPort"): 6000,
            
            // Browsing
            key("BrowsingSettings", "requestDesktopWebsite"): UIDevice.current.userInterfaceIdiom == .pad,
            key("BrowsingSettings", "showLinkPreviews"): true,
            key("BrowsingSettings", "showImagePreviews"): true,
            key("BrowsingSettings", "openLinksInExternalApps"): true,
            key("BrowsingSettings", "openLinksInNewTabsBehavior"): OpenLinksInNewTabsBehavior.switchTabImmediately.rawValue,
            key("BrowsingSettings", "defaultPageZoomLevel"): PageZoomLevels.defaultLevel,
            key("BrowsingSettings", "useReaderAutomatically"): false,
            key("BrowsingSettings", "readerViewFontSizeStep"): 3,
            key("BrowsingSettings", "readerViewFontType"): ReaderViewFontType.serif.rawValue,
            
            // New Tab
            key("NewTabSettings", "newTabDisplayOption"): NewTabDisplayOption.homepage.rawValue,
            key("NewTabSettings", "customNewTabURL"): "",
            
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
            key("HomepageSettings", "showsRecommendations"): true,
            key("HomepageSettings", "showsNewUpdates"): true,
            key("HomepageSettings", "showsWallpaper"): false,
            key("HomepageSettings", "donationRecommendationMultiplier"): 1,
            
            // Appearance
            key("AppearanceSettings", "appAppearance"): AppAppearance.system.rawValue,
            key("AppearanceSettings", "addressBarPosition"): BrowserChromePosition.bottom.rawValue,
            key("AppearanceSettings", "showsFullWebsiteAddress"): false,
            key("AppearanceSettings", "showsLandscapeTabBar"): true,
            key("AppearanceSettings", "pullToRefreshEnabled"): true,
            key("AppearanceSettings", "scrollToHideToolbarEnabled"): true,
            key("AppearanceSettings", "swipeAddressBarSidewaysEnabled"): true,
            key("AppearanceSettings", "swipeAddressBarUpEnabled"): true,
            
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
            key("SitePermissionSettings", "defaultMidiPermission"): SitePermissionAction.askToAllow.rawValue,
            
            // Clear Browsing Data
            key("ClearBrowsingData", "clearsBrowsingHistory"): true,
            key("ClearBrowsingData", "clearsCookiesAndSiteData"): true,
            key("ClearBrowsingData", "clearsCachedImagesAndFiles"): true,
            key("ClearBrowsingData", "clearsDownloadedFiles"): false,
            key("ClearBrowsingData", "clearsSitePermissions"): true,
            key("ClearBrowsingData", "clearsOpenedTabs"): true,
            
            // HTTPS-Only Mode
            key("HTTPSOnlyMode", "enabled"): false,
            key("HTTPSOnlyMode", "scope"): HTTPSOnlyModeScope.allTabs.rawValue,
            
            // DNS over HTTPS
            key("DNSOverHTTPS", "protectionLevel"): DNSOverHTTPSProtectionLevel.defaultProtection.rawValue,
            key("DNSOverHTTPS", "provider"): SecureDNSProvider.cloudflare.rawValue,
            key("DNSOverHTTPS", "customProviderURL"): "",
            key("DNSOverHTTPS", "exceptions"): (try? JSONEncoder().encode([String]())) ?? Data(),
            
            // Tracking Protection
            key("TrackingProtection", "enhancedTrackingProtectionLevel"): TrackingProtectionLevel.standard.rawValue,
            key("TrackingProtection", "strictBaselineAllowListEnabled"): true,
            key("TrackingProtection", "strictConvenienceAllowListEnabled"): false,
            key("TrackingProtection", "customBaselineAllowListEnabled"): true,
            key("TrackingProtection", "customConvenienceAllowListEnabled"): false,
            key("TrackingProtection", "customCookiePolicy"): CustomCookiePolicy.isolateCrossSite.rawValue,
            key("TrackingProtection", "customTrackingContentScope"): CustomBlockingScope.all.rawValue,
            key("TrackingProtection", "customBlocksCryptominers"): true,
            key("TrackingProtection", "customBlocksKnownFingerprinters"): true,
            key("TrackingProtection", "customBlocksRedirectTrackers"): true,
            key("TrackingProtection", "customSuspectedFingerprinterScope"): CustomBlockingScope.privateOnly.rawValue,
            key("TrackingProtection", "globalPrivacyControlEnabled"): false,
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
        
        static var openLinksInExternalApps: Bool {
            get {
                return prefs.bool(forSetting: "BrowsingSettings", key: "openLinksInExternalApps")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "openLinksInExternalApps")
            }
        }
        
        static var openLinksInNewTabsBehavior: OpenLinksInNewTabsBehavior {
            get {
                let rawValue = prefs.string(forSetting: "BrowsingSettings", key: "openLinksInNewTabsBehavior") ?? OpenLinksInNewTabsBehavior.switchTabImmediately.rawValue
                return OpenLinksInNewTabsBehavior(rawValue: rawValue) ?? .switchTabImmediately
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "BrowsingSettings", key: "openLinksInNewTabsBehavior")
            }
        }
        
        static var defaultPageZoomLevel: Int {
            get {
                let level = prefs.integer(forSetting: "BrowsingSettings", key: "defaultPageZoomLevel")
                return PageZoomLevels.all.contains(level) ? level : PageZoomLevels.defaultLevel
            }
            set {
                guard PageZoomLevels.all.contains(newValue) else {
                    return
                }
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "defaultPageZoomLevel")
            }
        }
        
        static var useReaderAutomatically: Bool {
            get {
                return prefs.bool(forSetting: "BrowsingSettings", key: "useReaderAutomatically")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "useReaderAutomatically")
            }
        }
        
        static var readerViewFontSizeStep: Int {
            get {
                return min(
                    ReaderViewAppearance.maximumFontSizeStep,
                    max(
                        ReaderViewAppearance.minimumFontSizeStep,
                        prefs.integer(forSetting: "BrowsingSettings", key: "readerViewFontSizeStep")
                    )
                )
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "readerViewFontSizeStep")
            }
        }
        
        static var readerViewFontType: ReaderViewFontType {
            get {
                let value = prefs.string(forSetting: "BrowsingSettings", key: "readerViewFontType")
                return ReaderViewFontType(rawValue: value ?? "") ?? .serif
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "BrowsingSettings", key: "readerViewFontType")
            }
        }
        
        static var readerViewColorScheme: ReaderViewColorScheme {
            get {
                if let value = prefs.string(forSetting: "BrowsingSettings", key: "readerViewColorScheme"),
                   let colorScheme = ReaderViewColorScheme(rawValue: value) {
                    return colorScheme
                }
                switch AppearanceSettings.appAppearance {
                case .dark:
                    return .dark
                case .light:
                    return .light
                case .system:
                    let style = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap(\.windows)
                        .first?.traitCollection.userInterfaceStyle
                    return style == .dark ? .dark : .light
                }
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "BrowsingSettings", key: "readerViewColorScheme")
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
    
    // MARK: - HTTPS-Only Mode
    struct HTTPSOnlyModePreferences {
        static var enabled: Bool {
            get {
                return prefs.bool(forSetting: "HTTPSOnlyMode", key: "enabled")
            }
            set {
                prefs.set(newValue, forSetting: "HTTPSOnlyMode", key: "enabled")
            }
        }
        
        static var scope: HTTPSOnlyModeScope {
            get {
                let rawValue = prefs.string(forSetting: "HTTPSOnlyMode", key: "scope") ?? HTTPSOnlyModeScope.allTabs.rawValue
                return HTTPSOnlyModeScope(rawValue: rawValue) ?? .allTabs
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "HTTPSOnlyMode", key: "scope")
            }
        }
    }
    
    // MARK: - DNS over HTTPS
    struct DNSOverHTTPSPreferences {
        static var protectionLevel: DNSOverHTTPSProtectionLevel {
            get {
                let rawValue = prefs.integer(forSetting: "DNSOverHTTPS", key: "protectionLevel")
                return DNSOverHTTPSProtectionLevel(rawValue: rawValue) ?? .defaultProtection
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "DNSOverHTTPS", key: "protectionLevel")
            }
        }
        
        static var provider: SecureDNSProvider {
            get {
                let rawValue = prefs.string(forSetting: "DNSOverHTTPS", key: "provider") ?? SecureDNSProvider.cloudflare.rawValue
                return SecureDNSProvider(rawValue: rawValue) ?? .cloudflare
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "DNSOverHTTPS", key: "provider")
            }
        }
        
        static var customProviderURL: String {
            get {
                return prefs.string(forSetting: "DNSOverHTTPS", key: "customProviderURL") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "DNSOverHTTPS", key: "customProviderURL")
            }
        }
        
        static var exceptions: [String] {
            get {
                guard let data = prefs.data(forSetting: "DNSOverHTTPS", key: "exceptions"),
                      let exceptions = try? JSONDecoder().decode([String].self, from: data) else {
                    return []
                }
                return exceptions
            }
            set {
                let data = try? JSONEncoder().encode(newValue)
                prefs.set(data, forSetting: "DNSOverHTTPS", key: "exceptions")
            }
        }
    }
    
    // MARK: - Tracking Protection
    struct TrackingProtectionPreferences {
        static var level: TrackingProtectionLevel {
            get {
                let rawValue = prefs.string(forSetting: "TrackingProtection", key: "enhancedTrackingProtectionLevel") ?? TrackingProtectionLevel.standard.rawValue
                return TrackingProtectionLevel(rawValue: rawValue) ?? .standard
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "TrackingProtection", key: "enhancedTrackingProtectionLevel")
            }
        }
        
        static var strictBaselineAllowListEnabled: Bool {
            get {
                return prefs.bool(forSetting: "TrackingProtection", key: "strictBaselineAllowListEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "TrackingProtection", key: "strictBaselineAllowListEnabled")
            }
        }
        
        static var strictConvenienceAllowListEnabled: Bool {
            get {
                return prefs.bool(forSetting: "TrackingProtection", key: "strictConvenienceAllowListEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "TrackingProtection", key: "strictConvenienceAllowListEnabled")
            }
        }
        
        static var customBaselineAllowListEnabled: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "customBaselineAllowListEnabled") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "customBaselineAllowListEnabled") }
        }
        
        static var customConvenienceAllowListEnabled: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "customConvenienceAllowListEnabled") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "customConvenienceAllowListEnabled") }
        }
        
        static var customCookiePolicy: CustomCookiePolicy {
            get {
                return CustomCookiePolicy(rawValue: prefs.integer(forSetting: "TrackingProtection", key: "customCookiePolicy")) ?? .isolateCrossSite
            }
            set { prefs.set(newValue.rawValue, forSetting: "TrackingProtection", key: "customCookiePolicy") }
        }
        
        static var customTrackingContentScope: CustomBlockingScope {
            get {
                let rawValue = prefs.string(forSetting: "TrackingProtection", key: "customTrackingContentScope") ?? CustomBlockingScope.all.rawValue
                return CustomBlockingScope(rawValue: rawValue) ?? .all
            }
            set { prefs.set(newValue.rawValue, forSetting: "TrackingProtection", key: "customTrackingContentScope") }
        }
        
        static var customBlocksCryptominers: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "customBlocksCryptominers") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "customBlocksCryptominers") }
        }
        
        static var customBlocksKnownFingerprinters: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "customBlocksKnownFingerprinters") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "customBlocksKnownFingerprinters") }
        }
        
        static var customBlocksRedirectTrackers: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "customBlocksRedirectTrackers") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "customBlocksRedirectTrackers") }
        }
        
        static var customSuspectedFingerprinterScope: CustomBlockingScope {
            get {
                let rawValue = prefs.string(forSetting: "TrackingProtection", key: "customSuspectedFingerprinterScope") ?? CustomBlockingScope.privateOnly.rawValue
                return CustomBlockingScope(rawValue: rawValue) ?? .privateOnly
            }
            set { prefs.set(newValue.rawValue, forSetting: "TrackingProtection", key: "customSuspectedFingerprinterScope") }
        }
        
        static var globalPrivacyControlEnabled: Bool {
            get { return prefs.bool(forSetting: "TrackingProtection", key: "globalPrivacyControlEnabled") }
            set { prefs.set(newValue, forSetting: "TrackingProtection", key: "globalPrivacyControlEnabled") }
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
        
        static var showsRecommendations: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsRecommendations")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsRecommendations")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsNewUpdates: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsNewUpdates")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsNewUpdates")
                NotificationCenter.default.post(name: .homepageSettingsDidChange, object: nil)
            }
        }
        
        static var showsWallpaper: Bool {
            get {
                return prefs.bool(forSetting: "HomepageSettings", key: "showsWallpaper")
            }
            set {
                prefs.set(newValue, forSetting: "HomepageSettings", key: "showsWallpaper")
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
        
        static var defaultMidiPermission: SitePermissionAction {
            get {
                let rawValue = prefs.string(forSetting: "SitePermissionSettings", key: "defaultMidiPermission")
                guard let rawValue,
                      let action = SitePermissionAction(rawValue: rawValue) else {
                    return .askToAllow
                }
                return action
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "SitePermissionSettings", key: "defaultMidiPermission")
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
        
        static var customUserAgent: String {
            get {
                return prefs.string(forSetting: "CompatibilitySettings", key: "customUserAgent") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "CompatibilitySettings", key: "customUserAgent")
            }
        }
        
        static var customPlatform: String {
            get {
                return prefs.string(forSetting: "CompatibilitySettings", key: "customPlatform") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "CompatibilitySettings", key: "customPlatform")
            }
        }
        
        static var customAppVersion: String {
            get {
                return prefs.string(forSetting: "CompatibilitySettings", key: "customAppVersion") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "CompatibilitySettings", key: "customAppVersion")
            }
        }
        
        static var customOscpu: String {
            get {
                return prefs.string(forSetting: "CompatibilitySettings", key: "customOscpu") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "CompatibilitySettings", key: "customOscpu")
            }
        }
        
        static var customBuildID: String {
            get {
                return prefs.string(forSetting: "CompatibilitySettings", key: "customBuildID") ?? ""
            }
            set {
                prefs.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forSetting: "CompatibilitySettings", key: "customBuildID")
            }
        }
    }
    
    // MARK: - Developer
    struct DeveloperSettings {
        static var remoteDebuggingEnabled: Bool {
            get {
                return prefs.bool(forSetting: "DeveloperSettings", key: "remoteDebuggingEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "DeveloperSettings", key: "remoteDebuggingEnabled")
            }
        }
        
        static var remoteDebuggingPort: Int {
            get {
                return prefs.integer(forSetting: "DeveloperSettings", key: "remoteDebuggingPort")
            }
            set {
                prefs.set(newValue, forSetting: "DeveloperSettings", key: "remoteDebuggingPort")
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
        
        static var pullToRefreshEnabled: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "pullToRefreshEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "pullToRefreshEnabled")
                NotificationCenter.default.post(name: .appearanceGestureSettingsDidChange, object: nil)
            }
        }
        
        static var scrollToHideToolbarEnabled: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "scrollToHideToolbarEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "scrollToHideToolbarEnabled")
                NotificationCenter.default.post(name: .appearanceGestureSettingsDidChange, object: nil)
            }
        }
        
        static var swipeAddressBarSidewaysEnabled: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "swipeAddressBarSidewaysEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "swipeAddressBarSidewaysEnabled")
                NotificationCenter.default.post(name: .appearanceGestureSettingsDidChange, object: nil)
            }
        }
        
        static var swipeAddressBarUpEnabled: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "swipeAddressBarUpEnabled")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "swipeAddressBarUpEnabled")
                NotificationCenter.default.post(name: .appearanceGestureSettingsDidChange, object: nil)
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
