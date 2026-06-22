//
//  LinkPreviewMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

struct LinkPreviewMenu {
    static func configuration(
        for context: ContextMenuContext,
        showsPreview: Bool,
        isPrivate: Bool,
        sessionManager: SessionManager,
        onPreviewCreated: @escaping (LinkPreviewViewController) -> Void,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL) -> Void
    ) -> UIContextMenuConfiguration? {
        guard case .link(let url) = context.target else {
            return nil
        }
        
        let previewProvider: UIContextMenuContentPreviewProvider? = showsPreview ? { [url] in
            let viewController = LinkPreviewViewController(
                url: url,
                isPrivate: isPrivate,
                sessionManager: sessionManager
            )
            onPreviewCreated(viewController)
            return viewController
        } : nil
        
        return UIContextMenuConfiguration(identifier: url as NSURL, previewProvider: previewProvider) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "Open in New Tab", image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                    openInNewTab()
                },
                UIAction(title: "Open in New Private Tab", image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                    openInNewPrivateTab()
                },
                UIAction(title: "Copy Link", image: UIImage(named: "reynard.document.on.document")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: "Share Link", image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                    shareLink(url)
                },
            ])
        }
    }
}
