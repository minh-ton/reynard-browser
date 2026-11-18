//
//  WebContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class WebContentView: UIView, UIScrollViewDelegate {
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
        static let scrollToTopTriggerOffset: CGFloat = 1
    }
    
    enum VisibilityState: Equatable {
        case visible
        case hidden
    }
    
    private(set) var visibility: VisibilityState = .visible
    private var refreshingSession: GeckoSession?
    private var isTrackingPullProgress = false
    private var pullToRefreshRecognizer: PullToRefreshGestureRecognizer?
    private var lastScrollState: (position: CGFloat, zoomScale: CGFloat)?
    private var currentScrollY: CGFloat = 0
    private var awaitsScrollInteraction = true
    private var pageBackgroundTopConstraint: NSLayoutConstraint?
    private var pageBackgroundBottomConstraint: NSLayoutConstraint?
    
    private let contentContainerView = UIView()
    private let webView = GeckoView()
    private let pageBackgroundView = UIView()
    private let errorView = WebContentErrorView()
    private let scrollToTopTriggerView = UIScrollView() // For scrolling up when tap the iOS status bar
    private let refreshIndicatorContainer = UIView()
    private let refreshIndicator = UIActivityIndicatorView(style: .large)
    
    var historySwipeDirectionsProvider: (() -> GeckoEdgeSwipeDirections)?
    var onHistorySwipeDidStart: ((GeckoEdgeSwipeDirections) -> Void)?
    var onHistorySwipeDidUpdate: ((CGFloat) -> Void)?
    var onHistorySwipeDidComplete: ((GeckoEdgeSwipeDirections) -> Void)?
    var onHistorySwipeDidEnd: (() -> Void)?
    var onVerticalScroll: ((CGFloat, CGFloat) -> Void)?
    
    var keyCommandDelegate: GeckoViewKeyCommandDelegate? {
        get { return webView.keyCommandDelegate }
        set { webView.keyCommandDelegate = newValue }
    }
    
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
        webView.interactionDelegate = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollToTopTriggerView.contentSize = CGSize(
            width: bounds.width,
            height: bounds.height + UX.scrollToTopTriggerOffset
        )
        scrollToTopTriggerView.contentOffset.y = UX.scrollToTopTriggerOffset
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }
        updateRefreshIndicatorTint()
    }
    
    private func configureHierarchy() {
        contentContainerView.backgroundColor = .systemBackground
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        pageBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        errorView.translatesAutoresizingMaskIntoConstraints = false
        scrollToTopTriggerView.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicator.translatesAutoresizingMaskIntoConstraints = false
        scrollToTopTriggerView.delegate = self
        scrollToTopTriggerView.showsVerticalScrollIndicator = false
        scrollToTopTriggerView.contentInsetAdjustmentBehavior = .never
        webView.interactionDelegate = self
        pageBackgroundView.backgroundColor = .systemBackground
        updateRefreshIndicatorTint()
        errorView.isHidden = true
        refreshIndicator.hidesWhenStopped = false
        refreshIndicatorContainer.addSubview(refreshIndicator)
        addSubview(contentContainerView)
        contentContainerView.addSubview(scrollToTopTriggerView)
        contentContainerView.addSubview(pageBackgroundView)
        contentContainerView.addSubview(webView)
        contentContainerView.addSubview(refreshIndicatorContainer)
        contentContainerView.addSubview(errorView)
        resetRefreshIndicator()
        refreshIndicatorContainer.alpha = 0
    }
    
    private func configureConstraints() {
        let topConstraint = pageBackgroundView.topAnchor.constraint(equalTo: topAnchor)
        let bottomConstraint = pageBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([topConstraint, bottomConstraint])
        pageBackgroundTopConstraint = topConstraint
        pageBackgroundBottomConstraint = bottomConstraint
        
        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: pageBackgroundView.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: pageBackgroundView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            scrollToTopTriggerView.topAnchor.constraint(equalTo: topAnchor),
            scrollToTopTriggerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollToTopTriggerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollToTopTriggerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            pageBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            errorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            refreshIndicatorContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            refreshIndicator.topAnchor.constraint(equalTo: refreshIndicatorContainer.topAnchor),
            refreshIndicator.leadingAnchor.constraint(equalTo: refreshIndicatorContainer.leadingAnchor),
            refreshIndicator.trailingAnchor.constraint(equalTo: refreshIndicatorContainer.trailingAnchor),
            refreshIndicator.bottomAnchor.constraint(equalTo: refreshIndicatorContainer.bottomAnchor),
        ])
    }
    
    func positionRefreshIndicator(below topAnchor: NSLayoutYAxisAnchor) {
        refreshIndicatorContainer.topAnchor.constraint(
            equalTo: topAnchor,
            constant: (UX.refreshingContentOffset - refreshIndicator.intrinsicContentSize.height) / 2
        ).isActive = true
    }
    
    func extendPageBackground(
        from topAnchor: NSLayoutYAxisAnchor,
        to bottomAnchor: NSLayoutYAxisAnchor
    ) {
        pageBackgroundTopConstraint?.isActive = false
        pageBackgroundBottomConstraint?.isActive = false
        let topConstraint = pageBackgroundView.topAnchor.constraint(equalTo: topAnchor)
        let bottomConstraint = pageBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([topConstraint, bottomConstraint])
        pageBackgroundTopConstraint = topConstraint
        pageBackgroundBottomConstraint = bottomConstraint
    }
    
    func setFullscreen(_ fullscreen: Bool) {
        pageBackgroundView.isHidden = fullscreen
        contentContainerView.backgroundColor = fullscreen ? .black : .systemBackground
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
        scrollToTopTriggerView.scrollsToTop = visibility == .visible && errorView.isHidden
    }
    
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        webView.session?.scrollTo(.zero)
        return false
    }
    
    func setTab(_ tab: Tab?, pageBackgroundColor: UIColor? = nil) {
        updateLoadError(for: tab)
        pageBackgroundView.backgroundColor = pageBackgroundColor ?? .systemBackground
        updateRefreshIndicatorTint()
        
        guard webView.session !== tab?.session else {
            return
        }
        resetScrollTracking()
        currentScrollY = 0
        refreshingSession = nil
        pullToRefreshRecognizer?.cancelPull()
        cancelRefreshPresentation()
        webView.session = tab?.session
    }
    
    func setPageBackgroundColor(_ color: UIColor) {
        pageBackgroundView.backgroundColor = color
        updateRefreshIndicatorTint()
    }
    
    func resetScrollTracking() {
        lastScrollState = nil
        awaitsScrollInteraction = true
    }
    
    func setPullToRefreshEnabled(_ enabled: Bool) {
        let enabled = enabled && errorView.isHidden
        guard enabled != (pullToRefreshRecognizer != nil) else {
            return
        }
        if enabled {
            installPullToRefreshRecognizer()
        } else if let pullToRefreshRecognizer {
            refreshingSession = nil
            pullToRefreshRecognizer.cancelPull()
            cancelRefreshPresentation()
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
    
    func thumbnailFrame(in view: UIView) -> CGRect {
        layoutIfNeeded()
        return convert(thumbnailBounds, to: view)
    }
    
    func makeThumbnail() -> UIImage? {
        layoutIfNeeded()
        let captureBounds = contentContainerView.bounds
        guard captureBounds.width > 1, captureBounds.height > 1 else {
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(size: captureBounds.size)
        return renderer.image { _ in
            contentContainerView.drawHierarchy(in: captureBounds, afterScreenUpdates: false)
        }
    }
    
    private var thumbnailBounds: CGRect {
        return convert(contentContainerView.bounds, from: contentContainerView)
    }
    
    var onErrorAction: ((WebContentErrorView.Action) -> Void)? {
        get { return errorView.onAction }
        set { errorView.onAction = newValue }
    }
    
    func positionErrorView(
        from topAnchor: NSLayoutYAxisAnchor,
        to bottomAnchor: NSLayoutYAxisAnchor,
        viewport: UIView
    ) {
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: topAnchor),
            errorView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        errorView.configureContentLayout(
            topAnchor: viewport.topAnchor,
            bottomAnchor: viewport.bottomAnchor
        )
    }
    
    func updateLoadError(for tab: Tab?) {
        errorView.configure(
            error: tab?.state.loadError,
            canGoBack: tab?.state.navigationState.canGoBack == true
        )
        webView.accessibilityElementsHidden = !errorView.isHidden
        applyVisibility()
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
            updatePullPresentation(pullDistance: recognizer.pullDistance)
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
    
    private func updatePullPresentation(pullDistance: CGFloat) {
        let viewportHeight = max(bounds.height, 1)
        let rubberBandDistance = UX.rubberBandCoefficient * pullDistance
        let contentOffset = rubberBandDistance * viewportHeight / (viewportHeight + rubberBandDistance)
        let indicatorHeight = refreshIndicator.intrinsicContentSize.height
        let opacity = (contentOffset - indicatorHeight) / (UX.refreshingContentOffset - indicatorHeight)
        setRefreshIndicatorProgress(contentOffset / UX.refreshingContentOffset)
        refreshIndicatorContainer.alpha = min(max(opacity, 0), 1)
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
        refreshIndicator.layer.timeOffset = progress * 0.3 // much better to look at
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
    
    private func updateRefreshIndicatorTint() {
        guard let pageBackgroundColor = pageBackgroundView.backgroundColor else {
            return
        }
        refreshIndicator.color = pageBackgroundColor.isLightColor(in: traitCollection) ? .black : .white
    }
}

extension WebContentView: GeckoViewInteractionDelegate {
    func touchSequenceDidBegin(_ sequenceID: UInt64) {
        pullToRefreshRecognizer?.beginInputSequence(sequenceID)
    }
    
    func touchSequence(
        _ sequenceID: UInt64,
        didResolve inputHandling: GeckoInputHandling,
        scrollableEdges: GeckoScrollableEdges,
        overscrollAxes: GeckoOverscrollAxes
    ) {
        awaitsScrollInteraction = false
        pullToRefreshRecognizer?.resolveInputSequence(PullInputResult(
            sequenceID: sequenceID,
            inputHandling: inputHandling,
            scrollableEdges: scrollableEdges,
            overscrollAxes: overscrollAxes
        ))
    }
    
    func touchSequenceDidEnd(_ sequenceID: UInt64) {}
    
    func trackpadScrollDidBegin(_ delta: CGPoint) {
        awaitsScrollInteraction = false
        guard currentScrollY <= 0.5 else {
            return
        }
        pullToRefreshRecognizer?.beginTrackpadScroll(delta)
    }
    
    func trackpadScrollDidUpdate(_ delta: CGPoint) {
        pullToRefreshRecognizer?.updateTrackpadScroll(delta)
    }
    
    func trackpadScrollDidEnd() {
        pullToRefreshRecognizer?.endTrackpadScroll()
    }
    
    func trackpadScrollDidCancel() {
        pullToRefreshRecognizer?.cancelTrackpadScroll()
    }
    
    func compositorScrollPositionDidChange(_ scrollY: Double, zoom: Double) {
        currentScrollY = CGFloat(scrollY)
        let currentState = (position: CGFloat(scrollY), zoomScale: CGFloat(zoom))
        defer {
            lastScrollState = currentState
        }
        guard !awaitsScrollInteraction,
              let previousState = lastScrollState,
              currentState.zoomScale == previousState.zoomScale || currentState.zoomScale == 1 else {
            return
        }
        let scrollDelta = currentState.position - previousState.position
        if scrollDelta != 0 {
            onVerticalScroll?(scrollDelta, currentState.position)
        }
    }
    
    func allowedEdgeSwipeDirections() -> GeckoEdgeSwipeDirections {
        return historySwipeDirectionsProvider?() ?? []
    }
    
    func edgeSwipeDidStart(_ direction: GeckoEdgeSwipeDirections) {
        onHistorySwipeDidStart?(direction)
    }
    
    func edgeSwipeDidUpdate(_ progress: Double) {
        onHistorySwipeDidUpdate?(CGFloat(progress))
    }
    
    func edgeSwipeDidComplete(_ direction: GeckoEdgeSwipeDirections) {
        onHistorySwipeDidComplete?(direction)
    }
    
    func edgeSwipeDidEnd() {
        onHistorySwipeDidEnd?()
    }
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
    private var isTrackingTrackpadScroll = false
    var pullDistance: CGFloat {
        return touchPosition.y - touchOrigin.y
    }
    var progress: CGFloat {
        // Short pull distance only when vertical space is constrained.
        let isLandscapePhone = view?.traitCollection.verticalSizeClass == .compact
        let refreshThreshold = isLandscapePhone
        ? WebContentView.UX.landscapePhoneRefreshThreshold
        : WebContentView.UX.refreshThreshold
        return min(pullDistance / refreshThreshold, 1)
    }
    private var isRecognizing: Bool {
        return state == .began || state == .changed
    }
    
    override func reset() {
        super.reset()
        activeInputSequenceID = nil
        isPullApproved = false
        isTrackingTrackpadScroll = false
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !isAwaitingRefreshCompletion else {
            state = .failed
            return
        }
        
        guard let touch = validSingleTouch(in: touches, event: event) else {
            return
        }
        
        touchOrigin = touch.location(in: view?.superview)
        touchPosition = touchOrigin
        activeInputSequenceID = nil
        isPullApproved = false
        hasTriggeredThresholdFeedback = false
        isTrackingTrackpadScroll = false
        
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
        guard !isAwaitingRefreshCompletion,
              state == .possible,
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
    
    func beginTrackpadScroll(_ delta: CGPoint) {
        guard !isAwaitingRefreshCompletion, state == .possible else {
            return
        }
        touchOrigin = .zero
        touchPosition = delta
        activeInputSequenceID = nil
        isPullApproved = true
        previousTap = nil
        hasTriggeredThresholdFeedback = false
        isTrackingTrackpadScroll = true
        updatePullRecognition()
    }
    
    func updateTrackpadScroll(_ delta: CGPoint) {
        guard isTrackingTrackpadScroll else {
            return
        }
        touchPosition.x += delta.x
        touchPosition.y += delta.y
        updatePullRecognition()
    }
    
    func endTrackpadScroll() {
        guard isTrackingTrackpadScroll else {
            return
        }
        isTrackingTrackpadScroll = false
        if isRecognizing {
            isAwaitingRefreshCompletion = progress >= 1
            state = .ended
        } else {
            state = .failed
        }
    }
    
    func cancelTrackpadScroll() {
        guard isTrackingTrackpadScroll else {
            return
        }
        isTrackingTrackpadScroll = false
        if isRecognizing {
            state = .cancelled
        } else {
            state = .failed
        }
    }
    
    func completeRefresh() {
        isAwaitingRefreshCompletion = false
    }
    
    func cancelPull() {
        previousTap = nil
        activeInputSequenceID = nil
        isPullApproved = false
        isAwaitingRefreshCompletion = false
        isTrackingTrackpadScroll = false
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
