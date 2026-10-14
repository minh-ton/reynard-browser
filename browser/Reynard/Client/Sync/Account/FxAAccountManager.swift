//
//  FxAAccountManager.swift
//  Reynard
//
//  Mozilla account sign-in (OAuth + PKCE + scoped keys over WebChannel),
//  token refresh, device registration and sign-out.
//

import Foundation
import UIKit

extension Notification.Name {
    static let fxaAccountStateDidChange = Notification.Name("FxA.AccountStateDidChange")
    static let syncStatusDidChange = Notification.Name("Sync.StatusDidChange")
    static let syncedTabsDidChange = Notification.Name("Sync.SyncedTabsDidChange")
}

enum FxAAccountError: Error, LocalizedError {
    case noPendingSignIn
    case stateMismatch
    case missingSyncKey
    case missingTokens
    case notSignedIn
    case reauthenticationRequired

    var errorDescription: String? {
        switch self {
        case .noPendingSignIn:
            return NSLocalizedString("The sign-in page finished, but Reynard wasn't expecting it. Start sign-in again from Settings.", comment: "")
        case .stateMismatch:
            return NSLocalizedString("The sign-in response didn't match this request. Start sign-in again from Settings.", comment: "")
        case .missingSyncKey:
            return NSLocalizedString("Your account didn't provide a Sync key. Make sure you signed in with your password, then try again.", comment: "")
        case .missingTokens:
            return NSLocalizedString("The account server returned an incomplete response.", comment: "")
        case .notSignedIn:
            return NSLocalizedString("You're not signed in.", comment: "")
        case .reauthenticationRequired:
            return NSLocalizedString("Your session expired. Sign in again to keep syncing.", comment: "")
        }
    }
}

final class FxAAccountManager {
    static let shared = FxAAccountManager()

    private struct PendingSignIn {
        let state: String
        let pkce: PKCEPair
        let keysFlow: ScopedKeysFlow
        let startedAt: Date
    }

    private(set) var account: FxAAccountState?
    private(set) var needsReauthentication = false
    private(set) var lastSignInError: String?
    private var pendingSignIn: PendingSignIn?
    private var accessTokenTask: Task<String, Error>?

    var isSignedIn: Bool {
        account != nil
    }

    var isSigningIn: Bool {
        guard let pendingSignIn else {
            return false
        }
        return Date().timeIntervalSince(pendingSignIn.startedAt) < 60 * 60
    }

    private init() {
        account = FxAAccountStorage.load()
    }

    // MARK: - Sign in

    /// Builds the accounts.firefox.com URL that starts the sign-in flow.
    /// Load it in a regular tab; the WebChannel extension reports the result.
    func beginSignIn() async throws -> URL {
        let config = await FxAConfig.discover()
        let pkce = try PKCEPair.generate()
        let keysFlow = ScopedKeysFlow()
        let state = try FxACrypto.randomBase64URL(byteCount: 16)

        guard var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw FxAHTTPError.invalidResponse("Invalid authorization endpoint")
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "action", value: "email"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "entrypoint", value: FxAConfig.entrypoint),
            URLQueryItem(name: "service", value: "sync"),
            URLQueryItem(name: "client_id", value: FxAConfig.clientID),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "keys_jwk", value: try keysFlow.keysJWKParameter()),
            URLQueryItem(name: "scope", value: FxAConfig.signInScopes.joined(separator: " ")),
            URLQueryItem(name: "context", value: "oauth_webchannel_v1"),
        ])
        if let email = account?.email, needsReauthentication {
            items.append(URLQueryItem(name: "email", value: email))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw FxAHTTPError.invalidResponse("Could not build the sign-in URL")
        }

        pendingSignIn = PendingSignIn(state: state, pkce: pkce, keysFlow: keysFlow, startedAt: Date())
        lastSignInError = nil
        postAccountStateDidChange()
        return url
    }

    /// Called when accounts.firefox.com sends `fxaccounts:oauth_login`.
    func completeSignIn(code: String, state: String, declinedEngines: [String]) async throws {
        guard let pending = pendingSignIn else {
            throw FxAAccountError.noPendingSignIn
        }
        guard pending.state == state else {
            throw FxAAccountError.stateMismatch
        }
        pendingSignIn = nil

        do {
            let config = await FxAConfig.discover()
            let response = try await FxAHTTP.postJSON(config.tokenEndpoint, body: [
                "grant_type": "authorization_code",
                "client_id": FxAConfig.clientID,
                "code": code,
                "code_verifier": pending.pkce.verifier,
            ])

            guard let refreshToken = response["refresh_token"] as? String,
                  let accessToken = response["access_token"] as? String else {
                throw FxAAccountError.missingTokens
            }
            guard let keysJWE = response["keys_jwe"] as? String else {
                throw FxAAccountError.missingSyncKey
            }

            let syncKey = try Self.extractSyncKey(from: pending.keysFlow.decrypt(jwe: keysJWE))
            let expiresIn = (response["expires_in"] as? NSNumber)?.doubleValue ?? 3_600

            var newAccount = FxAAccountState(
                uid: nil,
                email: nil,
                displayName: nil,
                refreshToken: refreshToken,
                sessionToken: response["session_token"] as? String,
                syncKey: syncKey,
                accessToken: accessToken,
                accessTokenExpiry: Date().addingTimeInterval(expiresIn),
                deviceID: account?.deviceID,
                clientRecordID: account?.clientRecordID ?? FxACrypto.makeSyncGUID(),
                signedInAt: Date()
            )

            if let profile = try? await fetchProfile(accessToken: accessToken, config: config) {
                newAccount.uid = profile["uid"] as? String
                newAccount.email = profile["email"] as? String
                newAccount.displayName = profile["displayName"] as? String
            }

            for engine in SyncPreferences.Engine.allCases where declinedEngines.contains(engine.rawValue) {
                SyncPreferences.setEnabled(false, for: engine)
            }

            if let previousUID = account?.uid, previousUID != newAccount.uid {
                // A different account: its device record and Sync state don't carry over.
                newAccount.deviceID = nil
                SyncPreferences.resetBookkeeping()
                SyncMetadataStore.shared.reset()
            }

            account = newAccount
            needsReauthentication = false
            lastSignInError = nil
            FxAAccountStorage.save(newAccount)
            postAccountStateDidChange()

            await registerDevice()
            SyncManager.shared.requestSync(reason: .signIn)
        } catch {
            lastSignInError = error.localizedDescription
            postAccountStateDidChange()
            throw error
        }
    }

    func cancelPendingSignIn() {
        pendingSignIn = nil
        postAccountStateDidChange()
    }

    // MARK: - Sign out

    func signOut() async {
        guard let current = account else {
            return
        }

        let config = await FxAConfig.discover()
        if let deviceID = current.deviceID {
            _ = try? await FxAHTTP.postJSON(
                config.authServerURL(path: "account/device/destroy"),
                body: ["id": deviceID],
                headers: ["Authorization": "Bearer \(current.refreshToken)"]
            )
        }
        _ = try? await FxAHTTP.postJSON(
            config.oauthServerURL(path: "destroy"),
            body: ["refresh_token": current.refreshToken]
        )

        account = nil
        needsReauthentication = false
        pendingSignIn = nil
        accessTokenTask?.cancel()
        accessTokenTask = nil
        FxAAccountStorage.clear()
        SyncPreferences.resetBookkeeping()
        SyncManager.shared.handleSignOut()
        postAccountStateDidChange()
    }

    // MARK: - Tokens

    /// A short lived OAuth access token with the profile + oldsync scopes.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = account else {
            throw FxAAccountError.notSignedIn
        }

        if !forceRefresh,
           let token = current.accessToken,
           let expiry = current.accessTokenExpiry,
           expiry.timeIntervalSinceNow > 120 {
            return token
        }

        if let accessTokenTask {
            return try await accessTokenTask.value
        }

        let refreshToken = current.refreshToken
        let task = Task { () async throws -> String in
            let config = await FxAConfig.discover()
            let response = try await FxAHTTP.send(FxAHTTP.makeRequest(
                url: config.tokenEndpoint,
                method: "POST",
                json: [
                    "grant_type": "refresh_token",
                    "client_id": FxAConfig.clientID,
                    "refresh_token": refreshToken,
                    "scope": FxAConfig.refreshScopes.joined(separator: " "),
                ]
            ))

            if response.status == 400 || response.status == 401 {
                // errno 110 = invalid token. The refresh token was revoked
                // (password change, sign-out from another device, ...).
                self.markNeedsReauthentication()
                throw FxAAccountError.reauthenticationRequired
            }
            guard response.isSuccess,
                  let json = response.jsonObject(),
                  let accessToken = json["access_token"] as? String else {
                throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
            }

            let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
            if var updated = self.account {
                updated.accessToken = accessToken
                updated.accessTokenExpiry = Date().addingTimeInterval(expiresIn)
                self.account = updated
                FxAAccountStorage.save(updated)
            }
            return accessToken
        }
        accessTokenTask = task
        defer { accessTokenTask = nil }
        return try await task.value
    }

    func markNeedsReauthentication() {
        guard !needsReauthentication else {
            return
        }
        needsReauthentication = true
        if var updated = account {
            updated.accessToken = nil
            updated.accessTokenExpiry = nil
            account = updated
            FxAAccountStorage.save(updated)
        }
        postAccountStateDidChange()
    }

    func syncKeyBundle() throws -> SyncKeyBundle {
        guard let account else {
            throw FxAAccountError.notSignedIn
        }
        guard let kSync = Base64URL.decode(account.syncKey.k) else {
            throw FxAAccountError.missingSyncKey
        }
        return try SyncKeyBundle(kSync: kSync)
    }

    func updateDeviceName(_ name: String) async {
        SyncPreferences.deviceName = name
        await registerDevice()
        SyncManager.shared.requestSync(reason: .user)
    }

    // MARK: - WebChannel support

    /// `data` for the `fxaccounts:fxa_status` reply.
    func webChannelStatus() -> [String: Any] {
        var signedInUser: Any = NSNull()
        if let account, !needsReauthentication, let sessionToken = account.sessionToken, let email = account.email {
            signedInUser = [
                "email": email,
                "uid": account.uid ?? "",
                "sessionToken": sessionToken,
                "verified": true,
            ] as [String: Any]
        }
        return [
            "capabilities": [
                "engines": [String](),
                "can_link_account_uid": true,
            ] as [String: Any],
            "signedInUser": signedInUser,
        ]
    }

    /// `fxaccounts:can_link_account`: only allow linking the same account we already have.
    func canLink(email: String?, uid: String?) -> Bool {
        guard let account else {
            return true
        }
        if let uid, !uid.isEmpty, let currentUID = account.uid {
            return uid == currentUID
        }
        if let email, let currentEmail = account.email {
            return email.caseInsensitiveCompare(currentEmail) == .orderedSame
        }
        return true
    }

    // MARK: - Helpers

    private func fetchProfile(accessToken: String, config: FxAConfig) async throws -> [String: Any] {
        try await FxAHTTP.getJSON(config.userInfoEndpoint, headers: ["Authorization": "Bearer \(accessToken)"])
    }

    /// Registers (or renames) this device so it shows up in the account's device list.
    private func registerDevice() async {
        guard var current = account else {
            return
        }
        let config = await FxAConfig.discover()
        var body: [String: Any] = [
            "name": SyncPreferences.deviceName,
            "type": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile",
        ]
        if let deviceID = current.deviceID {
            body["id"] = deviceID
        }

        do {
            let response = try await FxAHTTP.postJSON(
                config.authServerURL(path: "account/device"),
                body: body,
                headers: ["Authorization": "Bearer \(current.refreshToken)"]
            )
            if let deviceID = response["id"] as? String, current.deviceID != deviceID {
                current.deviceID = deviceID
                account = current
                FxAAccountStorage.save(current)
            }
        } catch {
            NSLog("Reynard Sync: device registration failed: %@", error.localizedDescription)
        }
    }

    private static func extractSyncKey(from keysData: Data) throws -> FxAScopedKey {
        guard let keys = try JSONSerialization.jsonObject(with: keysData) as? [String: Any],
              let syncKey = keys[FxAConfig.scopeOldSync] as? [String: Any],
              let kid = syncKey["kid"] as? String,
              let k = syncKey["k"] as? String,
              let decoded = Base64URL.decode(k),
              decoded.count == 64 else {
            throw FxAAccountError.missingSyncKey
        }
        return FxAScopedKey(kid: kid, k: k, scope: syncKey["scope"] as? String ?? FxAConfig.scopeOldSync)
    }

    private func postAccountStateDidChange() {
        NotificationCenter.default.post(name: .fxaAccountStateDidChange, object: self)
    }
}
