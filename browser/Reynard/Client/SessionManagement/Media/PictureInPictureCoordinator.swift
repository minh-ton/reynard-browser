//
//  PictureInPictureCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/7/26.
//

import AVFoundation
import AVKit
import Foundation
import GeckoView

protocol PictureInPictureCoordinating: AnyObject {
    func selectedSessionDidChange()
    func navigationStarted(in session: GeckoSession)
}

@available(iOS 15.0, *)
protocol PictureInPictureCoordinatorDelegate: AnyObject {
    func pictureInPictureCoordinator(
        _ coordinator: PictureInPictureCoordinator,
        restore session: GeckoSession
    ) -> Bool
}

@available(iOS 15.0, *)
final class PictureInPictureCoordinator: NSObject, PictureInPictureCoordinating {
    private struct EligibleSession {
        let session: GeckoSession
        let displayLayer: AVSampleBufferDisplayLayer
        let positionState: MediaSessionPositionState
        let supportsSeeking: Bool
    }
    
    private final class Presentation {
        let session: GeckoSession
        var displayLayer: AVSampleBufferDisplayLayer
        let controller: AVPictureInPictureController
        var wasStopRequested = false
        var pauseGeneration = 0
        
        init(
            session: GeckoSession,
            displayLayer: AVSampleBufferDisplayLayer,
            controller: AVPictureInPictureController
        ) {
            self.session = session
            self.displayLayer = displayLayer
            self.controller = controller
        }
    }
    
    private enum State {
        case idle
        case prepared(Presentation)
        case starting(Presentation)
        case active(Presentation)
        case stopping(Presentation)
        
        var presentation: Presentation? {
            switch self {
            case .idle:
                return nil
            case let .prepared(presentation),
                let .starting(presentation),
                let .active(presentation),
                let .stopping(presentation):
                return presentation
            }
        }
    }
    
    private weak var delegate: PictureInPictureCoordinatorDelegate?
    private let mediaSession: SystemMediaSession
    private let sessionManager: SessionManager
    private var state = State.idle
    private weak var observedSession: GeckoSession?
    private var isAwaitingAutomaticStart = false
    
    init?(
        delegate: PictureInPictureCoordinatorDelegate,
        mediaSession: SystemMediaSession,
        sessionManager: SessionManager
    ) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return nil
        }
        self.delegate = delegate
        self.mediaSession = mediaSession
        self.sessionManager = sessionManager
        super.init()
        mediaSession.observer = self
        sessionManager.applicationStateObserver = self
        sessionManager.pictureInPictureHandler = self
    }
    
    func selectedSessionDidChange() {
        if let presentation = state.presentation,
           mediaSession.selectedSnapshot?.session !== presentation.session {
            stopPresentation()
        }
        observeSelectedSession()
        updatePresentation()
    }
    
    func navigationStarted(in session: GeckoSession) {
        guard mediaSession.selectedSnapshot?.session === session ||
                state.presentation?.session === session else {
            return
        }
        stopPresentation()
    }
    
    private func observeSelectedSession() {
        let selectedSession = mediaSession.selectedSnapshot?.session
        guard observedSession !== selectedSession else {
            return
        }
        observedSession?.pictureInPictureDelegate = nil
        observedSession = selectedSession
        observedSession?.pictureInPictureDelegate = self
    }
    
    private func updatePresentation() {
        let isPresentationActive =
        state.presentation?.controller.isPictureInPictureActive == true
        guard !isAwaitingAutomaticStart,
              sessionManager.isForeground || isPresentationActive else {
            return
        }
        switch state {
        case .idle:
            guard let eligibleSession = eligibleSession() else {
                return
            }
            prepare(eligibleSession)
        case let .prepared(presentation):
            guard let snapshot = mediaSession.selectedSnapshot,
                  snapshot.session === presentation.session,
                  snapshot.playbackState == .playing,
                  let displayLayer =
                    presentation.session.pictureInPictureDisplayLayer else {
                stopPresentation()
                return
            }
            if displayLayer !== presentation.displayLayer {
                guard let positionState = snapshot.positionState,
                      isValid(positionState),
                      synchronizeTimebase(of: displayLayer, with: positionState) else {
                    stopPresentation()
                    return
                }
                presentation.displayLayer = displayLayer
                presentation.controller.contentSource =
                AVPictureInPictureController.ContentSource(
                    sampleBufferDisplayLayer: displayLayer,
                    playbackDelegate: self
                )
            }
            updatePlayback(of: presentation, with: snapshot)
        case let .starting(presentation), let .active(presentation):
            guard let snapshot = mediaSession.selectedSnapshot,
                  snapshot.session === presentation.session,
                  snapshot.playbackState != .none else {
                stopPresentation()
                return
            }
            updatePlayback(of: presentation, with: snapshot)
        case .stopping:
            break
        }
    }
    
    private func eligibleSession() -> EligibleSession? {
        guard let snapshot = mediaSession.selectedSnapshot,
              snapshot.playbackState == .playing,
              let displayLayer =
                snapshot.session.pictureInPictureDisplayLayer,
              let positionState = snapshot.positionState,
              isValid(positionState) else {
            return nil
        }
        return EligibleSession(
            session: snapshot.session,
            displayLayer: displayLayer,
            positionState: positionState,
            supportsSeeking: snapshot.supportsSeeking
        )
    }
    
    private func prepare(_ eligibleSession: EligibleSession) {
        guard synchronizeTimebase(
            of: eligibleSession.displayLayer,
            with: eligibleSession.positionState
        ),
              eligibleSession.session.pictureInPictureDisplayLayer ===
                eligibleSession.displayLayer else {
            return
        }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: eligibleSession.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.requiresLinearPlayback = !eligibleSession.supportsSeeking
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        state = .prepared(Presentation(
            session: eligibleSession.session,
            displayLayer: eligibleSession.displayLayer,
            controller: controller
        ))
    }
    
    private func updatePlayback(
        of presentation: Presentation,
        with snapshot: SystemMediaSession.Snapshot
    ) {
        if let positionState = snapshot.positionState, isValid(positionState) {
            _ = synchronizeTimebase(
                of: presentation.displayLayer,
                with: positionState,
                isPaused: snapshot.playbackState == .paused
            )
        }
        presentation.controller.requiresLinearPlayback =
        !snapshot.supportsSeeking
        presentation.controller.invalidatePlaybackState()
    }
    
    private func isValid(_ positionState: MediaSessionPositionState) -> Bool {
        return positionState.duration.isFinite &&
        positionState.duration > 0 &&
        positionState.position.isFinite &&
        positionState.position >= 0 &&
        positionState.position <= positionState.duration &&
        positionState.playbackRate.isFinite &&
        positionState.playbackRate > 0
    }
    
    private func synchronizeTimebase(
        of displayLayer: AVSampleBufferDisplayLayer,
        with positionState: MediaSessionPositionState,
        isPaused: Bool = false
    ) -> Bool {
        guard let timebase = displayLayer.controlTimebase else {
            return false
        }
        guard CMTimebaseSetTime(
            timebase,
            time: CMTime(seconds: positionState.position, preferredTimescale: 600)
        ) == noErr else {
            return false
        }
        return CMTimebaseSetRate(
            timebase,
            rate: isPaused ? 0 : positionState.playbackRate
        ) == noErr
    }
    
    private func stopPresentation() {
        isAwaitingAutomaticStart = false
        switch state {
        case .idle:
            break
        case let .prepared(presentation):
            finishPresentation(presentation)
        case let .starting(presentation), let .active(presentation):
            presentation.wasStopRequested = true
            state = .stopping(presentation)
            presentation.controller.stopPictureInPicture()
        case let .stopping(presentation):
            presentation.wasStopRequested = true
        }
    }
    
    private func finishPresentation(
        for controller: AVPictureInPictureController
    ) {
        guard let presentation = presentation(for: controller) else {
            return
        }
        if !sessionManager.isForeground {
            presentation.session.mediaSession.pause()
        }
        finishPresentation(presentation)
        DispatchQueue.main.async { [weak self] in
            self?.updatePresentation()
        }
    }
    
    private func finishPresentation(_ presentation: Presentation) {
        presentation.controller.delegate = nil
        state = .idle
        sessionManager.pictureInPicturePresentationDidEnd(
            presentation.session
        )
    }
    
    private func presentation(
        for controller: AVPictureInPictureController
    ) -> Presentation? {
        guard let presentation = state.presentation,
              presentation.controller === controller else {
            return nil
        }
        return presentation
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator: SystemMediaSessionObserver {
    func systemMediaSessionStateDidChange(_ mediaSession: SystemMediaSession) {
        observeSelectedSession()
        updatePresentation()
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator: SessionManagerApplicationStateObserver {
    func sessionManagerDidChangeApplicationState(
        _ sessionManager: SessionManager
    ) {
        guard sessionManager.isForeground else {
            return
        }
        if isAwaitingAutomaticStart {
            isAwaitingAutomaticStart = false
            if let presentation = state.presentation {
                sessionManager.pictureInPicturePresentationDidEnd(
                    presentation.session
                )
            }
        }
        updatePresentation()
    }
    
    func sessionManagerWillResignActive(_ sessionManager: SessionManager) {
        updatePresentation()
        guard case let .prepared(presentation) = state,
              presentation.controller.isPictureInPicturePossible else {
            return
        }
        isAwaitingAutomaticStart = true
        sessionManager.setPictureInPictureSession(presentation.session)
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator: SessionManagerPictureInPictureHandler {
    func stopPresenting(_ session: GeckoSession) -> Bool {
        guard state.presentation?.session === session else {
            return false
        }
        stopPresentation()
        return true
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator: PictureInPictureDelegate {
    func onSourceChanged(session: GeckoSession) {
        guard observedSession === session else {
            return
        }
        updatePresentation()
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator:
    AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying isPlaying: Bool
    ) {
        guard let presentation = presentation(
            for: pictureInPictureController
        ) else {
            return
        }
        presentation.pauseGeneration += 1
        if isPlaying {
            presentation.session.mediaSession.play()
        } else {
            let pauseGeneration = presentation.pauseGeneration
            DispatchQueue.main.async { [weak presentation] in
                guard let presentation,
                      presentation.pauseGeneration == pauseGeneration else {
                    return
                }
                presentation.session.mediaSession.pause()
            }
        }
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        guard let presentation = presentation(
            for: pictureInPictureController
        ),
              let snapshot = mediaSession.selectedSnapshot,
              snapshot.session === presentation.session,
              let positionState = snapshot.positionState,
              positionState.duration.isFinite,
              positionState.duration > 0 else {
            return .invalid
        }
        return CMTimeRange(
            start: .zero,
            duration: CMTime(
                seconds: positionState.duration,
                preferredTimescale: 600
            )
        )
    }
    
    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        guard let presentation = presentation(
            for: pictureInPictureController
        ),
              let snapshot = mediaSession.selectedSnapshot,
              snapshot.session === presentation.session else {
            return true
        }
        return snapshot.playbackState != .playing
    }
    
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}
    
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        guard let presentation = presentation(
            for: pictureInPictureController
        ),
              let snapshot = mediaSession.selectedSnapshot,
              snapshot.session === presentation.session,
              snapshot.supportsSeeking,
              let positionState = snapshot.positionState,
              positionState.duration.isFinite,
              positionState.duration > 0,
              let timebase = presentation.displayLayer.controlTimebase else {
            completionHandler()
            return
        }
        let skipSeconds = CMTimeGetSeconds(skipInterval)
        let currentSeconds = CMTimeGetSeconds(CMTimebaseGetTime(timebase))
        guard skipSeconds.isFinite, currentSeconds.isFinite else {
            completionHandler()
            return
        }
        presentation.pauseGeneration += 1
        let targetSeconds = min(
            max(currentSeconds + skipSeconds, 0), positionState.duration
        )
        if snapshot.features.contains(.seekTo) {
            presentation.session.mediaSession.seekTo(time: targetSeconds)
        } else if skipSeconds > 0 {
            presentation.session.mediaSession.seekForward(offset: skipSeconds)
        } else if skipSeconds < 0 {
            presentation.session.mediaSession.seekBackward(offset: -skipSeconds)
        }
        let playbackRate = snapshot.playbackState == .playing ?
        positionState.playbackRate : 0
        _ = CMTimebaseSetTime(
            timebase,
            time: CMTime(seconds: targetSeconds, preferredTimescale: 600)
        )
        _ = CMTimebaseSetRate(timebase, rate: playbackRate)
        completionHandler()
        presentation.pauseGeneration += 1
    }
}

@available(iOS 15.0, *)
extension PictureInPictureCoordinator: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard case let .prepared(presentation) = state,
              presentation.controller === pictureInPictureController else {
            return
        }
        isAwaitingAutomaticStart = false
        state = .starting(presentation)
        sessionManager.setPictureInPictureSession(presentation.session)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard case let .starting(presentation) = state,
              presentation.controller === pictureInPictureController else {
            return
        }
        state = .active(presentation)
    }
    
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        NSLog("Failed to start Picture in Picture: \(error)")
        finishPresentation(for: pictureInPictureController)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard let presentation = presentation(
            for: pictureInPictureController
        ) else {
            return
        }
        state = .stopping(presentation)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        finishPresentation(for: pictureInPictureController)
    }
    
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let presentation = presentation(
            for: pictureInPictureController
        ),
              !presentation.wasStopRequested else {
            completionHandler(false)
            return
        }
        completionHandler(
            delegate?.pictureInPictureCoordinator(
                self,
                restore: presentation.session
            ) == true
        )
    }
}
