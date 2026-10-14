//
//  FxAConfig.swift
//  Reynard
//
//  Mozilla account (formerly Firefox Account) server configuration.
//

import Foundation

struct FxAConfig {
    /// Public OAuth client used by GeckoView based Firefox builds (Fenix and its forks).
    /// It is registered for the WebChannel redirect and for Sync scoped keys.
    static let clientID = "a2270f727f45f648"

    static let contentURL = URL(string: "https://accounts.firefox.com")!

    static let scopeProfile = "profile"
    static let scopeOldSync = "https://identity.mozilla.com/apps/oldsync"
    static let scopeSession = "https://identity.mozilla.com/tokens/session"
    static let signInScopes = [scopeProfile, scopeOldSync, scopeSession]
    static let refreshScopes = [scopeProfile, scopeOldSync]

    static let entrypoint = "reynard-settings"
    static let webChannelID = "account_updates"

    var authorizationEndpoint: URL
    var tokenEndpoint: URL
    var userInfoEndpoint: URL
    var authServerBaseURL: URL
    var oauthServerBaseURL: URL
    var tokenServerURL: URL

    /// Defaults matching production accounts.firefox.com. Used when discovery fails.
    static let production = FxAConfig(
        authorizationEndpoint: URL(string: "https://accounts.firefox.com/authorization")!,
        tokenEndpoint: URL(string: "https://api.accounts.firefox.com/v1/oauth/token")!,
        userInfoEndpoint: URL(string: "https://profile.accounts.firefox.com/v1/profile")!,
        authServerBaseURL: URL(string: "https://api.accounts.firefox.com")!,
        oauthServerBaseURL: URL(string: "https://oauth.accounts.firefox.com")!,
        tokenServerURL: URL(string: "https://token.services.mozilla.com/1.0/sync/1.5")!
    )

    private static var cached: FxAConfig?

    /// Reads `.well-known/openid-configuration` and `.well-known/fxa-client-configuration`,
    /// falling back to the production defaults for anything missing.
    static func discover() async -> FxAConfig {
        if let cached {
            return cached
        }

        var config = production
        if let openID = try? await FxAHTTP.getJSON(contentURL.appendingPathComponent(".well-known/openid-configuration")) {
            if let value = (openID["authorization_endpoint"] as? String).flatMap(URL.init(string:)) {
                config.authorizationEndpoint = value
            }
            if let value = (openID["userinfo_endpoint"] as? String).flatMap(URL.init(string:)) {
                config.userInfoEndpoint = value
            }
        }
        if let client = try? await FxAHTTP.getJSON(contentURL.appendingPathComponent(".well-known/fxa-client-configuration")) {
            if let value = (client["auth_server_base_url"] as? String).flatMap(URL.init(string:)) {
                config.authServerBaseURL = value
                // Same choice as Mozilla's application-services: the openid
                // `token_endpoint` still points at the legacy OAuth server.
                config.tokenEndpoint = config.authServerURL(path: "oauth/token")
            }
            if let value = (client["oauth_server_base_url"] as? String).flatMap(URL.init(string:)) {
                config.oauthServerBaseURL = value
            }
            if let value = (client["sync_tokenserver_base_url"] as? String).flatMap(URL.init(string:)) {
                config.tokenServerURL = normalizedTokenServerURL(value)
            }
        }

        cached = config
        return config
    }

    private static func normalizedTokenServerURL(_ url: URL) -> URL {
        var string = url.absoluteString
        while string.hasSuffix("/") {
            string.removeLast()
        }
        if string.hasSuffix("1.0/sync/1.5") {
            return URL(string: string) ?? url
        }
        return URL(string: string + "/1.0/sync/1.5") ?? url
    }

    /// `auth_server_base_url` already ends in `/v1` in production; avoid doubling it.
    func authServerURL(path: String) -> URL {
        var base = authServerBaseURL.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.hasSuffix("/v1") {
            base += "/v1"
        }
        return URL(string: base + "/" + path)!
    }

    func oauthServerURL(path: String) -> URL {
        var base = oauthServerBaseURL.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.hasSuffix("/v1") {
            base += "/v1"
        }
        return URL(string: base + "/" + path)!
    }
}
