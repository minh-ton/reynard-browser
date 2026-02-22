//
//  NavigationDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

public enum LoadRequestTarget {
    case current
    case new
}

public struct LoadRequest {
    public let uri: String
    public let triggerUri: String?
    public let target: LoadRequestTarget
    public let isRedirect: Bool
    public let hasUserGesture: Bool
    public let isDirectNavigation: Bool
}

public protocol NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission])
    func onCanGoBack(session: GeckoSession, canGoBack: Bool)
    func onCanGoForward(session: GeckoSession, canGoForward: Bool)
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny
    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny
    func onNewSession(session: GeckoSession, uri: String) async -> GeckoSession?
}

extension NavigationDelegate {
    public func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {}
    public func onCanGoBack(session: GeckoSession, canGoBack: Bool) {}
    public func onCanGoForward(session: GeckoSession, canGoForward: Bool) {}
    public func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
    public func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
    public func onNewSession(session: GeckoSession, uri: String) async -> GeckoSession? { nil }
}

enum NavigationEvents: String, CaseIterable {
    case locationChange = "GeckoView:LocationChange"
    case onNewSession = "GeckoView:OnNewSession"
    case onLoadError = "GeckoView:OnLoadError"
    case onLoadRequest = "GeckoView:OnLoadRequest"
}

func newNavigationHandler(_ session: GeckoSession) -> GeckoSessionHandler<NavigationDelegate, NavigationEvents> {
    GeckoSessionHandler(moduleName: "GeckoViewNavigation", session: session) {
        @MainActor session, delegate, event, message in
        switch event {
        case .locationChange:
            if message?["isTopLevel"] as? Bool == true {
                let rawPermissions = message?["permissions"] as? [[String: Any?]]
                delegate?.onLocationChange(
                    session: session,
                    url: message?["uri"] as? String,
                    permissions: rawPermissions?.map(ContentPermission.fromDictionary) ?? []
                )
            }

            delegate?.onCanGoBack(session: session, canGoBack: message?["canGoBack"] as? Bool ?? false)
            delegate?.onCanGoForward(
                session: session,
                canGoForward: message?["canGoForward"] as? Bool ?? false
            )
            return nil

        case .onNewSession:
            guard
                let uri = message?["uri"] as? String,
                let newSessionId = message?["newSessionId"] as? String
            else {
                return false
            }

            if let newSession = await delegate?.onNewSession(session: session, uri: uri) {
                if !newSession.isOpen() {
                    newSession.open(windowId: newSessionId)
                }
                return true
            }
            return false

        case .onLoadError:
            return nil

        case .onLoadRequest:
            guard let uri = message?["uri"] as? String else {
                return true
            }

            func convertTarget(_ value: Int32) -> LoadRequestTarget {
                switch value {
                case 0, 1:
                    return .current
                default:
                    return .new
                }
            }

            let flags: Int
            if let intFlags = message?["flags"] as? Int {
                flags = intFlags
            } else if let numFlags = message?["flags"] as? NSNumber {
                flags = numFlags.intValue
            } else {
                flags = 0
            }

            let targetValue: Int32
            if let int32Where = message?["where"] as? Int32 {
                targetValue = int32Where
            } else if let numberWhere = message?["where"] as? NSNumber {
                targetValue = numberWhere.int32Value
            } else {
                targetValue = 0
            }

            let LOAD_REQUEST_IS_REDIRECT = 0x800000
            let request = LoadRequest(
                uri: uri,
                triggerUri: message?["triggerUri"] as? String,
                target: convertTarget(targetValue),
                isRedirect: (flags & LOAD_REQUEST_IS_REDIRECT) != 0,
                hasUserGesture: message?["hasUserGesture"] as? Bool ?? false,
                isDirectNavigation: true
            )

            let isTopLevel = message?["isTopLevel"] as? Bool ?? true
            if isTopLevel {
                return await delegate?.onLoadRequest(session: session, request: request) == .allow
            }
            return await delegate?.onSubframeLoadRequest(session: session, request: request) == .allow
        }
    }
}
