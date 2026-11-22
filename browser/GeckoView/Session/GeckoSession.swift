//
//  GeckoSession.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

protocol GeckoSessionHandlerCommon: GeckoEventListenerInternal {
    var moduleName: String? { get }
    var events: [String] { get }
    var enabled: Bool { get }
}

public enum GeckoSessionLoadFlags {
    public static let none = 0
    public static let bypassCache = 1 << 0
    public static let replaceHistory = 1 << 6
}

public struct GeckoFindInPageResult {
    public let found: Bool
    public let current: Int
    public let total: Int
    
    public init(found: Bool, current: Int, total: Int) {
        self.found = found
        self.current = current
        self.total = total
    }
}

public class GeckoSession {
    // MARK: - State
    
    var id: String?
    var window: GeckoViewWindow?
    private let stateCache = GeckoSessionState()
    private var awaitsPurgedHistoryState = false
    
    public let isAddonPopup: Bool
    public let isPrivateMode: Bool
    public private(set) var settings: GeckoSessionSettings
    
    let dispatcher: GeckoEventDispatcherWrapper = GeckoEventDispatcherWrapper()
    lazy var addonSessionListener = AddonSessionListener(session: self)
    
    public var currentSessionState: GeckoSessionState? {
        guard !awaitsPurgedHistoryState,
              !stateCache.isEmpty else {
            return nil
        }
        return GeckoSessionState(copying: stateCache)
    }
    
    // MARK: - Delegates
    
    public func updateSettings(_ settings: GeckoSessionSettings) {
        self.settings = settings
        GeckoRuntime.setLocale(acceptLanguages: settings.language.acceptLanguages)
        
        guard isOpen() else { return }
        
        dispatcher.dispatch(
            type: "GeckoView:UpdateSettings",
            message: [
                "userAgentOverride": settings.websiteMode.userAgentOverride ?? NSNull(),
                "platformOverride": settings.websiteMode.platformOverride ?? NSNull(),
                "appVersionOverride": settings.websiteMode.appVersionOverride ?? NSNull(),
                "oscpuOverride": settings.websiteMode.oscpuOverride ?? NSNull(),
                "buildIDOverride": settings.websiteMode.buildIDOverride ?? NSNull(),
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
    
    lazy var contentBlockingHandler = newContentBlockingHandler(self)
    public var contentBlockingDelegate: ContentBlockingDelegate? {
        get { contentBlockingHandler.delegate(as: ContentBlockingDelegate.self) }
        set { contentBlockingHandler.setDelegate(newValue) }
    }
    
    lazy var navigationHandler = newNavigationHandler(self)
    public var navigationDelegate: NavigationDelegate? {
        get { navigationHandler.delegate(as: NavigationDelegate.self) }
        set { navigationHandler.setDelegate(newValue) }
    }
    
    lazy var historyHandler = newHistoryHandler(self)
    public var historyDelegate: HistoryDelegate? {
        get { historyHandler.delegate(as: HistoryDelegate.self) }
        set { historyHandler.setDelegate(newValue) }
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
    
    lazy var scrollHandler = newScrollHandler(self)
    public var scrollDelegate: ScrollDelegate? {
        get { scrollHandler.delegate(as: ScrollDelegate.self) }
        set { scrollHandler.setDelegate(newValue) }
    }
    
    lazy var promptHandler: GeckoSessionHandler = {
        let handler = newPromptHandler(self)
        return handler
    }()
    public var promptDelegate: PromptDelegate? {
        get { promptHandler.delegate(as: PromptDelegate.self) }
        set { promptHandler.setDelegate(newValue) }
    }
    
    lazy var printHandler = newPrintHandler(self)
    public var printDelegate: PrintDelegate? {
        get { printHandler.delegate(as: PrintDelegate.self) }
        set { printHandler.setDelegate(newValue) }
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
    
    public func notifyScreenOrientationChanged(to orientation: UIInterfaceOrientation) {
        window?.updateScreenOrientation(orientation.rawValue)
    }
    
    // MARK: - Session Handlers
    
    lazy var sessionHandlers: [GeckoSessionHandlerCommon] = [
        contentHandler,
        contentBlockingHandler,
        processHangHandler,
        navigationHandler,
        historyHandler,
        permissionHandler,
        progressHandler,
        scrollHandler,
        promptHandler,
        printHandler,
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
        GeckoRuntime.setLocale(acceptLanguages: sessionSettings.language.acceptLanguages)
        
        let settings: [String: Any?] = [
            "chromeUri": nil,
            "screenId": 0,
            "useTrackingProtection": false,
            "userAgentMode": sessionSettings.websiteMode.userAgentMode,
            "userAgentOverride": sessionSettings.websiteMode.userAgentOverride,
            "platformOverride": sessionSettings.websiteMode.platformOverride,
            "appVersionOverride": sessionSettings.websiteMode.appVersionOverride,
            "oscpuOverride": sessionSettings.websiteMode.oscpuOverride,
            "buildIDOverride": sessionSettings.websiteMode.buildIDOverride,
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
        
        let modules: [String: Bool] = Dictionary(
            uniqueKeysWithValues: sessionHandlers.compactMap {
                guard let moduleName = $0.moduleName else {
                    return nil
                }
                return (moduleName, $0.enabled)
            }
        )
        
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
        contentBlockingDelegate = nil
        navigationDelegate = nil
        historyDelegate = nil
        permissionDelegate = nil
        progressDelegate = nil
        scrollDelegate = nil
        promptDelegate = nil
        printDelegate = nil
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
    
    public func reload(flags: Int = GeckoSessionLoadFlags.none) {
        dispatcher.dispatch(
            type: "GeckoView:Reload",
            message: [
                "flags": flags
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
    
    public func goToHistoryIndex(_ index: Int) {
        dispatcher.dispatch(type: "GeckoView:GotoHistoryIndex", message: ["index": index])
    }
    
    public func purgeHistory() {
        awaitsPurgedHistoryState = stateCache.history.count > 1
        dispatcher.dispatch(type: "GeckoView:PurgeHistory")
    }
    
    public func adoptPreview(_ preview: GeckoSession) async throws {
        _ = try await dispatcher.query(
            type: "GeckoView:AdoptPreview",
            message: ["previewSessionId": preview.id]
        )
    }
    
    // MARK: - Full screen
    
    public func exitFullScreen() {
        dispatcher.dispatch(type: "GeckoViewContent:ExitFullScreen")
    }
    
    // MARK: - Error Pages
    
    public var currentLoadError: WebRequestError? {
        return window?.errorPageURI().flatMap(WebRequestError.init(pageURI:))
    }
    
    public func addCertException(for error: WebRequestError) -> Bool {
        guard error.kind == .securityBadCertificate,
              window?.addCertException(pageURI: error.pageURI) == true else {
            return false
        }
        
        reload()
        return true
    }
    
    public func reloadWithHttpsOnlyException(for error: WebRequestError) -> Bool {
        guard error.kind == .httpsOnly else {
            return false
        }
        
        return window?.reloadWithHttpsOnlyException(pageURI: error.pageURI) == true
    }
    
    // MARK: - Image Loading
    
    @MainActor
    public func fetchImageData(from url: URL) async throws -> Data {
        guard isOpen() else {
            throw GeckoHandlerError("Session is closed")
        }
        
        let response = try await dispatcher.query(
            type: "GeckoView:FetchImage",
            message: ["url": url.absoluteString]
        )
        guard let base64 = response as? String,
              let data = Data(base64Encoded: base64) else {
            throw GeckoHandlerError("Invalid image response")
        }
        return data
    }
    
    // MARK: - Find in Page
    
    @MainActor
    public func findInPage(
        _ searchString: String? = nil,
        backwards: Bool = false
    ) async throws -> GeckoFindInPageResult {
        var message: [String: Any?] = [:]
        if let searchString {
            message["searchString"] = searchString
        }
        if backwards {
            message["backwards"] = true
        }
        let response = try await dispatcher.query(type: "GeckoView:FindInPage", message: message)
        let payload: [String: Any?]
        if let values = response as? [String: Any] {
            payload = values.mapValues { $0 }
        } else if let values = response as? [String: Any?] {
            payload = values
        } else {
            throw GeckoHandlerError("Invalid find-in-page response")
        }
        return GeckoFindInPageResult(
            found: PayloadValue.bool(payload["found"]) ?? false,
            current: PayloadValue.int(payload["current"]) ?? 0,
            total: PayloadValue.int(payload["total"]) ?? 0
        )
    }
    
    public func setFindInPageMatchHighlighting(_ enabled: Bool) {
        dispatcher.dispatch(
            type: "GeckoView:DisplayMatches",
            message: [
                "highlightAll": enabled,
                "dimPage": true,
                "drawOutline": false,
            ]
        )
    }
    
    public func clearFindInPageMatches() {
        dispatcher.dispatch(type: "GeckoView:ClearMatches")
        setFindInPageMatchHighlighting(false)
    }
    
    public func scrollTo(_ position: CGPoint, animated: Bool = true) {
        dispatcher.dispatch(
            type: "GeckoView:ScrollTo",
            message: [
                "widthValue": position.x,
                "widthType": 0,
                "heightValue": position.y,
                "heightType": 0,
                "behavior": animated ? 0 : 1,
            ])
    }
    
    // MARK: - Printing
    
    @MainActor
    public func printToPDF(browsingContextId: Int64? = nil) async throws -> URL {
        guard let window else {
            throw GeckoHandlerError("session window is unavailable")
        }
        
        if browsingContextId == nil,
           let isPDFDocument = try? await dispatcher.query(type: "GeckoView:IsPdfJs"),
           PayloadValue.bool(isPDFDocument) == true {
            let response = try await dispatcher.query(type: "GeckoView:PDFSave")
            let payload: [String: Any?]
            
            if let values = response as? [String: Any] {
                payload = values.mapValues { $0 }
            } else if let values = response as? [String: Any?] {
                payload = values
            } else {
                throw GeckoHandlerError("Invalid PDF document response")
            }
            
            guard let sourceURL = PayloadValue.string(payload["url"]) else {
                throw GeckoHandlerError("PDF document source is unavailable")
            }
            
            return try await savePDFDocument(from: sourceURL, using: window)
        }
        
        if browsingContextId == nil {
            setFocused(true)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let browsingContextId = browsingContextId.map { NSNumber(value: $0) }
            window.printToPDF(browsingContextId: browsingContextId) { fileURL, error in
                if let fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: error ?? GeckoHandlerError("PDF generation failed"))
                }
            }
        }
    }
    
    @MainActor
    private func savePDFDocument(
        from sourceURL: String,
        using window: GeckoViewWindow
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            window.savePDFDocument(sourceURL: sourceURL) { fileURL, error in
                if let fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: error ?? GeckoHandlerError("PDF document save failed"))
                }
            }
        }
    }
    
    // MARK: - State Updates
    
    public func setActive(_ active: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetActive", message: ["active": active])
        if !active {
            flushSessionState()
        }
    }
    
    public func setFocused(_ focused: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetFocused", message: ["focused": focused])
    }
    
    public func flushSessionState() {
        dispatcher.dispatch(type: "GeckoView:FlushSessionState")
    }
    
    public func flushSessionState() async throws {
        _ = try await dispatcher.query(type: "GeckoView:FlushSessionState")
    }
    
    public func restoreState(_ state: GeckoSessionState) {
        awaitsPurgedHistoryState = false
        stateCache.replace(with: state)
        dispatcher.dispatch(type: "GeckoView:RestoreState", message: state.restorePayload)
    }
    
    func handleSessionStateUpdate(_ stateUpdate: [String: Any]) {
        let previousHistoryCount = stateCache.history.count
        if awaitsPurgedHistoryState,
           let historyChange = stateUpdate["historychange"] as? [String: Any] {
            let updatedState = GeckoSessionState(copying: stateCache)
            updatedState.update(with: stateUpdate)
            guard PayloadValue.int(historyChange["fromIdx"]) == -1,
                  updatedState.history.count <= 1 else {
                return
            }
            stateCache.replace(with: updatedState)
            awaitsPurgedHistoryState = false
        } else {
            stateCache.update(with: stateUpdate)
        }
        guard !awaitsPurgedHistoryState else {
            return
        }
        let sessionState = GeckoSessionState(copying: stateCache)
        if !sessionState.isEmpty {
            progressDelegate?.onSessionStateChange(session: self, sessionState: sessionState)
        }
        guard stateUpdate["historychange"] != nil else {
            return
        }
        historyDelegate?.onHistoryStateChange(session: self, sessionState: sessionState)
        if previousHistoryCount > 1,
           sessionState.history.count == 1 {
            navigationDelegate?.onCanGoForward(session: self, canGoForward: false)
            navigationDelegate?.onCanGoBack(session: self, canGoBack: false)
        }
    }
    
    // Keyboard
    public func dismissSoftwareKeyboard() {
        window?.dismissSoftwareKeyboard()
    }
    
    public func focusedInputMetrics() async -> (bottomRatio: CGFloat, caretTop: CGFloat?)? {
        let response = try? await dispatcher.query(type: "GeckoView:GetFocusedInputMetrics")
        guard let values = response as? [AnyHashable: Any],
              let bottomRatio = PayloadValue.cgFloat(values["bottomRatio"]),
              let engineView else {
            return nil
        }
        let caretTop = PayloadValue.cgFloat(values["caretTop"])
        return (bottomRatio, caretTop.map { $0 / engineView.contentScaleFactor })
    }
    
    @discardableResult
    public func focusForHardwareKeyboard() -> Bool {
        return window?.focusForHardwareKeyboard() ?? false
    }
    
    public func isInHardwareKeyboardMode() -> Bool {
        return window?.isInHardwareKeyboardMode() ?? false
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
    
    // MARK: - Toolbar
    public func setDynamicToolbarMaxHeight(_ height: CGFloat, minHeight: CGFloat) {
        let maxHeight = max(0, height)
        window?.setDynamicToolbarMaxHeight(maxHeight, minHeight: min(max(0, minHeight), maxHeight))
    }
    
    public func setContentOffsets(
        top: CGFloat,
        bottom: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentTranslationY: CGFloat
    ) {
        window?.setContentOffsets(
            top,
            bottom: bottom,
            topInset: topInset,
            bottomInset: bottomInset,
            contentTranslationY: contentTranslationY
        )
    }
}
