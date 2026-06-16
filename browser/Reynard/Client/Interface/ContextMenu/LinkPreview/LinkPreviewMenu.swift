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
            UIMenu(title: "", children: [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus")) { _ in
                    openInNewTab()
                },
                UIAction(title: "Open in New Private Tab", image: UIImage(systemName: "sunglasses")) { _ in
                    openInNewPrivateTab()
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "document.on.document")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: "Share Link", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    shareLink(url)
                },
            ])
        }
    }
}
