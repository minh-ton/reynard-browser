//
//  BrowserViewController+ContextMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: ContextMenuCoordinatorHost {
    // MARK: - ContextMenuCoordinatorHost

    var contextMenuPresenter: UIViewController {
        self
    }

    var contextMenuSourceView: ContentView {
        contentView
    }

    var contextMenuTabActions: ContextMenuTabActions {
        ContextMenuTabActions(tabManager: tabManager)
    }

    var contextMenuSelectedTabIsPrivate: Bool {
        tabManager.selectedTab?.isPrivate ?? false
    }

    var contextMenuSelectedSession: GeckoSession? {
        tabManager.selectedTab?.session
    }

    func contextMenuShareLink(_ url: URL) {
        presentShareSheet(url: url.absoluteString)
    }

    func contextMenuRestoreInteraction(for session: GeckoSession) {
        contentView.restoreInteraction(for: session)
        sessionManager.activate(session)
    }
}
