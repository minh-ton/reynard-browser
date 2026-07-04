//
//  RecentlyCloseTabItemActions.swift
//  Reynard
//
//  Created by Minh Ton on 27/6/26.
//

import UIKit

struct RecentlyCloseTabItemActions {
    static func configuration(
        for tab: TabManagementStore.RecentlyClosedTabSnapshot,
        url: URL?,
        shareLink: @escaping (URL) -> Void,
        removeTab: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(identifier: tab.id.uuidString as NSString, previewProvider: nil) { _ in
            var children: [UIMenuElement] = []
            
            if let url {
                children.append(
                    UIMenu(title: "", options: .displayInline, children: [
                        UIAction(title: NSLocalizedString("Copy Link", comment: ""), image: UIImage(named: "reynard.document.on.document")) { _ in
                            UIPasteboard.general.string = url.absoluteString
                        },
                        UIAction(title: NSLocalizedString("Share Link", comment: ""), image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                            shareLink(url)
                        },
                    ])
                )
            }
            
            children.append(
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(
                        title: NSLocalizedString("Remove Recently Closed TabRemove Recently Closed Tab", comment: ""),
                        image: UIImage(named: "reynard.minus.circle"),
                        attributes: .destructive
                    ) { _ in
                        removeTab()
                    },
                ])
            )
            
            return UIMenu(title: "", children: children)
        }
    }
}

extension RecentlyClosedTabsSectionViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let cell = interaction.view as? RecentlyClosedTabCollectionViewCell,
              let tab = tab(for: cell) else {
            return nil
        }
        
        let url = tab.url.flatMap(URL.init(string:))
        return RecentlyCloseTabItemActions.configuration(
            for: tab,
            url: url,
            shareLink: { [weak self] url in
                guard let self else {
                    return
                }
                
                self.delegate?.homepageSection(self, didRequestShareURL: url)
            },
            removeTab: { [weak self] in
                guard let self else {
                    return
                }
                
                self.removeRecentlyClosedTab(id: tab.id)
            }
        )
    }
}
