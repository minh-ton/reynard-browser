//
//  LinkPreviewViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

final class LinkPreviewViewController: UIViewController {
    // MARK: - UX

    private enum UX {
        static let preferredPreviewSize = CGSize(width: 340, height: 480)
    }

    // MARK: - State

    private(set) var pageURL: String
    private(set) var pageTitle: String?
    private var session: GeckoSession?
    private var hasClosedSession = false

    // MARK: - Views

    private let geckoView = GeckoView()

    // MARK: - Lifecycle

    init(url: URL, isPrivate: Bool) {
        pageURL = url.absoluteString
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
        let session = GeckoSession()
        session.isPrivateMode = isPrivate
        session.contentDelegate = self
        session.navigationDelegate = self
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
        session?.contentDelegate = nil
        session?.navigationDelegate = nil
        session?.setFocused(false)
        session?.setActive(false)
        geckoView.session = nil
        session?.close()
        session = nil
    }

    private func loadPreview() {
        guard let session else {
            return
        }

        session.open()
        geckoView.session = session
        session.load(pageURL)
    }
}

extension LinkPreviewViewController: ContentDelegate, NavigationDelegate {
    // MARK: - ContentDelegate

    func onTitleChange(session: GeckoSession, title: String) {
        pageTitle = title
    }

    // MARK: - NavigationDelegate

    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let url,
              url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank") == false else {
            return
        }
        pageURL = url
    }
}
