//
//  LinkPreview.swift
//  Reynard
//
//  Created by Minh Ton on 16/5/26.
//

import GeckoView
import UIKit

enum LinkPreviewMenu {
    static func configuration(
        for context: ContextMenuContext,
        isPrivate: Bool,
        onPreviewCreated: @escaping (LinkPreviewViewController) -> Void,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL) -> Void
    ) -> UIContextMenuConfiguration? {
        guard case .link(let url) = context.target else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: url as NSURL) { [url] in
            let viewController = LinkPreviewViewController(url: url, isPrivate: isPrivate)
            onPreviewCreated(viewController)
            return viewController
        } actionProvider: { _ in
            let openInNewTabAction = UIAction(
                title: "Open in New Tab",
                image: UIImage(systemName: "plus")
            ) { _ in
                openInNewTab()
            }
            
            let openInNewPrivateTabAction = UIAction(
                title: "Open in New Private Tab",
                image: UIImage(systemName: "sunglasses")
            ) { _ in
                openInNewPrivateTab()
            }
            
            let copyLinkAction = UIAction(
                title: "Copy Link",
                image: UIImage(systemName: "document.on.document")
            ) { _ in
                UIPasteboard.general.string = url.absoluteString
            }
            
            let shareLinkAction = UIAction(
                title: "Share Link",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                shareLink(url)
            }
            
            return UIMenu(title: "", children: [openInNewTabAction, openInNewPrivateTabAction, copyLinkAction, shareLinkAction])
        }
    }
}

final class LinkPreviewViewController: UIViewController, ContentDelegate, NavigationDelegate {
    private(set) var pageURL: String
    private(set) var pageTitle: String?
    private var session: GeckoSession?
    private let geckoView = GeckoView()
    private var hasClosedSession = false
    
    init(url: URL, isPrivate: Bool) {
        pageURL = url.absoluteString
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 340, height: 480)
        session = GeckoSession()
        session?.isPrivateMode = isPrivate
        session?.contentDelegate = self
        session?.navigationDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        closeSessionIfNeeded()
    }
    
    override func loadView() {
        geckoView.backgroundColor = .systemBackground
        geckoView.isUserInteractionEnabled = false
        view = geckoView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let session else {
            return
        }
        
        session.open()
        geckoView.session = session
        session.load(pageURL)
    }
    
    func releaseSessionForCommit() -> GeckoSession? {
        hasClosedSession = true
        let committedSession = session
        session = nil
        geckoView.session = nil
        return committedSession
    }
    
    func closeSessionIfNeeded() {
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
    
    func onTitleChange(session: GeckoSession, title: String) {
        pageTitle = title
    }
    
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let url,
              url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("about:blank") == false else {
            return
        }
        self.pageURL = url
    }
}
