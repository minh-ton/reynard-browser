//
//  BrowserViewController+ContextMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: ContextMenuCoordinatorHost {
    var contextMenuPresenter: UIViewController {
        return self
    }
    
    var contextMenuSourceView: ContentView {
        return contentView
    }
    
    var contextMenuTabActions: ContextMenuTabActions {
        return ContextMenuTabActions(tabManager: tabManager)
    }
    
    var contextMenuSelectedTabIsPrivate: Bool {
        return tabManager.selectedTab?.isPrivate ?? false
    }
    
    var contextMenuSelectedSession: GeckoSession? {
        return tabManager.selectedTab?.session
    }
    
    func contextMenuShareLink(_ url: URL) {
        presentShareSheet(url: url.absoluteString)
    }
    
    func contextMenuRestoreInteraction(for session: GeckoSession) {
        contentView.restoreInteraction(for: session)
        sessionManager.activate(session)
    }
}
