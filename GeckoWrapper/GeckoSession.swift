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

public class GeckoSession {
    let dispatcher: GeckoEventDispatcherWrapper = GeckoEventDispatcherWrapper()
    var window: GeckoViewWindow?
    var id: String?

    lazy var contentHandler = newContentHandler(self)
    lazy var processHangHandler = newProcessHangHandler(self)
    public var contentDelegate: ContentDelegate? {
        get { contentHandler.delegate }
        set {
            contentHandler.delegate = newValue
            processHangHandler.delegate = newValue
        }
    }

    lazy var navigationHandler = newNavigationHandler(self)
    public var navigationDelegate: NavigationDelegate? {
        get { navigationHandler.delegate }
        set { navigationHandler.delegate = newValue }
    }

    lazy var progressHandler = newProgressHandler(self)
    public var progressDelegate: ProgressDelegate? {
        get { progressHandler.delegate }
        set { progressHandler.delegate = newValue }
    }

    lazy var sessionHandlers: [GeckoSessionHandlerCommon] = [
        contentHandler,
        processHangHandler,
        navigationHandler,
        progressHandler,
    ]

    public init() {
        for sessionHandler in sessionHandlers {
            for type in sessionHandler.events {
                dispatcher.addListener(type: type, listener: sessionHandler)
            }
        }
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
            "userAgentMode": 0,
            "userAgentOverride": nil,
            "viewportMode": 0,
            "displayMode": 0,
            "suspendMediaWhenInactive": false,
            "allowJavascript": true,
            "fullAccessibilityTree": false,
            "isPopup": false,
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
            false
        )
    }

    public func isOpen() -> Bool { window != nil }

    public func close() {
        window?.close()
        window = nil
        id = nil
    }

    public func load(_ url: String) {
        dispatchLoad(url)
    }

    private func dispatchLoad(_ url: String) {
        dispatcher.dispatch(
            type: "GeckoView:LoadUri",
            message: [
                "uri": url,
                "flags": 0,
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
}
