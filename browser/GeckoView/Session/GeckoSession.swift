//
//  GeckoSession.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

protocol GeckoSessionHandlerCommon: GeckoEventListenerInternal {
    var moduleName: String { get }
    var events: [String] { get }
    var enabled: Bool { get }
}

public struct GeckoSessionSettings {
    public let userAgentOverride: String?
    public let userAgentMode: Int
    public let viewportMode: Int
    
    public init(userAgentOverride: String?, userAgentMode: Int, viewportMode: Int) {
        self.userAgentOverride = userAgentOverride
        self.userAgentMode = userAgentMode
        self.viewportMode = viewportMode
    }
}

public enum GeckoSessionLoadFlags {
    public static let none = 0
    public static let replaceHistory = 1 << 6
}

public class GeckoSession {
    let dispatcher: GeckoEventDispatcherWrapper = GeckoEventDispatcherWrapper()
    var window: GeckoViewWindow?
    var id: String?
    public var isAddonPopup = false
    public var isPrivateMode = false
    lazy var addonSessionListener = AddonSessionListener(session: self)
    public var userAgentOverride: String?
    public var userAgentMode = 0
    public var viewportMode = 0
    
    public func updateSettings(_ settings: GeckoSessionSettings) {
        userAgentOverride = settings.userAgentOverride
        userAgentMode = settings.userAgentMode
        viewportMode = settings.viewportMode
        
        guard isOpen() else { return }
        
        let uaValue: Any = settings.userAgentOverride ?? NSNull()
        dispatcher.dispatch(
            type: "GeckoView:UpdateSettings",
            message: [
                "userAgentOverride": uaValue,
                "userAgentMode": settings.userAgentMode,
                "viewportMode": settings.viewportMode,
            ])
    }
    
    lazy var contentHandler = newContentHandler(self)
    lazy var processHangHandler = newProcessHangHandler(self)
    public var contentDelegate: ContentDelegate? {
        get { contentHandler.delegate(as: ContentDelegate.self) }
        set {
            contentHandler.setDelegate(newValue)
            processHangHandler.setDelegate(newValue)
        }
    }
    
    lazy var navigationHandler = newNavigationHandler(self)
    public var navigationDelegate: NavigationDelegate? {
        get { navigationHandler.delegate(as: NavigationDelegate.self) }
        set { navigationHandler.setDelegate(newValue) }
    }
    
    lazy var permissionHandler: GeckoSessionHandler = {
        let handler = newPermissionHandler(self)
        handler.setDelegate(true as AnyObject)
        return handler
    }()
    
    lazy var progressHandler = newProgressHandler(self)
    public var progressDelegate: ProgressDelegate? {
        get { progressHandler.delegate(as: ProgressDelegate.self) }
        set { progressHandler.setDelegate(newValue) }
    }
    
    lazy var promptHandler: GeckoSessionHandler = {
        let handler = newPromptHandler(self)
        return handler
    }()
    public var promptDelegate: PromptDelegate? {
        get { promptHandler.delegate(as: PromptDelegate.self) }
        set { promptHandler.setDelegate(newValue) }
    }
    
    lazy var selectionActionHandler = newSelectionActionHandler(self)
    public var selectionActionDelegate: SelectionActionDelegate? {
        get { selectionActionHandler.delegate(as: SelectionActionDelegate.self) }
        set { selectionActionHandler.setDelegate(newValue) }
    }
    
    lazy var mediaSessionHandler = newMediaSessionHandler(self)
    public var mediaSessionDelegate: MediaSessionDelegate? {
        get { mediaSessionHandler.delegate(as: MediaSessionDelegate.self) }
        set { mediaSessionHandler.setDelegate(newValue) }
    }
    public lazy var mediaSession = MediaSession(session: self)
    
    lazy var sessionHandlers: [GeckoSessionHandlerCommon] = [
        contentHandler,
        processHangHandler,
        navigationHandler,
        permissionHandler,
        progressHandler,
        promptHandler,
        selectionActionHandler,
        mediaSessionHandler,
    ]
    
    public init() {
        for sessionHandler in sessionHandlers {
            for type in sessionHandler.events {
                dispatcher.addListener(type: type, listener: sessionHandler)
            }
        }
        
        AddonRuntime.shared.register(sessionListener: addonSessionListener)
    }
    
    public func open(windowId: String? = nil) {
        if isOpen() {
            fatalError("cannot open a GeckoSession twice")
        }
        
        id = windowId ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        
        let settings: [String: Any?] = [
            "chromeUri": nil,
            "screenId": 0,
            "useTrackingProtection": false,
            "userAgentMode": userAgentMode,
            "userAgentOverride": userAgentOverride,
            "viewportMode": viewportMode,
            "displayMode": 0,
            "suspendMediaWhenInactive": false,
            "allowJavascript": true,
            "fullAccessibilityTree": false,
            "isExtensionPopup": isAddonPopup,
            "sessionContextId": nil,
            "unsafeSessionContextId": nil,
        ]
        
        let modules = Dictionary(uniqueKeysWithValues: sessionHandlers.map {
            ($0.moduleName, $0.enabled)
        })
        
        window = GeckoViewOpenWindow(
            id,
            dispatcher,
            [
                "settings": settings,
                "modules": modules,
            ],
            isPrivateMode
        )
    }
    
    public func isOpen() -> Bool { window != nil }

    public var engineView: UIView? {
        window?.view()
    }
    
    public func close() {
        guard let window else {
            return
        }

        contentDelegate = nil
        navigationDelegate = nil
        progressDelegate = nil
        promptDelegate = nil
        selectionActionDelegate = nil
        mediaSessionDelegate = nil
        
        window.close()
        self.window = nil
        id = nil
    }
    
    public func load(_ url: String, flags: Int = GeckoSessionLoadFlags.none) {
        dispatcher.dispatch(
            type: "GeckoView:LoadUri",
            message: [
                "uri": url,
                "flags": flags,
                "headerFilter": 1,
            ])
    }
    
    public func reload() {
        dispatcher.dispatch(
            type: "GeckoView:Reload",
            message: [
                "flags": 0
            ])
    }
    
    public func stop() {
        dispatcher.dispatch(type: "GeckoView:Stop")
    }
    
    public func goBack(userInteraction: Bool = true) {
        dispatcher.dispatch(
            type: "GeckoView:GoBack",
            message: [
                "userInteraction": userInteraction
            ])
    }
    
    public func goForward(userInteraction: Bool = true) {
        dispatcher.dispatch(
            type: "GeckoView:GoForward",
            message: [
                "userInteraction": userInteraction
            ])
    }
    
    public func setActive(_ active: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetActive", message: ["active": active])
    }
    
    public func setFocused(_ focused: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetFocused", message: ["focused": focused])
    }
    
    public func focusedInputBottomRatio() async -> CGFloat? {
        let response = try? await dispatcher.query(type: "GeckoView:GetFocusedInputMetrics")
        guard let values = response as? [AnyHashable: Any],
              let bottomRatioValue = values["bottomRatio"] else {
            return nil
        }
        
        return PayloadValue.cgFloat(bottomRatioValue)
    }

    public func executeSelectionAction(actionId: String, commandId: String) {
        dispatcher.dispatch(
            type: "GeckoView:ExecuteSelectionAction",
            message: [
                "actionId": actionId,
                "id": commandId,
            ]
        )
    }
}
