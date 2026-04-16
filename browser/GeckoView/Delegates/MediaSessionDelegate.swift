//
//  MediaSessionDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 9/4/26.
//

import Foundation
import MediaPlayer

public struct MediaSessionMetadata {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let artworkUrl: String?
}

public struct MediaSessionPositionState {
    public let duration: Double
    public let playbackRate: Double
    public let position: Double
}

public struct MediaSessionFeatures: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    
    public static let play = MediaSessionFeatures(rawValue: 1 << 0)
    public static let pause = MediaSessionFeatures(rawValue: 1 << 1)
    public static let stop = MediaSessionFeatures(rawValue: 1 << 2)
    public static let seekForward = MediaSessionFeatures(rawValue: 1 << 3)
    public static let seekBackward = MediaSessionFeatures(rawValue: 1 << 4)
    public static let seekTo = MediaSessionFeatures(rawValue: 1 << 5)
    public static let skipAd = MediaSessionFeatures(rawValue: 1 << 6)
    public static let nextTrack = MediaSessionFeatures(rawValue: 1 << 7)
    public static let prevTrack = MediaSessionFeatures(rawValue: 1 << 8)
    public static let muteAudio = MediaSessionFeatures(rawValue: 1 << 9)
}

public protocol MediaSessionDelegate: AnyObject {
    func onActivated(session: GeckoSession)
    func onDeactivated(session: GeckoSession)
    func onMetadata(session: GeckoSession, metadata: MediaSessionMetadata)
    func onPlaybackPlaying(session: GeckoSession)
    func onPlaybackPaused(session: GeckoSession)
    func onPlaybackNone(session: GeckoSession)
    func onFeatures(session: GeckoSession, features: MediaSessionFeatures)
    func onPositionState(session: GeckoSession, state: MediaSessionPositionState)
}

public extension MediaSessionDelegate {
    func onActivated(session: GeckoSession) {}
    func onDeactivated(session: GeckoSession) {}
    func onMetadata(session: GeckoSession, metadata: MediaSessionMetadata) {}
    func onPlaybackPlaying(session: GeckoSession) {}
    func onPlaybackPaused(session: GeckoSession) {}
    func onPlaybackNone(session: GeckoSession) {}
    func onFeatures(session: GeckoSession, features: MediaSessionFeatures) {}
    func onPositionState(session: GeckoSession, state: MediaSessionPositionState) {}
}

// Allows the host app to send playback control commands to Gecko.
public class MediaSession {
    weak var session: GeckoSession?
    
    init(session: GeckoSession) {
        self.session = session
    }
    
    public func play() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:Play")
    }
    
    public func pause() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:Pause")
    }
    
    public func stop() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:Stop")
    }
    
    public func nextTrack() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:NextTrack")
    }
    
    public func previousTrack() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:PrevTrack")
    }
    
    public func seekForward() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:SeekForward")
    }
    
    public func seekBackward() {
        session?.dispatcher.dispatch(type: "GeckoView:MediaSession:SeekBackward")
    }
    
    public func seekTo(time: Double, fast: Bool = false) {
        session?.dispatcher.dispatch(
            type: "GeckoView:MediaSession:SeekTo",
            message: ["time": time, "fast": fast]
        )
    }
}

private enum MediaSessionEvent: String, CaseIterable {
    case activated = "GeckoView:MediaSession:Activated"
    case deactivated = "GeckoView:MediaSession:Deactivated"
    case metadata = "GeckoView:MediaSession:Metadata"
    case playing = "GeckoView:MediaSession:Playback:Playing"
    case paused = "GeckoView:MediaSession:Playback:Paused"
    case none = "GeckoView:MediaSession:Playback:None"
    case features = "GeckoView:MediaSession:Features"
    case positionState = "GeckoView:MediaSession:PositionState"
}

func newMediaSessionHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewMediaControl",
        events: MediaSessionEvent.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = MediaSessionEvent(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        let delegate = delegate as? MediaSessionDelegate
        
        switch event {
        case .activated:
            delegate?.onActivated(session: session)
            
        case .deactivated:
            delegate?.onDeactivated(session: session)
            
        case .metadata:
            if let metaDict = message?["metadata"] as? [String: Any] {
                let artworkUrl = (metaDict["artwork"] as? [[String: Any]])?.first?["src"] as? String
                let metadata = MediaSessionMetadata(
                    title: metaDict["title"] as? String,
                    artist: metaDict["artist"] as? String,
                    album: metaDict["album"] as? String,
                    artworkUrl: artworkUrl
                )
                delegate?.onMetadata(session: session, metadata: metadata)
            }
            
        case .playing:
            delegate?.onPlaybackPlaying(session: session)
            
        case .paused:
            delegate?.onPlaybackPaused(session: session)
            
        case .none:
            delegate?.onPlaybackNone(session: session)
            
        case .features:
            let featDict = message?["features"] as? [String: Any] ?? [:]
            var features = MediaSessionFeatures()
            if featDict["play"] as? Bool == true { features.insert(.play) }
            if featDict["pause"] as? Bool == true { features.insert(.pause) }
            if featDict["stop"] as? Bool == true { features.insert(.stop) }
            if featDict["seekforward"] as? Bool == true { features.insert(.seekForward) }
            if featDict["seekbackward"] as? Bool == true { features.insert(.seekBackward) }
            if featDict["seekto"] as? Bool == true { features.insert(.seekTo) }
            if featDict["skipad"] as? Bool == true { features.insert(.skipAd) }
            if featDict["nexttrack"] as? Bool == true { features.insert(.nextTrack) }
            if featDict["previoustrack"] as? Bool == true { features.insert(.prevTrack) }
            if featDict["muteaudio"] as? Bool == true { features.insert(.muteAudio) }
            delegate?.onFeatures(session: session, features: features)
            
        case .positionState:
            if let stateDict = message?["state"] as? [String: Any] {
                let positionState = MediaSessionPositionState(
                    duration: stateDict["duration"] as? Double ?? 0,
                    playbackRate: stateDict["playbackRate"] as? Double ?? 1,
                    position: stateDict["position"] as? Double ?? 0
                )
                delegate?.onPositionState(session: session, state: positionState)
            }
        }
        
        return nil
    }
}
