//
//  LinkPreviewViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

final class LinkPreviewViewController: UIViewController {
    private enum UX {
        static let preferredPreviewSize = CGSize(width: 340, height: 480)
    }
    
    private(set) var pageURL: String
    private(set) var pageTitle: String?
    private let sessionManager: SessionManager
    private var session: GeckoSession?
    private var hasClosedSession = false
    
    private let geckoView = GeckoView()
    
    // MARK: - Lifecycle
    
    init(url: URL, isPrivate: Bool, sessionManager: SessionManager) {
        pageURL = url.absoluteString
        self.sessionManager = sessionManager
        super.init(nibName: nil, bundle: nil)
        configurePreview(isPrivate: isPrivate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        closeSession()
    }
    
    override func loadView() {
        configureView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadPreview()
    }
    
    // MARK: - Configuration
    
    private func configurePreview(isPrivate: Bool) {
        preferredContentSize = UX.preferredPreviewSize
        let session = sessionManager.createSession(
            url: pageURL,
            tabID: nil,
            isPrivate: isPrivate,
            opening: .manual,
            delegates: SessionDelegates()
        )
        sessionManager.bindDelegates(
            to: session,
            delegates: SessionDelegates(content: self, navigation: self)
        )
        self.session = session
    }
    
    private func configureView() {
        geckoView.backgroundColor = .systemBackground
        geckoView.isUserInteractionEnabled = false
        view = geckoView
    }
    
    // MARK: - Session
    
    func releaseSession() -> GeckoSession? {
        hasClosedSession = true
        if let session {
            sessionManager.deactivate(session)
        }
        let committedSession = session
        session = nil
        geckoView.session = nil
        return committedSession
    }
    
    func closeSession() {
        guard !hasClosedSession else {
            return
        }
        hasClosedSession = true
        geckoView.session = nil
        if let session {
            sessionManager.close(session)
        }
        session = nil
    }
    
    private func loadPreview() {
        guard let session else {
            return
        }
        
        sessionManager.open(session)
        geckoView.session = session
        sessionManager.activate(session)
        session.load(pageURL)
    }
}

extension LinkPreviewViewController: ContentDelegate, NavigationDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        pageTitle = title
    }
    
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let url,
              url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank") == false else {
            return
        }
        pageURL = url
    }
}
