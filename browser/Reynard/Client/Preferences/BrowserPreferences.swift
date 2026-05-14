//
//  BrowserPreferences.swift
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

import Foundation
import UIKit

final class BrowserPreferences {
    enum SearchEngine: String, CaseIterable {
        case google
        case yahoo
        case bing
        case brave
        case duckDuckGo
        case ecosia
        case startpage
        case custom
        
        var displayName: String {
            switch self {
            case .google:
                return "Google"
            case .yahoo:
                return "Yahoo"
            case .bing:
                return "Bing"
            case .brave:
                return "Brave"
            case .duckDuckGo:
                return "DuckDuckGo"
            case .ecosia:
                return "Ecosia"
            case .startpage:
                return "Startpage"
            case .custom:
                return "Custom"
            }
        }
        
        var searchTemplate: String? {
            switch self {
            case .google:
                return "https://www.google.com/search?q=%s"
            case .yahoo:
                return "https://search.yahoo.com/search?p=%s"
            case .bing:
                return "https://www.bing.com/search?q=%s"
            case .brave:
                return "https://search.brave.com/search?q=%s"
            case .duckDuckGo:
                return "https://duckduckgo.com/?q=%s"
            case .ecosia:
                return "https://www.ecosia.org/search?q=%s"
            case .startpage:
                return "https://www.startpage.com/sp/search?query=%s"
            case .custom:
                return nil
            }
        }
    }
    
    enum AddressBarPosition: String {
        case bottom
        case top
    }
    
    private enum Keys {
        static let searchEngine = "BrowserPreferences.searchEngine"
        static let customSearchTemplate = "BrowserPreferences.customSearchTemplate"
        static let jitEnabled = "BrowserPreferences.jitEnabled"
        static let androidUserAgentDomains = "BrowserPreferences.androidUserAgentDomains"
        static let useAndroidUserAgent = "BrowserPreferences.useAndroidUserAgent"
        static let requestDesktopWebsite = "BrowserPreferences.requestDesktopWebsite"
        static let addressBarPosition = "BrowserPreferences.addressBarPosition"
        static let showsLandscapeTabBar = "BrowserPreferences.showsLandscapeTabBar"
    }
    
    static let shared = BrowserPreferences()
    
    private let defaults: UserDefaults
    private let fileManager: FileManager
    
    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        registerDefaults()
    }
    
    var searchEngine: SearchEngine {
        get {
            let rawValue = defaults.string(forKey: Keys.searchEngine) ?? SearchEngine.google.rawValue
            return SearchEngine(rawValue: rawValue) ?? .google
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.searchEngine)
        }
    }
    
    var customSearchTemplate: String {
        get { defaults.string(forKey: Keys.customSearchTemplate) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.customSearchTemplate) }
    }
    
    var isCustomSearchTemplateValid: Bool {
        isValidCustomSearchTemplate(customSearchTemplate)
    }
    
    var hasPairingFile: Bool {
        fileManager.fileExists(atPath: pairingFileURL.path)
    }
    
    var isJITEnabled: Bool {
        get {
            guard hasPairingFile else {
                return false
            }
            return defaults.bool(forKey: Keys.jitEnabled)
        }
        set {
            defaults.set(hasPairingFile && newValue, forKey: Keys.jitEnabled)
        }
    }
    
    var androidUserAgentDomains: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.androidUserAgentDomains),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return list
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.androidUserAgentDomains)
        }
    }
    
    var useAndroidUserAgent: Bool {
        get { defaults.bool(forKey: Keys.useAndroidUserAgent) }
        set { defaults.set(newValue, forKey: Keys.useAndroidUserAgent) }
    }
    
    var requestDesktopWebsite: Bool {
        get { defaults.bool(forKey: Keys.requestDesktopWebsite) }
        set { defaults.set(newValue, forKey: Keys.requestDesktopWebsite) }
    }
    
    var addressBarPosition: AddressBarPosition {
        get {
            let rawValue = defaults.string(forKey: Keys.addressBarPosition) ?? AddressBarPosition.bottom.rawValue
            return AddressBarPosition(rawValue: rawValue) ?? .bottom
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.addressBarPosition)
            NotificationCenter.default.post(name: Notification.Name("addressBarPositionChanged"), object: nil)
        }
    }
    
    var showsLandscapeTabBar: Bool {
        get { defaults.object(forKey: Keys.showsLandscapeTabBar) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.showsLandscapeTabBar)
            NotificationCenter.default.post(name: Notification.Name("landscapeTabBarChanged"), object: nil)
        }
    }
    
    var pairingFileURL: URL {
        documentsDirectory.appendingPathComponent("pairingFile.plist", isDirectory: false)
    }
    
    var searchEngineSummary: String {
        searchEngine.displayName
    }
    
    func installPairingFile(from sourceURL: URL) throws {
        let destinationURL = pairingFileURL
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        let normalizedSourceURL = sourceURL.standardizedFileURL
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        
        guard normalizedSourceURL != normalizedDestinationURL else {
            isJITEnabled = false
            return
        }
        
        if fileManager.fileExists(atPath: normalizedDestinationURL.path) {
            try fileManager.removeItem(at: normalizedDestinationURL)
        }
        
        try fileManager.copyItem(at: normalizedSourceURL, to: normalizedDestinationURL)
        isJITEnabled = false
    }
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.searchEngine: SearchEngine.google.rawValue,
            Keys.customSearchTemplate: "",
            Keys.jitEnabled: false,
            Keys.androidUserAgentDomains: [],
            Keys.useAndroidUserAgent: true,
            Keys.requestDesktopWebsite: UIDevice.current.userInterfaceIdiom == .pad,
            Keys.addressBarPosition: AddressBarPosition.bottom.rawValue,
            Keys.showsLandscapeTabBar: true,
        ])
    }
}
