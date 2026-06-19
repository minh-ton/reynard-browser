//
//  ContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class ContentView: UIView {
    private enum UX {
        static let phoneSearchFocusedBottomInset: CGFloat = 94
        static let focusedInputBottomClearance: CGFloat = 12
        static let focusedInputOffsetThreshold: CGFloat = 0.5
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
    
    private(set) var state: State = .browsing
    private var layoutState = LayoutState(mode: .standard)
    private var session: GeckoSession?
    private var focusedInputTask: Task<Void, Never>?
    private var inputBottomRatio: CGFloat?
    private var focusedInputOffset: CGFloat = 0
    
    private let webContentView = WebContentView()
    private let overlayContentView = OverlayContentView()
    
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        applyState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        focusedInputTask?.cancel()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBackground
    }
    
    private func configureHierarchy() {
        webContentView.translatesAutoresizingMaskIntoConstraints = false
        overlayContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webContentView)
        addSubview(overlayContentView)
    }
    
    private func configureConstraints() {
        [webContentView, overlayContentView].forEach { contentView in
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
    
    // MARK: - Layout
    
    func applyLayout(
        _ layoutState: LayoutState,
        topAnchor: NSLayoutYAxisAnchor,
        bottomAnchor: NSLayoutYAxisAnchor
    ) {
        self.layoutState = layoutState
        applyLayoutState(topAnchor: topAnchor, bottomAnchor: bottomAnchor)
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
        topConstraint?.constant = layoutState.mode == .fullscreen ? 0 : -focusedInputOffset
        switch layoutState.mode {
        case .standard:
            bottomConstraint?.constant = -focusedInputOffset
        case .searchFocused:
            bottomConstraint?.constant = -UX.phoneSearchFocusedBottomInset
        case .fullscreen:
            bottomConstraint?.constant = 0
        }
    }
    
    // MARK: - Focused Input Relocation
    
    func relocateFocusedInput(
        above keyboardFrame: CGRect,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions
    ) {
        focusedInputTask?.cancel()
        guard let session else {
            resetFocusedInputRelocation(
                animationDuration: animationDuration,
                animationOptions: animationOptions
            )
            return
        }
        
        focusedInputTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let bottomRatio = await session.focusedInputBottomRatio()
            guard !Task.isCancelled else { return }
            
            inputBottomRatio = bottomRatio
            superview?.layoutIfNeeded()
            let newOffset = calculateFocusedInputOffset(keyboardFrame: keyboardFrame)
            guard abs(newOffset - focusedInputOffset) > UX.focusedInputOffsetThreshold else {
                return
            }
            
            focusedInputOffset = newOffset
            updateLayoutOffsets()
            animateLayout(duration: animationDuration, options: animationOptions)
        }
    }
    
    private func calculateFocusedInputOffset(keyboardFrame: CGRect) -> CGFloat {
        guard let inputBottomRatio else { return 0 }
        
        let unshiftedFrame = frame.offsetBy(dx: 0, dy: focusedInputOffset)
        guard unshiftedFrame.height > 1 else { return 0 }
        
        let keyboardOverlap = max(0, unshiftedFrame.maxY - keyboardFrame.minY)
        guard keyboardOverlap > 0 else { return 0 }
        
        let focusBottom = unshiftedFrame.height * inputBottomRatio
        let visibleBottom = max(
            0,
            unshiftedFrame.height - keyboardOverlap - UX.focusedInputBottomClearance
        )
        return min(keyboardOverlap, max(0, focusBottom - visibleBottom))
    }
    
    func resetFocusedInputRelocation(
        animationDuration: TimeInterval = 0,
        animationOptions: UIView.AnimationOptions = []
    ) {
        focusedInputTask?.cancel()
        focusedInputTask = nil
        inputBottomRatio = nil
        guard focusedInputOffset != 0 else { return }
        
        focusedInputOffset = 0
        updateLayoutOffsets()
        animateLayout(duration: animationDuration, options: animationOptions)
    }
    
    private func animateLayout(duration: TimeInterval, options: UIView.AnimationOptions) {
        guard duration > 0 else {
            superview?.layoutIfNeeded()
            return
        }
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]
        ) {
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
    }
    
    private func applyState() {
        webContentView.setVisibility(state.webVisibility)
        overlayContentView.setPresentation(state.overlayPresentation, animated: false)
    }
    
    // MARK: - Session
    
    func setSession(_ session: GeckoSession?) {
        self.session = session
        resetFocusedInputRelocation()
        webContentView.setSession(session)
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
    
    // MARK: - Overlay Hosting
    
    func setOverlayController(
        _ viewController: UIViewController,
        for page: OverlayContentView.Page,
        in parentViewController: UIViewController
    ) {
        overlayContentView.setController(viewController, for: page, in: parentViewController)
    }
    
    func removeOverlayController(for page: OverlayContentView.Page) {
        overlayContentView.removeController(for: page)
    }
}

