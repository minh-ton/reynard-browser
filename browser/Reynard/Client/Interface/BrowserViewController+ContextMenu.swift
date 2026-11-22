//
//  BrowserViewController+ContextMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: ContextMenuCoordinatorHost {
    func captureSourceTabThumbnail() {
        captureThumbnail(for: tabManager.selectedTab)
    }
    
    func contextMenuOpenLink(_ url: URL, disposition: TabOpenDisposition) {
        let mode: TabMode
        let target: TabInsertionTarget
        
        switch disposition {
        case .currentTab:
            tabManager.browse(to: url.absoluteString)
            return
        case .newTab, .backgroundTab:
            mode = tabManager.selectedTabMode
            target = .afterSelected
        case .newPrivateTab:
            mode = .private
            target = tabManager.selectedTabMode == .private ? .afterSelected : .end
        }
        
        let openerTabID = mode == .regular ? tabManager.selectedTab?.id : nil
        let tab = tabManager.createTab(selecting: disposition != .backgroundTab, target: target, mode: mode)
        tab.state.openerTabID = openerTabID
        tabManager.browse(to: url.absoluteString, in: tab)
        guard disposition != .backgroundTab else {
            return
        }
        
        captureThumbnail(for: tabManager.selectedTab)
        tabBar.setPendingExpansion(to: tab)
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab) { [weak self] in
            self?.tabManager.selectTab(tab)
        }
    }
    
    func contextMenuPresentShareSheet(items: [Any], sourceView: UIView, sourceRect: CGRect) {
        presentShareSheet(
            items: items,
            sourceView: sourceView,
            sourceRect: sourceRect
        )
    }
    
    func contextMenuRestoreInteraction(for session: GeckoSession) {
        contentView.restoreInteraction(for: session)
        sessionManager.activate(session)
        requestContentKeyboardFocus(for: session)
    }
    
    func contextMenuExpandToolbar() {
        toolbarController.reset()
    }
}
