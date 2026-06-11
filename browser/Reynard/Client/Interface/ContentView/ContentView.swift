//
//  ContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class ContentView: UIView {
    // MARK: - UX

    private enum UX {
        static let phoneSearchFocusedBottomInset: CGFloat = 94
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
        let verticalOffset: CGFloat
    }

    // MARK: - State

    private(set) var state: State = .browsing
    private var layoutState = LayoutState(
        mode: .standard,
        verticalOffset: 0
    )

    // MARK: - Views

    private let webContentView = WebContentView()
    private let overlayContentView = OverlayContentView()

    // MARK: - Constraints

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
        topConstraint?.isActive = false
        bottomConstraint?.isActive = false

        let topOffset = layoutState.mode == .fullscreen ? 0 : -layoutState.verticalOffset
        let bottomOffset = layoutState.mode == .searchFocused
            ? -UX.phoneSearchFocusedBottomInset
            : (layoutState.mode == .fullscreen ? 0 : -layoutState.verticalOffset)
        let nextTopConstraint = self.topAnchor.constraint(equalTo: topAnchor, constant: topOffset)
        let nextBottomConstraint = self.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomOffset)
        NSLayoutConstraint.activate([nextTopConstraint, nextBottomConstraint])
        topConstraint = nextTopConstraint
        bottomConstraint = nextBottomConstraint
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
