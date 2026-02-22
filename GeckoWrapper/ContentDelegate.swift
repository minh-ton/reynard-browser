//
//  ContentDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

public struct ContextElement {
    public enum ElementType {
        case none
        case image
        case video
        case audio
    }

    public let baseUri: String?
    public let linkUri: String?
    public let title: String?
    public let altText: String?
    public let type: ElementType
    public let srcUri: String?
    public let textContent: String?
}

public enum SlowScriptResponse {
    case halt
    case resume
}

public protocol ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String)
    func onPreviewImage(session: GeckoSession, previewImageUrl: String)
    func onFocusRequest(session: GeckoSession)
    func onCloseRequest(session: GeckoSession)
    func onFullScreen(session: GeckoSession, fullScreen: Bool)
    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String)
    func onProductUrl(session: GeckoSession)
    func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: ContextElement)
    func onCrash(session: GeckoSession)
    func onKill(session: GeckoSession)
    func onFirstComposite(session: GeckoSession)
    func onFirstContentfulPaint(session: GeckoSession)
    func onPaintStatusReset(session: GeckoSession)
    func onWebAppManifest(session: GeckoSession, manifest: Any)
    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse
    func onShowDynamicToolbar(session: GeckoSession)
    func onCookieBannerDetected(session: GeckoSession)
    func onCookieBannerHandled(session: GeckoSession)
}

extension ContentDelegate {
    public func onTitleChange(session: GeckoSession, title: String) {}
    public func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}
    public func onFocusRequest(session: GeckoSession) {}
    public func onCloseRequest(session: GeckoSession) {}
    public func onFullScreen(session: GeckoSession, fullScreen: Bool) {}
    public func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {}
    public func onProductUrl(session: GeckoSession) {}
    public func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: ContextElement) {}
    public func onCrash(session: GeckoSession) {}
    public func onKill(session: GeckoSession) {}
    public func onFirstComposite(session: GeckoSession) {}
    public func onFirstContentfulPaint(session: GeckoSession) {}
    public func onPaintStatusReset(session: GeckoSession) {}
    public func onWebAppManifest(session: GeckoSession, manifest: Any) {}
    public func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse { .halt }
    public func onShowDynamicToolbar(session: GeckoSession) {}
    public func onCookieBannerDetected(session: GeckoSession) {}
    public func onCookieBannerHandled(session: GeckoSession) {}
}

enum ContentEvents: String, CaseIterable {
    case contentCrash = "GeckoView:ContentCrash"
    case contentKill = "GeckoView:ContentKill"
    case contextMenu = "GeckoView:ContextMenu"
    case domMetaViewportFit = "GeckoView:DOMMetaViewportFit"
    case pageTitleChanged = "GeckoView:PageTitleChanged"
    case domWindowClose = "GeckoView:DOMWindowClose"
    case externalResponse = "GeckoView:ExternalResponse"
    case focusRequest = "GeckoView:FocusRequest"
    case fullscreenEnter = "GeckoView:FullScreenEnter"
    case fullscreenExit = "GeckoView:FullScreenExit"
    case webAppManifest = "GeckoView:WebAppManifest"
    case firstContentfulPaint = "GeckoView:FirstContentfulPaint"
    case paintStatusReset = "GeckoView:PaintStatusReset"
    case previewImage = "GeckoView:PreviewImage"
    case cookieBannerEventDetected = "GeckoView:CookieBannerEvent:Detected"
    case cookieBannerEventHandled = "GeckoView:CookieBannerEvent:Handled"
    case savePdf = "GeckoView:SavePdf"
    case onProductUrl = "GeckoView:OnProductUrl"
}

func newContentHandler(_ session: GeckoSession) -> GeckoSessionHandler<ContentDelegate, ContentEvents> {
    GeckoSessionHandler(moduleName: "GeckoViewContent", session: session) {
        @MainActor session, delegate, event, message in
        switch event {
        case .contentCrash:
            session.close()
            delegate?.onCrash(session: session)
            return nil

        case .contentKill:
            session.close()
            delegate?.onKill(session: session)
            return nil

        case .contextMenu:
            func parseElementType(_ value: String) -> ContextElement.ElementType {
                switch value {
                case "HTMLImageElement":
                    return .image
                case "HTMLVideoElement":
                    return .video
                case "HTMLAudioElement":
                    return .audio
                default:
                    return .none
                }
            }

            let contextElement = ContextElement(
                baseUri: message?["baseUri"] as? String,
                linkUri: message?["linkUri"] as? String,
                title: message?["title"] as? String,
                altText: message?["alt"] as? String,
                type: parseElementType(message?["elementType"] as? String ?? ""),
                srcUri: message?["elementSrc"] as? String,
                textContent: message?["textContent"] as? String
            )

            delegate?.onContextMenu(
                session: session,
                screenX: message?["screenX"] as? Int ?? 0,
                screenY: message?["screenY"] as? Int ?? 0,
                element: contextElement
            )
            return nil

        case .domMetaViewportFit:
            delegate?.onMetaViewportFitChange(
                session: session,
                viewportFit: message?["viewportfit"] as? String ?? ""
            )
            return nil

        case .pageTitleChanged:
            delegate?.onTitleChange(session: session, title: message?["title"] as? String ?? "")
            return nil

        case .domWindowClose:
            delegate?.onCloseRequest(session: session)
            return nil

        case .externalResponse:
            throw GeckoHandlerError("GeckoView:ExternalResponse is unimplemented")

        case .focusRequest:
            delegate?.onFocusRequest(session: session)
            return nil

        case .fullscreenEnter:
            delegate?.onFullScreen(session: session, fullScreen: true)
            return nil

        case .fullscreenExit:
            delegate?.onFullScreen(session: session, fullScreen: false)
            return nil

        case .webAppManifest:
            if let manifest = message?["manifest"] {
                delegate?.onWebAppManifest(session: session, manifest: manifest as Any)
            }
            return nil

        case .firstContentfulPaint:
            delegate?.onFirstContentfulPaint(session: session)
            return nil

        case .paintStatusReset:
            delegate?.onPaintStatusReset(session: session)
            return nil

        case .previewImage:
            delegate?.onPreviewImage(
                session: session,
                previewImageUrl: message?["previewImageUrl"] as? String ?? ""
            )
            return nil

        case .cookieBannerEventDetected:
            delegate?.onCookieBannerDetected(session: session)
            return nil

        case .cookieBannerEventHandled:
            delegate?.onCookieBannerHandled(session: session)
            return nil

        case .savePdf:
            throw GeckoHandlerError("GeckoView:SavePdf is unimplemented")

        case .onProductUrl:
            delegate?.onProductUrl(session: session)
            return nil
        }
    }
}

enum ProcessHangEvents: String, CaseIterable {
    case hangReport = "GeckoView:HangReport"
}

func newProcessHangHandler(_ session: GeckoSession) -> GeckoSessionHandler<ContentDelegate, ProcessHangEvents> {
    GeckoSessionHandler(moduleName: "GeckoViewProcessHangMonitor", session: session) {
        @MainActor session, delegate, event, message in
        switch event {
        case .hangReport:
            let reportId: Int
            if let intValue = message?["hangId"] as? Int {
                reportId = intValue
            } else if let number = message?["hangId"] as? NSNumber {
                reportId = number.intValue
            } else {
                reportId = 0
            }

            let response = await delegate?.onSlowScript(
                session: session,
                scriptFileName: message?["scriptFileName"] as? String ?? ""
            )

            switch response {
            case .resume:
                session.dispatcher.dispatch(
                    type: "GeckoView:HangReportWait",
                    message: ["hangId": reportId]
                )
            default:
                session.dispatcher.dispatch(
                    type: "GeckoView:HangReportStop",
                    message: ["hangId": reportId]
                )
            }
            return nil
        }
    }
}
