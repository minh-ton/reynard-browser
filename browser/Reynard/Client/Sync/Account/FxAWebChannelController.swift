//
//  FxAWebChannelController.swift
//  Reynard
//
//  Handles the WebChannel messages accounts.firefox.com sends to the browser.
//  The page cannot finish sign-in without replies to `fxaccounts:fxa_status`
//  and `fxaccounts:can_link_account`, and it hands the OAuth code back
//  through `fxaccounts:oauth_login`.
//
//  [accounts.firefox.com] <-DOM events-> [fxawebchannel.js] <-native port-> [this class]
//

import Foundation
import GeckoView

final class FxAWebChannelController: AddonMessageDelegate, AddonPortDelegate {
    static let shared = FxAWebChannelController()

    private static let extensionID = "fxawebchannel@reynard"
    private static let extensionLocation = "resource://app/extensions/fxawebchannel/"
    private static let nativeApp = "reynardFxaWebChannel"
    private static let allowedHosts: Set<String> = ["accounts.firefox.com"]

    private enum Command {
        static let status = "fxaccounts:fxa_status"
        static let canLinkAccount = "fxaccounts:can_link_account"
        static let oauthLogin = "fxaccounts:oauth_login"
        static let login = "fxaccounts:login"
        static let logout = "fxaccounts:logout"
        static let deleteAccount = "fxaccounts:delete"
        static let changePassword = "fxaccounts:change_password"
        static let syncPreferences = "fxaccounts:sync_preferences"
    }

    private var ports: [ObjectIdentifier: AddonPort] = [:]
    private var isInstalling = false
    private var isInstalled = false

    private init() {}

    /// Installs the built-in extension. Safe to call repeatedly.
    func ensureInstalled() {
        guard !isInstalled, !isInstalling else {
            return
        }
        isInstalling = true
        Task { @MainActor [weak self] in
            do {
                _ = try await AddonRuntime.shared.ensureBuiltIn(
                    location: Self.extensionLocation,
                    id: Self.extensionID
                )
                self?.isInstalled = true
            } catch {
                NSLog("Reynard Sync: failed to install the account WebChannel extension: %@", "\(error)")
            }
            self?.isInstalling = false
        }
    }

    func registerMessageHandlers(for session: GeckoSession) {
        ensureInstalled()
        session.setAddonMessageDelegate(
            self,
            extensionID: Self.extensionID,
            nativeApp: Self.nativeApp
        )
    }

    // MARK: - AddonMessageDelegate

    func addonPortDidConnect(_ port: AddonPort) {
        guard port.sender.extensionID == Self.extensionID,
              port.sender.environment == .contentScript,
              port.sender.isTopLevel,
              isAllowedOrigin(port.sender.url) else {
            port.disconnect()
            return
        }

        let sessionID = port.sender.sessionIdentifier
        if let existing = ports[sessionID], existing !== port {
            existing.disconnect()
        }
        port.delegate = self
        ports[sessionID] = port
    }

    // MARK: - AddonPortDelegate

    func addonPort(_ port: AddonPort, didReceive message: Any) {
        guard isAllowedOrigin(port.sender.url),
              let envelope = Self.dictionary(message),
              let channelID = envelope["id"] as? String,
              channelID == FxAConfig.webChannelID,
              let payload = Self.dictionary(envelope["message"]),
              let command = payload["command"] as? String else {
            return
        }

        // Echo the ID back exactly as received (FxA matches replies on it).
        let messageID: Any = payload["messageId"] ?? ""
        let data = Self.dictionary(payload["data"]) ?? [:]

        switch command {
        case Command.status:
            reply(on: port, command: command, messageID: messageID, data: FxAAccountManager.shared.webChannelStatus())

        case Command.canLinkAccount:
            let ok = FxAAccountManager.shared.canLink(
                email: data["email"] as? String,
                uid: data["uid"] as? String
            )
            reply(on: port, command: command, messageID: messageID, data: ["ok": ok])

        case Command.oauthLogin:
            handleOAuthLogin(data)

        case Command.logout, Command.deleteAccount:
            Task { @MainActor in
                await FxAAccountManager.shared.signOut()
            }

        case Command.login, Command.changePassword, Command.syncPreferences:
            // Nothing to do: Reynard only uses the OAuth flow, and Sync
            // preferences live in Reynard's settings.
            break

        default:
            NSLog("Reynard Sync: ignoring WebChannel command %@", command)
        }
    }

    func addonPortDidDisconnect(_ port: AddonPort) {
        let sessionID = port.sender.sessionIdentifier
        if ports[sessionID] === port {
            ports.removeValue(forKey: sessionID)
        }
    }

    // MARK: - Commands

    private func handleOAuthLogin(_ data: [String: Any]) {
        guard let code = data["code"] as? String,
              let state = data["state"] as? String else {
            return
        }
        let declined = (data["declinedSyncEngines"] as? [Any])?.compactMap { $0 as? String } ?? []
        
        Task { @MainActor in
            do {
                try await FxAAccountManager.shared.completeSignIn(
                    code: code,
                    state: state,
                    declinedEngines: declined
                )
                let email = FxAAccountManager.shared.account?.email
                let message = email.map {
                    String(format: NSLocalizedString("Signed in as %@. Reynard is now syncing with your other Firefox browsers.", comment: ""), $0)
                } ?? NSLocalizedString("Reynard is now syncing with your other Firefox browsers.", comment: "")
                AlertPresenter.show(title: NSLocalizedString("Signed In", comment: ""), message: message)
            } catch {
                NSLog("Reynard Sync: sign-in failed: %@", error.localizedDescription)
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn't Sign In", comment: ""),
                    message: error.localizedDescription
                )
            }
        }
    }
    
    private func reply(on port: AddonPort, command: String, messageID: Any, data: [String: Any]) {
        port.postMessage([
            "id": FxAConfig.webChannelID,
            "message": [
                "command": command,
                "messageId": messageID,
                "data": data,
            ] as [String: Any],
        ])
    }

    // MARK: - Helpers

    private func isAllowedOrigin(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return Self.allowedHosts.contains(host)
    }

    /// Messages arrive as `[String: Any?]`, `[String: Any]` or `NSDictionary`
    /// depending on how they were bridged; normalize to `[String: Any]`.
    static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let value else {
            return nil
        }
        if let dictionary = value as? [String: Any?] {
            var result: [String: Any] = [:]
            for (key, element) in dictionary {
                if let element {
                    result[key] = element
                }
            }
            return result
        }
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, element) in dictionary {
                if let key = key as? String {
                    result[key] = element
                }
            }
            return result
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return nil
    }
}
