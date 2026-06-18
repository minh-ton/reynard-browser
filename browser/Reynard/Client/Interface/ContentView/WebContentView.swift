//
//  WebContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class WebContentView: UIView {
    enum VisibilityState: Equatable {
        case visible
        case hidden
    }

    // MARK: - State

    private(set) var visibility: VisibilityState = .visible

    // MARK: - Views

    private let webView = GeckoView()

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureConstraints()
        applyVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    private func configureHierarchy() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - State

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

    // MARK: - Session

    func setSession(_ session: GeckoSession?) {
        webView.session = session
    }

    func isDisplaying(session: GeckoSession) -> Bool {
        webView.session === session
    }

    func restoreInteraction(for session: GeckoSession) {
        webView.session = session
    }

    // MARK: - Interaction

    func addWebViewInteraction(_ interaction: UIInteraction) {
        webView.addInteraction(interaction)
    }
}
