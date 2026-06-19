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
    private weak var activeSession: GeckoSession?
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var artworkTask: URLSessionDataTask?
    private var commandTargets: [Any] = []
    
    init() {
        registerRemoteCommands()
    }
    
    deinit {
        unregisterRemoteCommands()
    }
    
    func onActivated(session: GeckoSession) {
        activeSession = session
    }
    
    func onDeactivated(session: GeckoSession) {
        guard activeSession === session else { return }
        activeSession = nil
        nowPlayingCenter.nowPlayingInfo = nil
        artworkTask?.cancel()
        artworkTask = nil
    }
    
    func onMetadata(session: GeckoSession, metadata: MediaSessionMetadata) {
        guard activeSession === session else { return }
        var info = nowPlayingCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle]  = metadata.title  ?? ""
        info[MPMediaItemPropertyArtist] = metadata.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = metadata.album ?? ""
        nowPlayingCenter.nowPlayingInfo = info
        
        artworkTask?.cancel()
        artworkTask = nil
        
        if let artworkURLString = metadata.artworkUrl,
           let artworkURL = URL(string: artworkURLString) {
            let task = URLSession.shared.dataTask(with: artworkURL) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    guard self.activeSession === session else { return }
                    var updated = self.nowPlayingCenter.nowPlayingInfo ?? [:]
                    updated[MPMediaItemPropertyArtwork] = artwork
                    self.nowPlayingCenter.nowPlayingInfo = updated
                }
            }
            task.resume()
            artworkTask = task
        }
    }
    
    func onPlaybackPlaying(session: GeckoSession) {
        guard activeSession === session else { return }
        var info = nowPlayingCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        nowPlayingCenter.nowPlayingInfo = info
    }
    
    func onPlaybackPaused(session: GeckoSession) {
        guard activeSession === session else { return }
        var info = nowPlayingCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        nowPlayingCenter.nowPlayingInfo = info
    }
    
    func onPlaybackNone(session: GeckoSession) {
        guard activeSession === session else { return }
        nowPlayingCenter.nowPlayingInfo = nil
    }
    
    func onPositionState(session: GeckoSession, state: MediaSessionPositionState) {
        guard activeSession === session else { return }
        var info = nowPlayingCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyPlaybackDuration] = state.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = state.playbackRate
        nowPlayingCenter.nowPlayingInfo = info
    }
    
    func onFeatures(session: GeckoSession, features: MediaSessionFeatures) {
        guard activeSession === session else { return }
        commandCenter.nextTrackCommand.isEnabled     = features.contains(.nextTrack)
        commandCenter.previousTrackCommand.isEnabled = features.contains(.prevTrack)
        commandCenter.skipForwardCommand.isEnabled   = features.contains(.seekForward)
        commandCenter.skipBackwardCommand.isEnabled  = features.contains(.seekBackward)
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
            commandCenter.nextTrackCommand,
            commandCenter.previousTrackCommand,
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.changePlaybackPositionCommand,
        ]
        zip(commands, commandTargets).forEach { command, target in
            command.removeTarget(target)
        }
        commandTargets.removeAll()
    }
}
