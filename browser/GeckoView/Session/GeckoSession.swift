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

public enum GeckoSessionLoadFlags {
    public static let none = 0
    public static let replaceHistory = 1 << 6
}

public class GeckoSession {
    // MARK: - State
    
    let dispatcher: GeckoEventDispatcherWrapper = GeckoEventDispatcherWrapper()
    var window: GeckoViewWindow?
    var id: String?
    public let isAddonPopup: Bool
    public let isPrivateMode: Bool
    lazy var addonSessionListener = AddonSessionListener(session: self)
    public private(set) var settings: GeckoSessionSettings
    
    // MARK: - Delegates
    
    public func updateSettings(_ settings: GeckoSessionSettings) {
        self.settings = settings
        
        guard isOpen() else { return }
        
        dispatcher.dispatch(
            type: "GeckoView:UpdateSettings",
            message: [
                "userAgentOverride": settings.websiteMode.userAgentOverride ?? NSNull(),
                "userAgentMode": settings.websiteMode.userAgentMode,
                "viewportMode": settings.websiteMode.viewportMode,
                "pageZoom": settings.pageZoom.scale,
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
    
    lazy var permissionHandler = newPermissionHandler(self)
    public var permissionDelegate: PermissionEmbedderDelegate? {
        get { permissionHandler.delegate(as: PermissionEmbedderDelegate.self) }
        set { permissionHandler.setDelegate(newValue) }
    }
    
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
    
    // MARK: - Session Handlers
    
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
    
    // MARK: - Lifecycle
    
    public init(
        settings: GeckoSessionSettings = .default,
        isPrivateMode: Bool = false,
        isAddonPopup: Bool = false
    ) {
        self.settings = settings
        self.isPrivateMode = isPrivateMode
        self.isAddonPopup = isAddonPopup
        
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
        
        let sessionSettings = settings
        let settings: [String: Any?] = [
            "chromeUri": nil,
            "screenId": 0,
            "useTrackingProtection": false,
            "userAgentMode": sessionSettings.websiteMode.userAgentMode,
            "userAgentOverride": sessionSettings.websiteMode.userAgentOverride,
            "viewportMode": sessionSettings.websiteMode.viewportMode,
            "pageZoom": sessionSettings.pageZoom.scale,
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
        return window?.view()
    }
    
    public func close() {
        contentDelegate = nil
        navigationDelegate = nil
        permissionDelegate = nil
        progressDelegate = nil
        promptDelegate = nil
        selectionActionDelegate = nil
        mediaSessionDelegate?.onDeactivated(session: self)
        mediaSessionDelegate = nil
        
        guard let window else {
            return
        }
        
        window.close()
        self.window = nil
        id = nil
    }
    
    // MARK: - Navigation
    
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
    
    // MARK: - State Updates
    
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
    
    // MARK: - Selection Actions
    
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
