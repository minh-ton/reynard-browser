//
//  WebContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class WebContentView: UIView {
    fileprivate enum UX {
        static let minimumPullDistance: CGFloat = 8
        static let refreshThreshold: CGFloat = 350
        static let landscapePhoneRefreshThreshold: CGFloat = 100
        static let quickScaleMaximumInterval: TimeInterval = 0.3
        static let quickScaleSpatialTolerance: CGFloat = 44
        static let refreshingContentOffset: CGFloat = 64
        static let rubberBandCoefficient: CGFloat = 0.55
        static let returnAnimationDuration: TimeInterval = 0.45
        static let returnSpringDamping: CGFloat = 0.9
    }
    
    enum VisibilityState: Equatable {
        case visible
        case hidden
    }
    
    private(set) var visibility: VisibilityState = .visible
    private var refreshingSession: GeckoSession?
    private var isTrackingPullProgress = false
    private var pullToRefreshRecognizer: PullToRefreshGestureRecognizer?
    
    private let webView = GeckoView()
    private let refreshIndicatorContainer = UIView()
    private let refreshIndicator = UIActivityIndicatorView(style: .large)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureConstraints()
        applyVisibility()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        webView.inputResultDelegate = nil
    }
    
    private func configureHierarchy() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicator.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicator.hidesWhenStopped = false
        refreshIndicatorContainer.addSubview(refreshIndicator)
        addSubview(refreshIndicatorContainer)
        addSubview(webView)
        resetRefreshIndicator()
        refreshIndicatorContainer.alpha = 0
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            refreshIndicatorContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            refreshIndicatorContainer.topAnchor.constraint(
                equalTo: topAnchor,
                constant: (UX.refreshingContentOffset - refreshIndicator.intrinsicContentSize.height) / 2
            ),
            refreshIndicator.topAnchor.constraint(equalTo: refreshIndicatorContainer.topAnchor),
            refreshIndicator.leadingAnchor.constraint(equalTo: refreshIndicatorContainer.leadingAnchor),
            refreshIndicator.trailingAnchor.constraint(equalTo: refreshIndicatorContainer.trailingAnchor),
            refreshIndicator.bottomAnchor.constraint(equalTo: refreshIndicatorContainer.bottomAnchor),
        ])
    }
    
    func setVisibility(_ visibility: VisibilityState) {
        guard self.visibility != visibility else {
            return
        }
        
        self.visibility = visibility
        applyVisibility()
    }
    
    private func applyVisibility() {
        isHidden = visibility == .hidden
    }
    
    func setSession(_ session: GeckoSession?) {
        guard webView.session !== session else {
            return
        }
        refreshingSession = nil
        pullToRefreshRecognizer?.cancelPull()
        webView.session = session
    }
    
    func setPullToRefreshEnabled(_ enabled: Bool) {
        guard enabled != (pullToRefreshRecognizer != nil) else {
            return
        }
        if enabled {
            installPullToRefreshRecognizer()
            webView.inputResultDelegate = self
        } else if let pullToRefreshRecognizer {
            webView.inputResultDelegate = nil
            refreshingSession = nil
            pullToRefreshRecognizer.cancelPull()
            webView.removeGestureRecognizer(pullToRefreshRecognizer)
            self.pullToRefreshRecognizer = nil
        }
    }
    
    func didFinishLoading(session: GeckoSession) {
        guard session === refreshingSession else {
            return
        }
        refreshingSession = nil
        pullToRefreshRecognizer?.completeRefresh()
        cancelRefreshPresentation()
    }
    
    func isDisplaying(session: GeckoSession) -> Bool {
        webView.session === session
    }
    
    func restoreInteraction(for session: GeckoSession) {
        webView.session = session
    }
    
    func addWebViewInteraction(_ interaction: UIInteraction) {
        webView.addInteraction(interaction)
    }
    
    func makeThumbnail() -> UIImage? {
        layoutIfNeeded()
        guard bounds.width > 1, bounds.height > 1 else {
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
    
    private func installPullToRefreshRecognizer() {
        let recognizer = PullToRefreshGestureRecognizer(
            target: self,
            action: #selector(handlePullToRefresh(_:))
        )
        recognizer.delaysTouchesEnded = false
        pullToRefreshRecognizer = recognizer
        webView.addGestureRecognizer(recognizer)
    }
    
    @objc private func handlePullToRefresh(_ recognizer: PullToRefreshGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            updatePullPresentation(
                progress: recognizer.progress,
                pullDistance: recognizer.pullDistance
            )
        case .ended where recognizer.progress >= 1:
            guard refreshingSession == nil,
                  let session = webView.session else {
                return
            }
            refreshingSession = session
            beginRefreshingPresentation()
            session.reload()
        case .ended, .cancelled, .failed:
            guard refreshingSession == nil else {
                return
            }
            cancelRefreshPresentation()
        default:
            break
        }
    }
    
    private func updatePullPresentation(progress: CGFloat, pullDistance: CGFloat) {
        let viewportHeight = max(bounds.height, 1)
        let rubberBandDistance = UX.rubberBandCoefficient * pullDistance
        let contentOffset = rubberBandDistance * viewportHeight / (viewportHeight + rubberBandDistance)
        setRefreshIndicatorProgress(contentOffset / UX.refreshingContentOffset)
        refreshIndicatorContainer.alpha = progress
        webView.transform = CGAffineTransform(translationX: 0, y: contentOffset)
    }
    
    private func beginRefreshingPresentation() {
        startRefreshIndicatorAnimation()
        UIView.animate(
            withDuration: UX.returnAnimationDuration,
            delay: 0,
            usingSpringWithDamping: UX.returnSpringDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.refreshIndicatorContainer.alpha = 1
            self.webView.transform = CGAffineTransform(
                translationX: 0,
                y: UX.refreshingContentOffset
            )
        }
    }
    
    private func cancelRefreshPresentation() {
        UIView.animate(
            withDuration: UX.returnAnimationDuration,
            delay: 0,
            usingSpringWithDamping: UX.returnSpringDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.refreshIndicatorContainer.alpha = 0
            self.webView.transform = .identity
        } completion: { _ in
            if self.refreshingSession == nil {
                self.resetRefreshIndicator()
            }
        }
    }
    
    private func setRefreshIndicatorProgress(_ progress: CFTimeInterval) {
        if !isTrackingPullProgress {
            refreshIndicator.layer.speed = 0
            refreshIndicator.layer.timeOffset = 0
            refreshIndicator.layer.beginTime = 0
            refreshIndicator.startAnimating()
            isTrackingPullProgress = true
        }
        refreshIndicator.layer.timeOffset = progress
    }
    
    private func startRefreshIndicatorAnimation() {
        guard isTrackingPullProgress else {
            refreshIndicator.startAnimating()
            return
        }
        let pausedTime = refreshIndicator.layer.timeOffset
        refreshIndicator.layer.speed = 1
        refreshIndicator.layer.timeOffset = 0
        refreshIndicator.layer.beginTime = 0
        refreshIndicator.layer.beginTime = refreshIndicator.layer.convertTime(
            CACurrentMediaTime(),
            from: nil
        ) - pausedTime
        isTrackingPullProgress = false
    }
    
    private func resetRefreshIndicator() {
        refreshIndicator.stopAnimating()
        refreshIndicator.layer.speed = 1
        refreshIndicator.layer.timeOffset = 0
        refreshIndicator.layer.beginTime = 0
        isTrackingPullProgress = false
    }
}

extension WebContentView: GeckoViewInputResultDelegate {
    func touchSequenceDidBegin(_ sequenceID: UInt64) {
        pullToRefreshRecognizer?.beginInputSequence(sequenceID)
    }
    
    func touchSequence(
        _ sequenceID: UInt64,
        didResolve inputHandling: GeckoInputHandling,
        scrollableEdges: GeckoScrollableEdges,
        overscrollAxes: GeckoOverscrollAxes
    ) {
        pullToRefreshRecognizer?.resolveInputSequence(PullInputResult(
            sequenceID: sequenceID,
            inputHandling: inputHandling,
            scrollableEdges: scrollableEdges,
            overscrollAxes: overscrollAxes
        ))
    }
    
    func touchSequenceDidEnd(_ sequenceID: UInt64) {}
}

private struct PullInputResult {
    let sequenceID: UInt64
    let inputHandling: GeckoInputHandling
    let scrollableEdges: GeckoScrollableEdges
    let overscrollAxes: GeckoOverscrollAxes
    
    var canOverscrollTop: Bool {
        return inputHandling.rawValue != GeckoInputHandling.content.rawValue &&
        scrollableEdges.rawValue & GeckoScrollableEdges.top.rawValue == 0 &&
        overscrollAxes.rawValue & GeckoOverscrollAxes.axisVertical.rawValue != 0
    }
}

private final class PullToRefreshGestureRecognizer: UIGestureRecognizer {
    private var touchOrigin = CGPoint.zero
    private var touchPosition = CGPoint.zero
    private var activeInputSequenceID: UInt64?
    private var isPullApproved = false
    private var previousTap: (position: CGPoint, endTimestamp: TimeInterval)?
    private var hasTriggeredThresholdFeedback = false
    private var isAwaitingRefreshCompletion = false
    var pullDistance: CGFloat {
        return touchPosition.y - touchOrigin.y
    }
    var progress: CGFloat {
        let isLandscapePhone = view?.traitCollection.userInterfaceIdiom == .phone &&
        (view?.bounds.width ?? 0) > (view?.bounds.height ?? 0)
        let refreshThreshold = isLandscapePhone
        ? WebContentView.UX.landscapePhoneRefreshThreshold
        : WebContentView.UX.refreshThreshold
        return min(pullDistance / refreshThreshold, 1)
    }
    private var isRecognizing: Bool {
        return state == .began || state == .changed
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !isAwaitingRefreshCompletion,
              let touch = validSingleTouch(in: touches, event: event) else {
            return
        }
        
        touchOrigin = touch.location(in: view?.superview)
        touchPosition = touchOrigin
        activeInputSequenceID = nil
        isPullApproved = false
        hasTriggeredThresholdFeedback = false
        
        if let previousTap {
            let interval = touch.timestamp - previousTap.endTimestamp
            let distance = hypot(
                touchOrigin.x - previousTap.position.x,
                touchOrigin.y - previousTap.position.y
            )
            if interval > WebContentView.UX.quickScaleMaximumInterval ||
                distance > WebContentView.UX.quickScaleSpatialTolerance {
                self.previousTap = nil
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = validSingleTouch(in: touches, event: event) else {
            return
        }
        
        touchPosition = touch.location(in: view?.superview)
        updatePullRecognition()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else {
            rejectPull()
            return
        }
        
        touchPosition = touch.location(in: view?.superview)
        if isRecognizing {
            isAwaitingRefreshCompletion = progress >= 1
            state = .ended
        } else {
            state = .failed
        }
        
        if previousTap != nil {
            previousTap = nil
        } else if hypot(
            touchPosition.x - touchOrigin.x,
            touchPosition.y - touchOrigin.y
        ) < WebContentView.UX.minimumPullDistance {
            previousTap = (touchOrigin, touch.timestamp)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        previousTap = nil
        if isRecognizing {
            state = .cancelled
        } else {
            state = .failed
        }
    }
    
    func beginInputSequence(_ sequenceID: UInt64) {
        activeInputSequenceID = sequenceID
    }
    
    func resolveInputSequence(_ result: PullInputResult) {
        guard state == .possible,
              result.sequenceID == activeInputSequenceID else {
            return
        }
        guard result.canOverscrollTop else {
            rejectPull()
            return
        }
        isPullApproved = true
        updatePullRecognition()
    }
    
    func completeRefresh() {
        isAwaitingRefreshCompletion = false
    }
    
    func cancelPull() {
        previousTap = nil
        activeInputSequenceID = nil
        isPullApproved = false
        isAwaitingRefreshCompletion = false
        if isRecognizing {
            state = .cancelled
        } else if state == .possible {
            state = .failed
        }
    }
    
    private func updatePullRecognition() {
        guard state == .possible || state == .began || state == .changed else {
            return
        }
        
        let horizontalDistance = touchPosition.x - touchOrigin.x
        let verticalDistance = touchPosition.y - touchOrigin.y
        if verticalDistance < 0 || abs(horizontalDistance) > abs(verticalDistance) {
            rejectPull()
            return
        }
        if previousTap != nil &&
            hypot(horizontalDistance, verticalDistance) >= WebContentView.UX.minimumPullDistance {
            previousTap = nil
            rejectPull()
            return
        }
        guard isPullApproved,
              verticalDistance >= WebContentView.UX.minimumPullDistance else {
            return
        }
        
        updateThresholdFeedback()
        state = state == .possible ? .began : .changed
    }
    
    private func updateThresholdFeedback() {
        if progress >= 1 && !hasTriggeredThresholdFeedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hasTriggeredThresholdFeedback = true
        } else if progress < 1 {
            hasTriggeredThresholdFeedback = false
        }
    }
    
    private func validSingleTouch(in touches: Set<UITouch>, event: UIEvent) -> UITouch? {
        guard touches.count == 1,
              event.allTouches?.count == 1 else {
            previousTap = nil
            rejectPull()
            return nil
        }
        return touches.first
    }
    
    private func rejectPull() {
        if state == .possible {
            state = .failed
        }
    }
}
