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
    
    func captureSourceTabThumbnail(completion: @escaping () -> Void) {
        let selectedIndex = tabManager.selectedTabIndex
        let selectedMode = tabManager.selectedTabMode
        captureThumbnail(forTabAt: selectedIndex, mode: selectedMode) { _ in
            completion()
        }
    }
    
    func contextMenuOpenLink(_ url: URL, disposition: TabOpenDisposition) {
        let mode: TabMode
        let target: TabInsertionTarget
        
        switch disposition {
        case .currentTab:
            tabManager.browse(to: url.absoluteString)
            return
        case .newTab:
            mode = tabManager.selectedTabMode
            target = .afterSelected
        case .newPrivateTab:
            mode = .private
            target = tabManager.selectedTabMode == .private ? .afterSelected : .end
        }
        
        let tabIndex = tabManager.createTab(selecting: false, target: target, mode: mode)
        let tabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard let tab = tabs[safe: tabIndex] else {
            return
        }
        
        tabManager.browse(to: url.absoluteString, in: tab)
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode) { [weak self] _ in
            guard let self else {
                return
            }
            
            self.tabBar.setPendingExpansion(at: tabIndex)
            self.browserChrome.animateAutomaticNewTabTransition(to: tab) { [weak self] in
                self?.tabManager.selectTab(at: tabIndex, mode: mode)
            }
        }
    }
    
    func contextMenuShareLink(_ url: URL) {
        presentShareSheet(url: url.absoluteString)
    }
    
    func contextMenuRestoreInteraction(for session: GeckoSession) {
        contentView.restoreInteraction(for: session)
        sessionManager.activate(session)
    }
}
