//
//  ContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class ContentView: UIView, UIGestureRecognizerDelegate {
    struct ThumbnailGeometry {
        let fullFrame: CGRect
        let cropRect: CGRect
    }
    
    struct ThumbnailCaptureGeometry {
        let size: CGSize
        let visibleRect: CGRect
    }
    
    private enum UX {
        static let phoneSearchFocusedBottomInset: CGFloat = 94
        static let focusedInputBottomClearance: CGFloat = 12
        static let focusedInputOffsetThreshold: CGFloat = 0.5
        static let historyPreviewParallaxRatio: CGFloat = 0.33
        static let historyTransitionOverlayMaximumAlpha: CGFloat = 0.12
        static let historyTransitionProjectionDuration: CGFloat = 0.2
        static let historyTransitionDuration: TimeInterval = 0.35
    }
    
    private enum HistorySwipeDirection: Equatable {
        case back
        case forward
    }
    
    private enum HistorySwipeState {
        case idle // No history swipe is active.
        case swiping(HistorySwipeDirection) // Gesture is tracking the user's drag.
        case settling // Swipe completed; finish animation is running.
        case settled // Location changed before finish animation ended.
        case loaded // Page load completed before finish animation ended.
        case loading // Finish animation ended; waiting for page load.
        case resetting // Location changed without a load; reset on next run loop.
    }
    
    struct State: Equatable {
        let webVisibility: WebContentView.VisibilityState
        let overlayPresentation: OverlayContentView.PresentationState
        
        static let browsing = State(
            webVisibility: .visible,
            overlayPresentation: .hidden
        )
    }
    
    struct LayoutState: Equatable {
        enum Mode: Equatable {
            case standard
            case searchFocused
            case fullscreen
        }
        
        let mode: Mode
    }
    
    private(set) var state: State = .browsing {
        didSet {
            onAppearanceChanged?()
        }
    }
    private var layoutState = LayoutState(mode: .standard)
    private var session: GeckoSession?
    private var dynamicToolbarMaxHeight: CGFloat = 0
    private var contentBottomOffset: CGFloat = 0
    private var toolbarTopOffset: CGFloat = 0
    private var contentTopInset: CGFloat = 0
    private var contentBottomInset: CGFloat = 0
    private var webContentBottomOffset: CGFloat = 0
    private var focusedInputOffset: CGFloat = 0
    private var focusedInputTask: Task<Void, Never>?
    
    private var canGoBack = false
    private var canGoForward = false
    private var backPreviewImage: UIImage?
    private var forwardPreviewImage: UIImage?
    private var isHistorySwipeEnabled = false
    private var historySwipeState = HistorySwipeState.idle
    private var activeHistorySwipeDirection: HistorySwipeDirection?
    private var webContentSize: CGSize?
    
    private let webContentView = WebContentView()
    private let overlayContentView = OverlayContentView()
    private let historyPreviewImageView = UIImageView()
    private let historyTransitionOverlayView = UIView()
    
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onHistorySwipeBegan: (() -> Void)?
    var onHistorySwipeEnded: (() -> Void)?
    var onVerticalScroll: ((CGFloat, CGFloat) -> Void)?
    var onAppearanceChanged: (() -> Void)?
    
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var webContentTopConstraint: NSLayoutConstraint?
    private var webContentBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureHistoryNavigation()
        configureObservers()
        applyState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        focusedInputTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !super.point(inside: point, with: event) else {
            return true
        }
        guard !webContentView.isHidden,
              webContentView.isUserInteractionEnabled else {
            return false
        }
        return webContentView.point(
            inside: webContentView.convert(point, from: self),
            with: event
        )
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBackground
    }
    
    private func configureHierarchy() {
        webContentView.translatesAutoresizingMaskIntoConstraints = false
        historyPreviewImageView.translatesAutoresizingMaskIntoConstraints = false
        historyTransitionOverlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayContentView.translatesAutoresizingMaskIntoConstraints = false
        historyPreviewImageView.isHidden = true
        historyPreviewImageView.backgroundColor = .systemBackground
        historyPreviewImageView.contentMode = .scaleAspectFill
        historyPreviewImageView.clipsToBounds = true
        historyTransitionOverlayView.isHidden = true
        historyTransitionOverlayView.backgroundColor = .black
        historyTransitionOverlayView.alpha = 0
        addSubview(webContentView)
        addSubview(historyPreviewImageView)
        addSubview(historyTransitionOverlayView)
        addSubview(overlayContentView)
    }
    
    private func configureConstraints() {
        let topConstraint = webContentView.topAnchor.constraint(equalTo: topAnchor)
        webContentTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            webContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        
        [historyPreviewImageView, historyTransitionOverlayView].forEach { contentView in
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }
    
    private func configureHistoryNavigation() {
        let backGesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleBackHistoryPan(_:))
        )
        backGesture.edges = .left
        backGesture.delegate = self
        addGestureRecognizer(backGesture)
        
        let forwardGesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleForwardHistoryPan(_:))
        )
        forwardGesture.edges = .right
        forwardGesture.delegate = self
        addGestureRecognizer(forwardGesture)
        
        webContentView.historySwipeDirectionsProvider = { [weak self] in
            return self?.allowedTrackpadHistorySwipeDirections() ?? []
        }
        webContentView.onHistorySwipeDidStart = { [weak self] direction in
            self?.beginTrackpadHistoryNavigation(direction)
        }
        webContentView.onHistorySwipeDidUpdate = { [weak self] progress in
            self?.updateTrackpadHistoryNavigation(progress)
        }
        webContentView.onHistorySwipeDidComplete = { [weak self] direction in
            self?.completeTrackpadHistoryNavigation(direction)
        }
        webContentView.onHistorySwipeDidEnd = { [weak self] in
            self?.endTrackpadHistoryNavigation()
        }
        webContentView.onVerticalScroll = { [weak self] delta, position in
            self?.onVerticalScroll?(delta, position)
        }
    }
    
    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceGestureSettingsDidChange),
            name: .appearanceGestureSettingsDidChange,
            object: nil
        )
    }
    
    // MARK: - Layout
    
    func applyLayout(
        _ layoutState: LayoutState,
        topAnchor: NSLayoutYAxisAnchor,
        bottomAnchor: NSLayoutYAxisAnchor
    ) {
        self.layoutState = layoutState
        webContentView.setFullscreen(layoutState.mode == .fullscreen)
        applyLayoutState(topAnchor: topAnchor, bottomAnchor: bottomAnchor)
    }
    
    func updateWebContentSize() -> Bool {
        let size = webContentView.bounds.size
        guard size.width > 1, size.height > 1 else {
            return false
        }
        defer { webContentSize = size }
        
        guard let previousSize = webContentSize else {
            return false
        }
        
        return previousSize != size
    }
    
    func setToolbarLimits(
        maxHeight: CGFloat,
        contentTopInset: CGFloat,
        contentBottomInset: CGFloat,
        webContentBottomOffset: CGFloat
    ) {
        defer {
            applyToolbarOffsets(top: toolbarTopOffset, bottom: -contentBottomOffset, refresh: true)
        }
        
        if maxHeight != dynamicToolbarMaxHeight {
            dynamicToolbarMaxHeight = maxHeight
            session?.setDynamicToolbarMaxHeight(maxHeight)
        }
        
        self.contentBottomInset = contentBottomInset
        guard abs(contentTopInset - self.contentTopInset) > 0.5
                || abs(webContentBottomOffset - self.webContentBottomOffset) > 0.5 else {
            return
        }
        self.contentTopInset = contentTopInset
        webContentTopConstraint?.constant = -contentTopInset
        self.webContentBottomOffset = webContentBottomOffset
        updateContentBottomInset()
        superview?.layoutIfNeeded()
    }
    
    func applyToolbarOffsets(top: CGFloat, bottom: CGFloat, refresh: Bool = false) {
        let contentBottomOffset = -bottom
        guard refresh || top != toolbarTopOffset || contentBottomOffset != self.contentBottomOffset else {
            return
        }
        toolbarTopOffset = top
        self.contentBottomOffset = contentBottomOffset
        session?.setContentOffsets(
            top: -top,
            bottom: contentBottomOffset,
            topInset: contentTopInset,
            bottomInset: contentBottomInset
        )
    }
    
    func configureLayout(
        topAnchor: NSLayoutYAxisAnchor,
        bottomAnchor: NSLayoutYAxisAnchor
    ) {
        let bottomConstraint = webContentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomConstraint.isActive = true
        webContentBottomConstraint = bottomConstraint
        webContentView.extendPageBackground(from: topAnchor, to: bottomAnchor)
        [historyPreviewImageView, historyTransitionOverlayView].forEach { contentView in
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.bottomAnchor.constraint(equalTo: webContentView.bottomAnchor),
            ])
        }
        overlayContentView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        overlayContentView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        overlayContentView.configureContentLayout(
            topAnchor: safeAreaLayoutGuide.topAnchor,
            bottomAnchor: self.bottomAnchor
        )
    }
    
    private func applyLayoutState(
        topAnchor: NSLayoutYAxisAnchor,
        bottomAnchor: NSLayoutYAxisAnchor
    ) {
        let nextTopConstraint = self.topAnchor.constraint(equalTo: topAnchor)
        let nextBottomConstraint = self.bottomAnchor.constraint(equalTo: bottomAnchor)
        guard canActivateConstraints([nextTopConstraint, nextBottomConstraint]) else {
            return
        }
        
        topConstraint?.isActive = false
        bottomConstraint?.isActive = false
        
        NSLayoutConstraint.activate([nextTopConstraint, nextBottomConstraint])
        topConstraint = nextTopConstraint
        bottomConstraint = nextBottomConstraint
        updateLayoutOffsets()
        transform = focusedInputTransform
        updatePullToRefreshAvailability()
    }
    
    private func canActivateConstraints(_ constraints: [NSLayoutConstraint]) -> Bool {
        constraints.allSatisfy { constraint in
            guard let firstView = owningView(for: constraint.firstItem),
                  let secondView = owningView(for: constraint.secondItem) else {
                return true
            }
            
            return firstView.hasCommonAncestor(with: secondView)
        }
    }
    
    private func owningView(for item: Any?) -> UIView? {
        if let view = item as? UIView {
            return view
        }
        
        if let layoutGuide = item as? UILayoutGuide {
            return layoutGuide.owningView
        }
        
        return nil
    }
    
    private func updateLayoutOffsets() {
        let constraintOffset = layoutState.mode == .standard ? 0 : focusedInputOffset
        topConstraint?.constant = layoutState.mode == .fullscreen ? 0 : -constraintOffset
        switch layoutState.mode {
        case .standard:
            bottomConstraint?.constant = 0
        case .searchFocused:
            bottomConstraint?.constant = -UX.phoneSearchFocusedBottomInset
        case .fullscreen:
            bottomConstraint?.constant = 0
        }
        updateContentBottomInset()
    }
    
    private func updateContentBottomInset() {
        let constraintOffset = layoutState.mode == .standard ? 0 : focusedInputOffset
        webContentBottomConstraint?.constant = webContentBottomOffset - constraintOffset
    }
    
    private var focusedInputTransform: CGAffineTransform {
        guard layoutState.mode == .standard else {
            return .identity
        }
        return CGAffineTransform(translationX: 0, y: -focusedInputOffset)
    }
    
    // MARK: - Focused Input Relocation
    
    func relocateFocusedInput(
        above keyboardFrame: CGRect,
        bottomInset: CGFloat = 0,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions
    ) {
        focusedInputTask?.cancel()
        guard let session,
              let engineView = session.engineView,
              engineView.isFirstResponder,
              let textInput = engineView as? UITextInput,
              textInput.selectedTextRange != nil else {
            resetFocusedInputRelocation(
                animationDuration: animationDuration,
                animationOptions: animationOptions
            )
            return
        }
        
        focusedInputTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let bottomRatio = await session.focusedInputBottomRatio()
            guard !Task.isCancelled,
                  engineView.isFirstResponder,
                  let selectedTextRange = textInput.selectedTextRange,
                  let bottomRatio else { return }
            
            superview?.layoutIfNeeded()
            let caretRect = textInput.caretRect(for: selectedTextRange.end)
            guard !caretRect.isEmpty else { return }
            let engineFrame = engineView.convert(engineView.bounds, to: self)
            let viewportFrame = engineFrame.inset(by: UIEdgeInsets(
                top: max(0, contentTopInset - toolbarTopOffset),
                left: 0,
                bottom: max(0, dynamicToolbarMaxHeight - contentTopInset + contentBottomOffset),
                right: 0
            ))
            let newOffset = calculateFocusedInputOffset(
                focusedInputBottom: viewportFrame.minY + viewportFrame.height * bottomRatio,
                webContentBottom: viewportFrame.maxY,
                caretRect: engineView.convert(caretRect, to: self),
                keyboardTop: keyboardFrame.minY - bottomInset - frame.minY - focusedInputOffset
            )
            guard abs(newOffset - focusedInputOffset) > UX.focusedInputOffsetThreshold else {
                return
            }
            
            focusedInputOffset = newOffset
            updateLayoutOffsets()
            animateLayout(duration: animationDuration, options: animationOptions)
        }
    }
    
    private func calculateFocusedInputOffset(
        focusedInputBottom: CGFloat,
        webContentBottom: CGFloat,
        caretRect: CGRect,
        keyboardTop: CGFloat
    ) -> CGFloat {
        let maximumViewOffset = max(0, webContentBottom - keyboardTop)
        let visibleBottom = max(0, keyboardTop - UX.focusedInputBottomClearance)
        let elementOffset = max(0, focusedInputBottom - visibleBottom)
        let maximumOffset = min(maximumViewOffset, max(0, caretRect.minY - UX.focusedInputBottomClearance))
        return min(maximumOffset, elementOffset)
    }
    
    func resetFocusedInputRelocation(
        animationDuration: TimeInterval = 0,
        animationOptions: UIView.AnimationOptions = []
    ) {
        focusedInputTask?.cancel()
        focusedInputTask = nil
        guard focusedInputOffset != 0 else { return }
        
        focusedInputOffset = 0
        updateLayoutOffsets()
        animateLayout(duration: animationDuration, options: animationOptions)
    }
    
    private func animateLayout(duration: TimeInterval, options: UIView.AnimationOptions) {
        guard duration > 0 else {
            transform = focusedInputTransform
            superview?.layoutIfNeeded()
            return
        }
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.transform = self.focusedInputTransform
            self.superview?.layoutIfNeeded()
        }
    }
    
    // MARK: - State
    
    func setState(_ state: State) {
        guard self.state != state else {
            return
        }
        
        self.state = state
        applyState()
    }
    
    func setWebVisibility(_ visibility: WebContentView.VisibilityState) {
        setState(State(
            webVisibility: visibility,
            overlayPresentation: state.overlayPresentation
        ))
    }
    
    func setOverlayPresentation(
        _ presentation: OverlayContentView.PresentationState,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        self.state = State(
            webVisibility: state.webVisibility,
            overlayPresentation: presentation
        )
        webContentView.setVisibility(state.webVisibility)
        overlayContentView.setPresentation(presentation, animated: animated, completion: completion)
        updatePullToRefreshAvailability()
    }
    
    private func applyState() {
        webContentView.setVisibility(state.webVisibility)
        overlayContentView.setPresentation(state.overlayPresentation, animated: false)
        updatePullToRefreshAvailability()
    }
    
    // MARK: - Session
    
    func setTab(_ tab: Tab?, pageBackgroundColor: UIColor? = nil) {
        resetHistoryNavigation()
        self.session = tab?.session
        resetFocusedInputRelocation()
        webContentView.setTab(tab, pageBackgroundColor: pageBackgroundColor)
        onAppearanceChanged?()
        tab?.session.setDynamicToolbarMaxHeight(dynamicToolbarMaxHeight)
        applyToolbarOffsets(top: toolbarTopOffset, bottom: -contentBottomOffset, refresh: true)
        updatePullToRefreshAvailability()
    }
    
    func setPageBackgroundColor(_ color: UIColor) {
        webContentView.setPageBackgroundColor(color)
        onAppearanceChanged?()
    }
    
    func resetScrollTracking() {
        webContentView.resetScrollTracking()
    }
    
    func showPageError(for url: String?) {
        webContentView.showPageError(for: url)
    }
    
    func didFinishLoading(session: GeckoSession) {
        webContentView.didFinishLoading(session: session)
    }
    
    func isDisplaying(session: GeckoSession) -> Bool {
        webContentView.isDisplaying(session: session)
    }
    
    func restoreInteraction(for session: GeckoSession) {
        webContentView.restoreInteraction(for: session)
    }
    
    // MARK: - Interaction
    
    func addWebViewInteraction(_ interaction: UIInteraction) {
        webContentView.addWebViewInteraction(interaction)
    }
    
    // MARK: - History Navigation
    
    func setHistoryNavigation(
        canGoBack: Bool,
        canGoForward: Bool,
        backPreviewImage: UIImage?,
        forwardPreviewImage: UIImage?,
        isSwipeEnabled: Bool
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.backPreviewImage = backPreviewImage
        self.forwardPreviewImage = forwardPreviewImage
        isHistorySwipeEnabled = isSwipeEnabled
    }
    
    @objc private func handleBackHistoryPan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        handleHistoryPan(gesture, direction: .back)
    }
    
    @objc private func handleForwardHistoryPan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        handleHistoryPan(gesture, direction: .forward)
    }
    
    private func handleHistoryPan(
        _ gesture: UIScreenEdgePanGestureRecognizer,
        direction: HistorySwipeDirection
    ) {
        switch gesture.state {
        case .began:
            beginHistoryNavigation(direction)
        case .changed:
            updateHistoryNavigation(gesture, direction: direction)
        case .ended:
            finishHistoryNavigation(gesture, direction: direction, cancelled: false)
        case .cancelled, .failed:
            finishHistoryNavigation(gesture, direction: direction, cancelled: true)
        default:
            break
        }
    }
    
    private func beginHistoryNavigation(_ direction: HistorySwipeDirection) {
        guard case .idle = historySwipeState else {
            return
        }
        
        onHistorySwipeBegan?()
        historySwipeState = .swiping(direction)
        activeHistorySwipeDirection = direction
        updatePullToRefreshAvailability()
        historyPreviewImageView.image = direction == .back ? backPreviewImage : forwardPreviewImage
        historyPreviewImageView.isHidden = false
        historyTransitionOverlayView.isHidden = false
        
        let width = bounds.width
        switch direction {
        case .back:
            insertSubview(historyPreviewImageView, belowSubview: webContentView)
            insertSubview(historyTransitionOverlayView, belowSubview: webContentView)
            historyPreviewImageView.transform = CGAffineTransform(
                translationX: -width * UX.historyPreviewParallaxRatio, y: 0
            )
            updateHistoryTransitionOverlay(direction: direction, progress: 0)
        case .forward:
            insertSubview(historyTransitionOverlayView, aboveSubview: webContentView)
            insertSubview(historyPreviewImageView, aboveSubview: historyTransitionOverlayView)
            historyPreviewImageView.transform = CGAffineTransform(translationX: width, y: 0)
            updateHistoryTransitionOverlay(direction: direction, progress: 0)
        }
        historyTransitionOverlayView.transform = .identity
    }
    
    private func updateHistoryNavigation(
        _ gesture: UIScreenEdgePanGestureRecognizer,
        direction: HistorySwipeDirection
    ) {
        let progress = historyNavigationProgress(for: gesture, direction: direction)
        updateHistoryNavigation(progress: progress, direction: direction)
    }
    
    private func updateHistoryNavigation(
        progress: CGFloat,
        direction: HistorySwipeDirection
    ) {
        guard case .swiping(let activeDirection) = historySwipeState,
              activeDirection == direction else {
            return
        }
        
        let width = bounds.width
        switch direction {
        case .back:
            webContentView.transform = CGAffineTransform(translationX: width * progress, y: 0)
            historyPreviewImageView.transform = CGAffineTransform(
                translationX: -width * UX.historyPreviewParallaxRatio * (1 - progress), y: 0
            )
        case .forward:
            historyPreviewImageView.transform = CGAffineTransform(
                translationX: width * (1 - progress), y: 0
            )
        }
        updateHistoryTransitionOverlay(direction: direction, progress: progress)
    }
    
    private func finishHistoryNavigation(
        _ gesture: UIScreenEdgePanGestureRecognizer,
        direction: HistorySwipeDirection,
        cancelled: Bool
    ) {
        guard case .swiping(let activeDirection) = historySwipeState,
              activeDirection == direction else {
            resetHistoryNavigation()
            return
        }
        
        let progress = historyNavigationProgress(for: gesture, direction: direction)
        let velocityX = gesture.velocity(in: self).x
        let directionalVelocity: CGFloat
        switch direction {
        case .back:
            directionalVelocity = max(velocityX, 0)
        case .forward:
            directionalVelocity = max(-velocityX, 0)
        }
        
        let width = bounds.width
        let projectedDistance = width * progress
        + directionalVelocity * UX.historyTransitionProjectionDuration
        let shouldComplete = !cancelled && projectedDistance >= width
        
        settleHistoryNavigation(
            direction: direction,
            shouldComplete: shouldComplete,
            velocityX: velocityX
        )
    }
    
    private func settleHistoryNavigation(
        direction: HistorySwipeDirection,
        shouldComplete: Bool,
        velocityX: CGFloat
    ) {
        let width = bounds.width
        UIView.animate(
            withDuration: UX.historyTransitionDuration,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: abs(velocityX) / max(width, 1),
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            if shouldComplete {
                self.historySwipeState = .settling
                switch direction {
                case .back:
                    self.webContentView.transform = CGAffineTransform(translationX: width, y: 0)
                    self.historyPreviewImageView.transform = .identity
                    self.updateHistoryTransitionOverlay(direction: direction, progress: 1)
                    self.onBack?()
                case .forward:
                    self.historyPreviewImageView.transform = .identity
                    self.updateHistoryTransitionOverlay(direction: direction, progress: 1)
                    self.onForward?()
                }
            } else {
                self.webContentView.transform = .identity
                switch direction {
                case .back:
                    self.historyPreviewImageView.transform = CGAffineTransform(
                        translationX: -width * UX.historyPreviewParallaxRatio, y: 0
                    )
                    self.updateHistoryTransitionOverlay(direction: direction, progress: 0)
                case .forward:
                    self.historyPreviewImageView.transform = CGAffineTransform(translationX: width, y: 0)
                    self.updateHistoryTransitionOverlay(direction: direction, progress: 0)
                }
            }
        } completion: { _ in
            guard shouldComplete else {
                self.resetHistoryNavigation()
                return
            }
            
            if case .loaded = self.historySwipeState {
                self.resetHistoryNavigation()
                return
            }
            
            switch self.historySwipeState {
            case .settling:
                self.historySwipeState = .loading
            case .settled:
                self.scheduleHistoryLocationReset()
            default:
                break
            }
        }
    }
    
    private func historyNavigationProgress(
        for gesture: UIScreenEdgePanGestureRecognizer,
        direction: HistorySwipeDirection
    ) -> CGFloat {
        let translationX = gesture.translation(in: self).x
        let distance: CGFloat
        switch direction {
        case .back:
            distance = translationX
        case .forward:
            distance = -translationX
        }
        return min(max(distance / max(bounds.width, 1), 0), 1)
    }
    
    private func allowedTrackpadHistorySwipeDirections() -> GeckoEdgeSwipeDirections {
        guard canBeginHistoryNavigation else {
            return []
        }
        
        var directions: GeckoEdgeSwipeDirections = []
        if canGoBack {
            directions.insert(.left)
        }
        if canGoForward {
            directions.insert(.right)
        }
        return directions
    }
    
    private func beginTrackpadHistoryNavigation(_ direction: GeckoEdgeSwipeDirections) {
        guard let direction = historySwipeDirection(from: direction) else {
            return
        }
        beginHistoryNavigation(direction)
    }
    
    private func updateTrackpadHistoryNavigation(_ progress: CGFloat) {
        guard let direction = activeHistorySwipeDirection else {
            return
        }
        updateHistoryNavigation(
            progress: min(max(progress, 0), 1),
            direction: direction
        )
    }
    
    private func completeTrackpadHistoryNavigation(_ direction: GeckoEdgeSwipeDirections) {
        guard let direction = historySwipeDirection(from: direction),
              direction == activeHistorySwipeDirection,
              case .swiping(let activeDirection) = historySwipeState,
              activeDirection == direction else {
            return
        }
        
        settleHistoryNavigation(
            direction: direction,
            shouldComplete: true,
            velocityX: 0
        )
    }
    
    private func endTrackpadHistoryNavigation() {
        guard case .swiping = historySwipeState else {
            return
        }
        resetHistoryNavigation()
    }
    
    private func historySwipeDirection(
        from direction: GeckoEdgeSwipeDirections
    ) -> HistorySwipeDirection? {
        if direction.contains(.left) {
            return .back
        }
        if direction.contains(.right) {
            return .forward
        }
        return nil
    }
    
    private func updateHistoryTransitionOverlay(
        direction: HistorySwipeDirection,
        progress: CGFloat
    ) {
        let leadingEdgeProgress: CGFloat
        switch direction {
        case .back:
            leadingEdgeProgress = 1 - progress
        case .forward:
            leadingEdgeProgress = progress
        }
        
        historyTransitionOverlayView.alpha = UX.historyTransitionOverlayMaximumAlpha * leadingEdgeProgress
    }
    
    private func resetHistoryNavigation() {
        webContentView.transform = .identity
        historyPreviewImageView.transform = .identity
        historyTransitionOverlayView.transform = .identity
        historyPreviewImageView.image = nil
        historyPreviewImageView.isHidden = true
        historyTransitionOverlayView.alpha = 0
        historyTransitionOverlayView.isHidden = true
        historySwipeState = .idle
        activeHistorySwipeDirection = nil
        updatePullToRefreshAvailability()
        onHistorySwipeEnded?()
    }
    
    private func updatePullToRefreshAvailability() {
        let isHistoryNavigationIdle: Bool
        if case .idle = historySwipeState {
            isHistoryNavigationIdle = true
        } else {
            isHistoryNavigationIdle = false
        }
        let isEnabled = session != nil &&
        state == .browsing &&
        webContentView.visibility == .visible &&
        layoutState.mode != .fullscreen &&
        Prefs.AppearanceSettings.pullToRefreshEnabled &&
        isHistoryNavigationIdle
        webContentView.setPullToRefreshEnabled(isEnabled)
    }
    
    @objc private func appearanceGestureSettingsDidChange() {
        updatePullToRefreshAvailability()
    }
    
    func finishHistoryLoad() {
        switch historySwipeState {
        case .settling, .settled:
            historySwipeState = .loaded
        case .loading, .resetting:
            resetHistoryNavigation()
        case .idle, .swiping, .loaded:
            break
        }
    }
    
    func noteHistoryLocationChange() {
        switch historySwipeState {
        case .settling:
            historySwipeState = .settled
        case .loading:
            scheduleHistoryLocationReset()
        case .idle, .swiping, .settled, .loaded, .resetting:
            break
        }
    }
    
    private func scheduleHistoryLocationReset() {
        historySwipeState = .resetting
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  case .resetting = self.historySwipeState else {
                return
            }
            
            self.resetHistoryNavigation()
        }
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIScreenEdgePanGestureRecognizer,
              canBeginHistoryNavigation else {
            return false
        }
        
        if let backGesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
           backGesture.edges == .left {
            return canGoBack
        }
        
        return canGoForward
    }
    
    private var canBeginHistoryNavigation: Bool {
        guard case .idle = historySwipeState else {
            return false
        }
        
        return isHistorySwipeEnabled &&
        state == .browsing &&
        webContentView.visibility == .visible
    }
    
    // MARK: - Presentation
    
    func setTransitionTransform(_ transform: CGAffineTransform) {
        self.transform = transform
    }
    
    func setTransitionHidden(_ hidden: Bool) {
        isHidden = hidden
    }
    
    func frame(in view: UIView) -> CGRect {
        convert(bounds, to: view)
    }
    
    // MARK: - Thumbnail
    
    func thumbnailGeometry(in view: UIView) -> ThumbnailGeometry? {
        let fullFrame = webContentView.thumbnailFrame(in: view)
        let visibleFrame = fullFrame.intersection(frame(in: view))
        guard fullFrame.width > 1,
              fullFrame.height > 1,
              visibleFrame.width > 1,
              visibleFrame.height > 1 else {
            return nil
        }
        
        return ThumbnailGeometry(
            fullFrame: fullFrame,
            cropRect: CGRect(
                x: (visibleFrame.minX - fullFrame.minX) / fullFrame.width,
                y: (visibleFrame.minY - fullFrame.minY) / fullFrame.height,
                width: visibleFrame.width / fullFrame.width,
                height: visibleFrame.height / fullFrame.height
            )
        )
    }
    
    var thumbnailCaptureGeometry: ThumbnailCaptureGeometry? {
        guard let geometry = thumbnailGeometry(in: self) else {
            return nil
        }
        
        let size = geometry.fullFrame.size
        return ThumbnailCaptureGeometry(
            size: size,
            visibleRect: CGRect(
                x: geometry.cropRect.minX * size.width,
                y: geometry.cropRect.minY * size.height,
                width: geometry.cropRect.width * size.width,
                height: geometry.cropRect.height * size.height
            )
        )
    }
    
    func makeWebThumbnail() -> UIImage? {
        return webContentView.makeThumbnail()
    }
    
    // MARK: - Overlay Hosting
    
    func setOverlayController(
        _ viewController: UIViewController,
        for page: OverlayContentView.Page,
        in parentViewController: UIViewController
    ) {
        overlayContentView.setController(viewController, for: page, in: parentViewController)
    }
    
    func layoutOverlayIfNeeded() {
        overlayContentView.layoutIfNeeded()
    }
    
    func removeOverlayController(for page: OverlayContentView.Page) {
        overlayContentView.removeController(for: page)
    }
}
