//
//  FrequentlyVisitedSiteActions.swift
//  Reynard
//
//  Created by Minh Ton on 27/6/26.
//

import UIKit

struct FrequentlyVisitedSiteActions {
    static func configuration(
        for site: HistorySiteSnapshot,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL) -> Void,
        removeLink: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(identifier: site.url as NSURL, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: "Open in New Tab", image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                        openInNewTab()
                    },
                    UIAction(title: "Open in New Private Tab", image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                        openInNewPrivateTab()
                    },
                ]),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: "Copy Link", image: UIImage(named: "reynard.document.on.document")) { _ in
                        UIPasteboard.general.string = site.url.absoluteString
                    },
                    UIAction(title: "Share Link", image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                        shareLink(site.url)
                    },
                ]),
                UIAction(title: "Remove Link", image: UIImage(named: "reynard.minus.circle"), attributes: .destructive) { _ in
                    removeLink()
                },
            ])
        }
    }
}

extension FrequentlyVisitedSectionViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let cardView = interaction.view as? FrequentlyVisitedSiteCardView,
              let site = site(for: cardView) else {
            return nil
        }
        
        return FrequentlyVisitedSiteActions.configuration(
            for: site,
            openInNewTab: { [weak self] in
                guard let self else {
                    return
                }
                
                self.delegate?.homepageSection(self, didRequestOpenURL: site.url, disposition: .newTab)
            },
            openInNewPrivateTab: { [weak self] in
                guard let self else {
                    return
                }
                
                self.delegate?.homepageSection(self, didRequestOpenURL: site.url, disposition: .newPrivateTab)
            },
            shareLink: { [weak self] url in
                guard let self else {
                    return
                }
                
                self.delegate?.homepageSection(self, didRequestShareURL: url)
            },
            removeLink: { [weak self] in
                guard let self else {
                    return
                }
                
                self.delegate?.homepageSection(self, didRequestHideFromSuggestions: site.id)
            }
        )
    }
}
