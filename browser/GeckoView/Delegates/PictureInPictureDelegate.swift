//
//  PictureInPictureDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 17/7/26.
//

import AVFoundation

public protocol PictureInPictureDelegate: AnyObject {
    func onSourceChanged(session: GeckoSession)
}

public extension PictureInPictureDelegate {
    func onSourceChanged(session: GeckoSession) {}
}

final class PictureInPictureHandler: GeckoSessionHandlerCommon {
    let moduleName: String? = nil
    let events = ["GeckoView:PictureInPicture:SourceChanged"]
    let enabled = true
    
    private weak var session: GeckoSession?
    weak var delegate: PictureInPictureDelegate?
    
    var displayLayer: AVSampleBufferDisplayLayer? {
        return autoreleasepool {
            session?.window?.pictureInPictureDisplayLayer()
        }
    }
    
    init(session: GeckoSession) {
        self.session = session
    }
    
    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        guard events.contains(type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        guard let session else {
            throw GeckoHandlerError("session has been destroyed")
        }
        delegate?.onSourceChanged(session: session)
        return nil
    }
}

func newPictureInPictureHandler(_ session: GeckoSession) -> PictureInPictureHandler {
    return PictureInPictureHandler(session: session)
}
