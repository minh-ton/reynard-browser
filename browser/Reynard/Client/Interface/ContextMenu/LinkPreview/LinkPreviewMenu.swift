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
        sourceView: UIView,
        onPreviewCreated: @escaping (LinkPreviewViewController) -> Void,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL, UIView, CGRect) -> Void
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
            var linkActions: [UIMenuElement] = [
                UIAction(title: NSLocalizedString("Open Link in New Tab", comment: ""), image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                    openInNewTab()
                },
            ]
            if !isPrivate {
                linkActions.append(
                    UIAction(title: NSLocalizedString("Open Link in New Private Tab", comment: ""), image: UIImage(named: "reynard.plus.square.fill.on.square.fill")) { _ in
                        openInNewPrivateTab()
                    }
                )
            }
            return UIMenu(title: "", children: [
                UIMenu(title: "", options: .displayInline, children: linkActions),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: NSLocalizedString("Copy Link", comment: ""), image: UIImage(named: "reynard.document.on.document")) { _ in
                        UIPasteboard.general.string = url.absoluteString
                    },
                    UIAction(title: NSLocalizedString("Share Link", comment: ""), image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                        shareLink(
                            url,
                            sourceView,
                            CGRect(origin: context.point, size: .zero)
                        )
                    },
                ]),
            ])
        }
    }
}
