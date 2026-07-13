//
//  SystemMediaSession.swift
//  Reynard
//
//  Created by Minh Ton on 9/4/26.
//

import Foundation
import GeckoView
import MediaPlayer

final class SystemMediaSession: MediaSessionDelegate {
    private enum PlaybackState {
        case none
        case paused
        case playing
    }
    
    private final class SessionState {
        weak var session: GeckoSession?
        var nowPlayingInfo: [String: Any] = [:]
        var features: MediaSessionFeatures = [.seekForward, .seekBackward, .seekTo]
        var artworkTask: URLSessionDataTask?
        var playbackState = PlaybackState.none
        
        init(session: GeckoSession) {
            self.session = session
        }
    }
    
    private weak var activeSession: GeckoSession?
    private weak var selectedSession: GeckoSession?
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var sessionStates: [ObjectIdentifier: SessionState] = [:]
    private var playbackHistory: [ObjectIdentifier] = []
    private var commandTargets: [Any] = []
    
    init() {
        registerRemoteCommands()
        apply(MediaSessionFeatures())
    }
    
    deinit {
        if activeSession != nil {
            nowPlayingCenter.nowPlayingInfo = nil
        }
        sessionStates.values.forEach { $0.artworkTask?.cancel() }
        unregisterRemoteCommands()
    }
    
    func onActivated(session: GeckoSession) {
        _ = state(for: session)
    }
    
    func onDeactivated(session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        let wasActive = activeSession === session
        if selectedSession === session {
            selectedSession = nil
        }
        sessionStates.removeValue(forKey: identifier)?.artworkTask?.cancel()
        playbackHistory.removeAll { $0 == identifier }
        
        if wasActive {
            activateMostRecentPlayingSession()
        }
    }
    
    func onMetadata(session: GeckoSession, metadata: MediaSessionMetadata) {
        let state = state(for: session)
        state.nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.title ?? ""
        state.nowPlayingInfo[MPMediaItemPropertyArtist] = metadata.artist ?? ""
        state.nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata.album ?? ""
        
        if activeSession === session {
            nowPlayingCenter.nowPlayingInfo = state.nowPlayingInfo
        }
        
        state.artworkTask?.cancel()
        state.artworkTask = nil
        
        if let artworkURLString = metadata.artworkUrl,
           let artworkURL = URL(string: artworkURLString) {
            let task = URLSession.shared.dataTask(with: artworkURL) { [weak self, weak state] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    guard let self, let state else { return }
                    state.artworkTask = nil
                    state.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    if self.activeSession === state.session {
                        self.nowPlayingCenter.nowPlayingInfo = state.nowPlayingInfo
                    }
                }
            }
            task.resume()
            state.artworkTask = task
        }
    }
    
    func onPlaybackPlaying(session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        let state = state(for: session)
        state.playbackState = .playing
        state.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        playbackHistory.removeAll { $0 == identifier }
        playbackHistory.append(identifier)
        
        if let selectedSession,
           selectedSession !== session,
           let selectedState = sessionStates[ObjectIdentifier(selectedSession)],
           selectedState.playbackState != .none {
            return
        }
        activate(session, state: state)
    }
    
    func onPlaybackPaused(session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        let state = state(for: session)
        state.playbackState = .paused
        state.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        playbackHistory.removeAll { $0 == identifier }
        
        if activeSession === session {
            nowPlayingCenter.nowPlayingInfo = state.nowPlayingInfo
            apply(state.features)
        }
    }
    
    func onPlaybackNone(session: GeckoSession) {
        let identifier = ObjectIdentifier(session)
        let state = state(for: session)
        state.playbackState = .none
        playbackHistory.removeAll { $0 == identifier }
        
        if activeSession === session {
            activateMostRecentPlayingSession()
        }
    }
    
    func select(session: GeckoSession) {
        selectedSession = session
        guard let state = sessionStates[ObjectIdentifier(session)],
              state.playbackState != .none else {
            return
        }
        
        activate(session, state: state)
    }
    
    func onPositionState(session: GeckoSession, state: MediaSessionPositionState) {
        let sessionState = self.state(for: session)
        sessionState.nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = state.duration
        sessionState.nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.position
        sessionState.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = state.playbackRate
        
        if activeSession === session {
            nowPlayingCenter.nowPlayingInfo = sessionState.nowPlayingInfo
        }
    }
    
    func onFeatures(session: GeckoSession, features: MediaSessionFeatures) {
        let state = state(for: session)
        state.features = features
        
        if activeSession === session {
            apply(features)
        }
    }
    
    private func state(for session: GeckoSession) -> SessionState {
        let identifier = ObjectIdentifier(session)
        if let state = sessionStates[identifier] {
            return state
        }
        
        let state = SessionState(session: session)
        sessionStates[identifier] = state
        return state
    }
    
    private func activate(_ session: GeckoSession, state: SessionState) {
        activeSession = session
        nowPlayingCenter.nowPlayingInfo = state.nowPlayingInfo
        apply(state.features)
    }
    
    private func activateMostRecentPlayingSession() {
        while let identifier = playbackHistory.last {
            guard let state = sessionStates[identifier],
                  state.playbackState == .playing,
                  let session = state.session else {
                playbackHistory.removeLast()
                continue
            }
            
            activate(session, state: state)
            return
        }
        
        activeSession = nil
        nowPlayingCenter.nowPlayingInfo = nil
        apply(MediaSessionFeatures())
    }
    
    private func apply(_ features: MediaSessionFeatures) {
        let hasActivePlayback = activeSession.flatMap { session in
            sessionStates[ObjectIdentifier(session)]?.playbackState
        }.map { $0 != .none } ?? false
        
        commandCenter.playCommand.isEnabled = hasActivePlayback || features.contains(.play)
        commandCenter.pauseCommand.isEnabled = hasActivePlayback || features.contains(.pause)
        commandCenter.stopCommand.isEnabled = features.contains(.stop)
        commandCenter.togglePlayPauseCommand.isEnabled = hasActivePlayback || features.contains(.play) || features.contains(.pause)
        commandCenter.nextTrackCommand.isEnabled = features.contains(.nextTrack)
        commandCenter.previousTrackCommand.isEnabled = features.contains(.prevTrack)
        commandCenter.skipForwardCommand.isEnabled = features.contains(.seekForward)
        commandCenter.skipBackwardCommand.isEnabled = features.contains(.seekBackward)
        commandCenter.seekForwardCommand.isEnabled = features.contains(.seekForward)
        commandCenter.seekBackwardCommand.isEnabled = features.contains(.seekBackward)
        commandCenter.changePlaybackPositionCommand.isEnabled = features.contains(.seekTo)
    }
    
    private func registerRemoteCommands() {
        var targets: [Any] = []
        targets.append(commandCenter.playCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.play()
            return .success
        })
        targets.append(commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.pause()
            return .success
        })
        targets.append(commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.stop()
            return .success
        })
        targets.append(commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self,
                  let session = activeSession,
                  let state = sessionStates[ObjectIdentifier(session)] else {
                return .commandFailed
            }
            
            switch state.playbackState {
            case .playing:
                session.mediaSession.pause()
            case .paused:
                session.mediaSession.play()
            case .none:
                return .commandFailed
            }
            return .success
        })
        targets.append(commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.nextTrack()
            return .success
        })
        targets.append(commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.previousTrack()
            return .success
        })
        targets.append(commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.seekForward()
            return .success
        })
        targets.append(commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.seekBackward()
            return .success
        })
        targets.append(commandCenter.seekForwardCommand.addTarget { [weak self] event in
            guard let seekEvent = event as? MPSeekCommandEvent else {
                return .commandFailed
            }
            guard seekEvent.type == .beginSeeking else {
                return .success
            }
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.seekForward()
            return .success
        })
        targets.append(commandCenter.seekBackwardCommand.addTarget { [weak self] event in
            guard let seekEvent = event as? MPSeekCommandEvent else {
                return .commandFailed
            }
            guard seekEvent.type == .beginSeeking else {
                return .success
            }
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.seekBackward()
            return .success
        })
        targets.append(commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSession.seekTo(time: positionEvent.positionTime)
            return .success
        })
        commandTargets = targets
    }
    
    private func unregisterRemoteCommands() {
        let commands: [MPRemoteCommand] = [
            commandCenter.playCommand,
            commandCenter.pauseCommand,
            commandCenter.stopCommand,
            commandCenter.togglePlayPauseCommand,
            commandCenter.nextTrackCommand,
            commandCenter.previousTrackCommand,
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.seekForwardCommand,
            commandCenter.seekBackwardCommand,
            commandCenter.changePlaybackPositionCommand,
        ]
        zip(commands, commandTargets).forEach { command, target in
            command.isEnabled = false
            command.removeTarget(target)
        }
        commandTargets.removeAll()
    }
}
