//
//  SystemProxyPreferences.swift
//  Reynard
//
//  Applies the proxy configuration of the system to Gecko.
//

import CFNetwork
import Foundation
import GeckoView
import UIKit

/// Gecko uses its own network stack and therefore only follows the
/// `network.proxy.*` preferences. The proxy that is configured in
/// Settings > Wi-Fi is not visible to it, which means that requests are always
/// sent directly to the network.
///
/// This reads the system configuration and applies it to Gecko, so that
/// manually configured HTTP, HTTPS and SOCKS proxies as well as proxy
/// auto-configuration (PAC) files are honoured.
enum SystemProxyPreferences {
    private struct ProxyEndpoint {
        let host: String
        let port: Int
    }
    
    /// CFNetwork only declares constants for some of the keys that it returns
    /// on iOS. The remaining ones are marked as unavailable there
    /// (`CF_AVAILABLE(10_6, NA)`), so their names are spelled out instead.
    private enum Key {
        static let httpsEnable = "HTTPSEnable"
        static let httpsProxy = "HTTPSProxy"
        static let httpsPort = "HTTPSPort"
        static let socksEnable = "SOCKSEnable"
        static let socksProxy = "SOCKSProxy"
        static let socksPort = "SOCKSPort"
        static let exceptionsList = "ExceptionsList"
    }
    
    private static var appliedPreferences: [String: Any]?
    private static var activationObserver: NSObjectProtocol?
    
    static func apply() {
        let preferences = proxyPreferences()
        
        if let appliedPreferences,
           (preferences as NSDictionary).isEqual(to: appliedPreferences) {
            return
        }
        
        appliedPreferences = preferences
        GeckoRuntime.setDefaultPrefs(preferences)
    }
    
    /// The system proxy can only be changed from the Settings app, which puts
    /// Reynard in the background, so the preferences are refreshed whenever the
    /// app becomes active again.
    static func observeChanges() {
        guard activationObserver == nil else {
            return
        }
        
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            apply()
        }
    }
    
    private static func proxyPreferences() -> [String: Any] {
        let settings = systemProxySettings()
        var preferences: [String: Any] = [:]
        
        let httpProxy = endpoint(
            in: settings,
            enableKey: kCFNetworkProxiesHTTPEnable as String,
            proxyKey: kCFNetworkProxiesHTTPProxy as String,
            portKey: kCFNetworkProxiesHTTPPort as String
        )
        let httpsProxy = endpoint(
            in: settings,
            enableKey: Key.httpsEnable,
            proxyKey: Key.httpsProxy,
            portKey: Key.httpsPort
        )
        let socksProxy = endpoint(
            in: settings,
            enableKey: Key.socksEnable,
            proxyKey: Key.socksProxy,
            portKey: Key.socksPort
        )
        
        // A proxy auto-configuration file takes precedence over the proxies
        // that are configured manually.
        let autoConfigURL = settings[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String ?? ""
        if isEnabled(settings[kCFNetworkProxiesProxyAutoConfigEnable as String]),
           !autoConfigURL.isEmpty {
            preferences["network.proxy.type"] = 2
            preferences["network.proxy.autoconfig_url"] = autoConfigURL
        } else if httpProxy != nil || httpsProxy != nil || socksProxy != nil {
            preferences["network.proxy.type"] = 1
            
            if let httpProxy = httpProxy {
                preferences["network.proxy.http"] = httpProxy.host
                preferences["network.proxy.http_port"] = httpProxy.port
            }
            
            // iOS uses the HTTP proxy for HTTPS as well when no separate secure
            // proxy is configured.
            if let secureProxy = httpsProxy ?? httpProxy {
                preferences["network.proxy.ssl"] = secureProxy.host
                preferences["network.proxy.ssl_port"] = secureProxy.port
            }
            
            if let socksProxy = socksProxy {
                preferences["network.proxy.socks"] = socksProxy.host
                preferences["network.proxy.socks_port"] = socksProxy.port
            }
        } else {
            preferences["network.proxy.type"] = 0
        }
        
        let exceptions = settings[Key.exceptionsList] as? [String] ?? []
        preferences["network.proxy.no_proxies_on"] = exceptions.joined(separator: ", ")
        
        return preferences
    }
    
    private static func systemProxySettings() -> [String: Any] {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            return [:]
        }
        
        return settings as NSDictionary as? [String: Any] ?? [:]
    }
    
    private static func endpoint(
        in settings: [String: Any],
        enableKey: String,
        proxyKey: String,
        portKey: String
    ) -> ProxyEndpoint? {
        guard isEnabled(settings[enableKey]),
              let host = settings[proxyKey] as? String,
              !host.isEmpty,
              let port = settings[portKey] as? Int,
              port > 0,
              port <= 65535 else {
            return nil
        }
        
        return ProxyEndpoint(host: host, port: port)
    }
    
    private static func isEnabled(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }
        
        return number.boolValue
    }
}
