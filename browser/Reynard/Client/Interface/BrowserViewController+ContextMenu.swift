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
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
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
        let tabIndex = tabManager.createTab(selecting: disposition != .backgroundTab, target: target, mode: mode)
        guard let tab = tabManager.tabs(for: mode)[safe: tabIndex] else {
            return
        }
        
        tab.state.openerTabID = openerTabID
        tabManager.browse(to: url.absoluteString, in: tab)
        guard disposition != .backgroundTab else {
            return
        }
        
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
        tabBar.setPendingExpansion(at: tabIndex)
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab) { [weak self] in
            self?.tabManager.selectTab(at: tabIndex, mode: mode)
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
