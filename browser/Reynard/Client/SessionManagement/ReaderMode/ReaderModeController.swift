//
//  ReaderModeController.swift
//  Reynard
//

import Foundation
import GeckoView

enum ReaderViewFontType: String, CaseIterable, Equatable {
    case sansSerif = "sans-serif"
    case serif
}

enum ReaderViewColorScheme: String, CaseIterable, Equatable {
    case light
    case sepia
    case dark
}

struct ReaderViewAppearance {
    static let minimumFontSizeStep = 1
    static let maximumFontSizeStep = 9
    
    let fontSizeStep: Int
    let fontType: ReaderViewFontType
    let colorScheme: ReaderViewColorScheme
}

struct ReaderModeState {
    enum AutomaticEntry {
        case allowed
        case pending
        case blocked(ObjectIdentifier)
    }
    
    var isReaderable = false
    var isActive = false
    var originalURL: String?
    var sourceScrollY: Int?
    var automaticEntry = AutomaticEntry.allowed
}

protocol ReaderModeControllerDelegate: AnyObject {
    func readerModeController(
        _ controller: ReaderModeController,
        tabFor session: GeckoSession
    ) -> Tab?
    func readerModeController(
        _ controller: ReaderModeController,
        didChangeStateFor tab: Tab
    )
}

final class ReaderModeController: AddonMessageDelegate, AddonPortDelegate {
    struct PortHandoff {
        let contentPort: AddonPort?
        let activePort: AddonPort?
    }
    
    private static let extensionID = "readerview@mozac.org"
    private static let extensionLocation = "resource://app/extensions/readerview/"
    private static let contentPortName = "mozacReaderview"
    private static let activePortName = "mozacReaderviewActive"
    
    private weak var delegate: ReaderModeControllerDelegate?
    private var extensionBaseURL: String?
    private var contentPorts: [ObjectIdentifier: AddonPort] = [:]
    private var activePorts: [ObjectIdentifier: AddonPort] = [:]
    
    private var appearance: ReaderViewAppearance {
        ReaderViewAppearance(
            fontSizeStep: Prefs.BrowsingSettings.readerViewFontSizeStep,
            fontType: Prefs.BrowsingSettings.readerViewFontType,
            colorScheme: Prefs.BrowsingSettings.readerViewColorScheme
        )
    }
    
    init(delegate: ReaderModeControllerDelegate) {
        self.delegate = delegate
        Task { @MainActor [weak self] in
            await self?.ensureExtensionInstalled()
        }
    }
    
    func registerMessageHandlers(for session: GeckoSession) {
        for nativeApp in [Self.contentPortName, Self.activePortName] {
            session.setAddonMessageDelegate(
                self,
                extensionID: Self.extensionID,
                nativeApp: nativeApp
            )
        }
    }
    
    func detach(_ session: GeckoSession) -> PortHandoff {
        let sessionID = ObjectIdentifier(session)
        return PortHandoff(
            contentPort: contentPorts.removeValue(forKey: sessionID),
            activePort: activePorts.removeValue(forKey: sessionID)
        )
    }
    
    func attach(_ session: GeckoSession, ports: PortHandoff) {
        registerMessageHandlers(for: session)
        
        let sessionID = ObjectIdentifier(session)
        ports.contentPort?.delegate = self
        ports.activePort?.delegate = self
        contentPorts[sessionID] = ports.contentPort
        activePorts[sessionID] = ports.activePort
    }
    
    @discardableResult
    func enter(in tab: Tab) -> Bool {
        let state = tab.state.readerMode
        let sessionID = ObjectIdentifier(tab.session)
        guard state.isReaderable,
              !state.isActive,
              let originalURL = tab.url,
              let port = contentPorts[sessionID],
              let baseURL = extensionBaseURL else {
            return false
        }
        
        let documentID = UUID().uuidString
        port.postMessage([
            "action": "cachePage",
            "id": documentID,
        ])
        
        guard var components = URLComponents(string: baseURL + "readerview.html") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: originalURL),
            URLQueryItem(name: "id", value: documentID),
            URLQueryItem(name: "colorScheme", value: appearance.colorScheme.rawValue),
        ]
        guard let readerURL = components.url?.absoluteString else {
            return false
        }
        
        tab.state.readerMode.automaticEntry = .allowed
        tab.state.readerMode.isActive = true
        tab.state.readerMode.originalURL = originalURL
        delegate?.readerModeController(self, didChangeStateFor: tab)
        tab.session.load(readerURL)
        return true
    }
    
    @discardableResult
    func exit(in tab: Tab) -> Bool {
        guard tab.state.readerMode.isActive else {
            return false
        }
        
        tab.state.readerMode.isActive = false
        tab.state.readerMode.isReaderable = false
        tab.state.readerMode.automaticEntry = .pending
        
        delegate?.readerModeController(self, didChangeStateFor: tab)
        
        if tab.state.navigationState.canGoBack {
            tab.session.goBack(userInteraction: false)
        } else if let port = activePorts[ObjectIdentifier(tab.session)] {
            port.postMessage(["action": "hide"])
        }
        return true
    }
    
    private func enterAutomaticallyIfNeeded(in tab: Tab, from port: AddonPort) {
        let portID = ObjectIdentifier(port)
        switch tab.state.readerMode.automaticEntry {
        case .allowed:
            break
        case .pending:
            tab.state.readerMode.automaticEntry = .blocked(portID)
            return
        case let .blocked(blockedPortID):
            guard blockedPortID != portID else {
                return
            }
            tab.state.readerMode.automaticEntry = .allowed
        }
        
        guard tab.state.readerMode.isReaderable,
              let urlString = tab.url,
              let host = URL(string: urlString)?.host else {
            return
        }
        let usesReaderAutomatically = SiteSettingsStore.shared.settings(for: host)?.readerMode
        ?? Prefs.BrowsingSettings.useReaderAutomatically
        guard usesReaderAutomatically else {
            return
        }
        _ = enter(in: tab)
    }
    
    func setFontSizeStep(_ step: Int, for session: GeckoSession?) {
        let clampedStep = min(
            ReaderViewAppearance.maximumFontSizeStep,
            max(ReaderViewAppearance.minimumFontSizeStep, step)
        )
        let difference = clampedStep - Prefs.BrowsingSettings.readerViewFontSizeStep
        guard difference != 0 else { return }
        Prefs.BrowsingSettings.readerViewFontSizeStep = clampedStep
        sendToActivePort(
            ["action": "changeFontSize", "value": difference],
            for: session
        )
    }
    
    func setFontType(_ fontType: ReaderViewFontType, for session: GeckoSession?) {
        guard fontType != Prefs.BrowsingSettings.readerViewFontType else { return }
        Prefs.BrowsingSettings.readerViewFontType = fontType
        sendToActivePort(
            ["action": "setFontType", "value": fontType.rawValue],
            for: session
        )
    }
    
    func setColorScheme(_ colorScheme: ReaderViewColorScheme, for session: GeckoSession?) {
        guard colorScheme != Prefs.BrowsingSettings.readerViewColorScheme else { return }
        Prefs.BrowsingSettings.readerViewColorScheme = colorScheme
        sendToActivePort(
            ["action": "setColorScheme", "value": colorScheme.rawValue],
            for: session
        )
    }
    
    func displayedURL(for engineURL: String, in tab: Tab) -> String {
        let state = tab.state.readerMode
        let isKnownReaderURL = extensionBaseURL.map {
            engineURL.hasPrefix($0)
        } ?? false
        let components = URLComponents(string: engineURL)
        let isReaderDocument = components?.url?.scheme == "moz-extension" &&
        components?.url?.lastPathComponent == "readerview.html"
        
        if isKnownReaderURL || isReaderDocument,
           let originalURL = components?.queryItems?.first(where: { $0.name == "url" })?.value,
           URL(string: originalURL)?.scheme != nil {
            let stateChanged = !state.isActive || state.originalURL != originalURL
            if stateChanged {
                tab.state.readerMode.isActive = true
                tab.state.readerMode.originalURL = originalURL
                delegate?.readerModeController(self, didChangeStateFor: tab)
            }
            return originalURL
        }
        
        if state.isActive || state.isReaderable || state.originalURL != nil {
            tab.state.readerMode.isActive = false
            tab.state.readerMode.isReaderable = false
            tab.state.readerMode.originalURL = nil
            delegate?.readerModeController(self, didChangeStateFor: tab)
        }
        return engineURL
    }
    
    func addonPortDidConnect(_ port: AddonPort) {
        guard port.sender.extensionID == Self.extensionID,
              port.sender.isTopLevel else {
            port.disconnect()
            return
        }
        
        guard port.sender.session != nil else {
            port.disconnect()
            return
        }
        let sessionID = port.sender.sessionIdentifier
        port.delegate = self
        switch port.name {
        case Self.contentPortName where port.sender.environment == .contentScript:
            contentPorts[sessionID]?.disconnect()
            contentPorts[sessionID] = port
            port.postMessage(["action": "checkReaderState"])
        case Self.activePortName where port.sender.environment == .extensionPage:
            activePorts[sessionID]?.disconnect()
            activePorts[sessionID] = port
            port.postMessage(["action": "checkReaderState"])
        default:
            port.disconnect()
        }
    }
    
    func addonPort(_ port: AddonPort, didReceive message: Any) {
        guard let payload = message as? [String: Any?],
              let session = port.sender.session,
              let tab = delegate?.readerModeController(self, tabFor: session) else {
            return
        }
        
        if let baseURL = payload["baseUrl"] as? String, !baseURL.isEmpty {
            extensionBaseURL = baseURL
        }
        
        if port.name == Self.activePortName {
            guard let originalURL = payload["activeUrl"] as? String else {
                return
            }
            tab.state.readerMode.isReaderable = true
            tab.state.readerMode.isActive = true
            tab.state.readerMode.originalURL = originalURL
            port.postMessage(makeShowMessage(scrollY: tab.state.readerMode.sourceScrollY))
        } else {
            let isReaderable: Bool
            if let readerable = payload["readerable"] as? Bool {
                isReaderable = readerable
            } else if let readerable = payload["readerable"] as? NSNumber {
                isReaderable = readerable.boolValue
            } else {
                isReaderable = false
            }
            tab.state.readerMode.isReaderable = isReaderable
        }
        delegate?.readerModeController(self, didChangeStateFor: tab)
        
        if port.name == Self.contentPortName {
            enterAutomaticallyIfNeeded(in: tab, from: port)
        }
    }
    
    func addonPortDidDisconnect(_ port: AddonPort) {
        let sessionID = port.sender.sessionIdentifier
        if contentPorts[sessionID] === port {
            contentPorts.removeValue(forKey: sessionID)
        }
        if activePorts[sessionID] === port {
            activePorts.removeValue(forKey: sessionID)
        }
    }
    
    private func ensureExtensionInstalled() async {
        do {
            let addon = try await AddonRuntime.shared.ensureBuiltIn(
                location: Self.extensionLocation,
                id: Self.extensionID
            )
            extensionBaseURL = addon.metaData.baseURL
        } catch {
            NSLog("Failed to install Reader View extension: %@", "\(error)")
        }
    }
    
    private func makeShowMessage(scrollY: Int?) -> [String: Any?] {
        var options: [String: Any?] = [
            "fontSize": appearance.fontSizeStep,
            "fontType": appearance.fontType.rawValue,
            "colorScheme": appearance.colorScheme.rawValue,
        ]
        if let scrollY {
            options["scrollY"] = scrollY
        }
        return [
            "action": "show",
            "value": options,
        ]
    }
    
    private func sendToActivePort(_ message: [String: Any?], for session: GeckoSession?) {
        guard let session else { return }
        activePorts[ObjectIdentifier(session)]?.postMessage(message)
    }
}
