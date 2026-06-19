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
        UserDefaults.standard.register(defaults: [
            // Search
            key("SearchSettings", "searchEngine"): SearchEngine.google.rawValue,
            key("SearchSettings", "customSearchTemplate"): "",
            
            // JIT
            key("JITSettings", "isJITEnabled"): false,
            
            // Compatibility
            key("CompatibilitySettings", "androidUserAgentDomains"): [],
            key("CompatibilitySettings", "useAndroidUserAgent"): true,
            
            // Browsing
            key("BrowsingSettings", "requestDesktopWebsite"): UIDevice.current.userInterfaceIdiom == .pad,
            
            // Appearance
            key("AppearanceSettings", "addressBarPosition"): BrowserChromePosition.bottom.rawValue,
            key("AppearanceSettings", "showsLandscapeTabBar"): true,
            
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
    
    func set(_ value: Bool, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: String?, forSetting setting: String, key name: String) {
        UserDefaults.standard.set(value, forKey: key(setting, name))
    }
    
    func set(_ value: Data?, forSetting setting: String, key name: String) {
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
    }
    
    // MARK: - Browsing
    struct BrowsingSettings {
        static var requestDesktopWebsite: Bool {
            get {
                prefs.bool(forSetting: "BrowsingSettings", key: "requestDesktopWebsite")
            }
            set {
                prefs.set(newValue, forSetting: "BrowsingSettings", key: "requestDesktopWebsite")
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
