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
            key("AppearanceSettings", "addressBarPosition"): AddressBarPosition.bottom.rawValue,
            key("AppearanceSettings", "showsLandscapeTabBar"): true,
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
        static var addressBarPosition: AddressBarPosition {
            get {
                let rawValue = prefs.string(forSetting: "AppearanceSettings", key: "addressBarPosition") ?? AddressBarPosition.bottom.rawValue
                return AddressBarPosition(rawValue: rawValue) ?? .bottom
            }
            set {
                prefs.set(newValue.rawValue, forSetting: "AppearanceSettings", key: "addressBarPosition")
                NotificationCenter.default.post(name: Notification.Name("addressBarPositionChanged"), object: nil)
            }
        }
        
        static var showsLandscapeTabBar: Bool {
            get {
                prefs.bool(forSetting: "AppearanceSettings", key: "showsLandscapeTabBar")
            }
            set {
                prefs.set(newValue, forSetting: "AppearanceSettings", key: "showsLandscapeTabBar")
                NotificationCenter.default.post(name: Notification.Name("landscapeTabBarChanged"), object: nil)
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
}

private var prefs: BrowserPreferences { BrowserPreferences.shared }
