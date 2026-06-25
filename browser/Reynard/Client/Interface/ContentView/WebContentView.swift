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
    
    private(set) var visibility: VisibilityState = .visible
    
    private let webView = GeckoView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureConstraints()
        applyVisibility()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
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
        webView.session = session
    }
    
    func isDisplaying(session: GeckoSession) -> Bool {
        webView.session === session
    }
    
    func restoreInteraction(for session: GeckoSession) {
        isHidden = false
        alpha = 1
        isUserInteractionEnabled = true
        webView.isHidden = false
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        if webView.session !== session {
            webView.session = session
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    func hasRenderableContent(for session: GeckoSession) -> Bool {
        layoutIfNeeded()
        return webView.session === session
            && window != nil
            && webView.window != nil
            && !isHidden
            && !webView.isHidden
            && alpha > 0.01
            && webView.alpha > 0.01
            && isUserInteractionEnabled
            && webView.isUserInteractionEnabled
            && bounds.width > 1
            && bounds.height > 1
            && webView.bounds.width > 1
            && webView.bounds.height > 1
    }
    
    func addWebViewInteraction(_ interaction: UIInteraction) {
        webView.addInteraction(interaction)
    }
}
