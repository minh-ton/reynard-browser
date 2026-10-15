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
    private var installTask: Task<Void, Never>?
    private var isInstalled = false

    private init() {}

    /// Installs the built-in extension. Safe to call repeatedly.
    func ensureInstalled() {
        _ = startInstall()
    }

    /// Waits (briefly) until the extension is installed, so a page opened right
    /// afterwards gets its content script injected on the very first load.
    func waitUntilInstalled(timeout: TimeInterval = 8) async {
        _ = startInstall()
        let deadline = Date().addingTimeInterval(timeout)
        while !isInstalled && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if !isInstalled {
            FxADebugLog.shared.log("extension still not installed after \(Int(timeout))s, continuing anyway")
        }
    }

    private func startInstall() -> Task<Void, Never>? {
        if isInstalled {
            return nil
        }
        if let installTask {
            return installTask
        }
        FxADebugLog.shared.log("installing extension \(Self.extensionID)")
        let task = Task { @MainActor [weak self] in
            do {
                _ = try await AddonRuntime.shared.ensureBuiltIn(
                    location: Self.extensionLocation,
                    id: Self.extensionID
                )
                self?.isInstalled = true
                FxADebugLog.shared.log("extension installed")
            } catch {
                FxADebugLog.shared.log("extension install FAILED: \(error)")
                NSLog("Reynard Sync: failed to install the account WebChannel extension: %@", "\(error)")
            }
            self?.installTask = nil
        }
        installTask = task
        return task
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
        let sender = port.sender
        FxADebugLog.shared.log("port connect: ext=\(sender.extensionID) env=\(sender.environment) topLevel=\(sender.isTopLevel) url=\(Self.loggableURL(sender.url))")

        guard sender.extensionID == Self.extensionID,
              sender.environment == .contentScript,
              sender.isTopLevel,
              isAllowedOrigin(sender.url, allowMissing: true) else {
            FxADebugLog.shared.log("port REJECTED")
            port.disconnect()
            return
        }

        let sessionID = sender.sessionIdentifier
        if let existing = ports[sessionID], existing !== port {
            existing.disconnect()
        }
        port.delegate = self
        ports[sessionID] = port
        FxADebugLog.shared.log("port accepted")
    }

    // MARK: - AddonPortDelegate

    func addonPort(_ port: AddonPort, didReceive message: Any) {
        guard isAllowedOrigin(port.sender.url, allowMissing: true) else {
            FxADebugLog.shared.log("message dropped: bad origin \(Self.loggableURL(port.sender.url))")
            return
        }
        guard let envelope = Self.dictionary(message),
              let channelID = envelope["id"] as? String,
              channelID == FxAConfig.webChannelID,
              let payload = Self.dictionary(envelope["message"]),
              let command = payload["command"] as? String else {
            FxADebugLog.shared.log("message dropped: unrecognised envelope")
            return
        }

        FxADebugLog.shared.log("page -> app: \(command)")

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
            FxADebugLog.shared.log("oauth_login ignored: missing code or state (keys: \(data.keys.sorted().joined(separator: ",")))")
            return
        }
        FxADebugLog.shared.log("oauth_login received, exchanging code")
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
                FxADebugLog.shared.log("sign-in complete")
                AlertPresenter.show(title: NSLocalizedString("Signed In", comment: ""), message: message)
            } catch {
                FxADebugLog.shared.log("sign-in FAILED: \(error.localizedDescription)")
                NSLog("Reynard Sync: sign-in failed: %@", error.localizedDescription)
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn't Sign In", comment: ""),
                    message: error.localizedDescription
                )
            }
        }
    }
    
    private func reply(on port: AddonPort, command: String, messageID: Any, data: [String: Any]) {
        FxADebugLog.shared.log("app -> page: \(command)")
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

    /// The content script only injects on accounts.firefox.com (see the
    /// extension manifest), so a missing URL is tolerated; a present URL must match.
    private func isAllowedOrigin(_ urlString: String?, allowMissing: Bool = false) -> Bool {
        guard let urlString else {
            return allowMissing
        }
        guard let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return Self.allowedHosts.contains(host)
    }

    /// Host and path only, so query strings (which carry OAuth state) never reach the log.
    private static func loggableURL(_ urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString), let host = url.host else {
            return urlString == nil ? "nil" : "unparseable"
        }
        return "\(url.scheme ?? "")://\(host)\(url.path)"
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
