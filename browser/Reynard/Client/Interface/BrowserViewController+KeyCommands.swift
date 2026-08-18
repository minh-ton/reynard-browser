//
//  BrowserViewController+KeyCommands.swift
//  Reynard
//
//  Created by Minh Ton on 15/8/26.
//

import GeckoView
import UIKit

extension BrowserViewController {
    @objc func newTabKeyCommand(_ sender: UIKeyCommand) {
        createNewTab()
    }
    
    @objc func newPrivateTabKeyCommand(_ sender: UIKeyCommand) {
        createNewTab(mode: .private)
    }
    
    @objc func focusAddressBarKeyCommand(_ sender: UIKeyCommand) {
        if tabOverview.isPresented || tabOverview.isTransitionRunning {
            setTabOverviewVisible(false, animated: false)
        }
        _ = browserChrome.addressBar.becomeFirstResponder()
    }
    
    @objc func closeTabKeyCommand(_ sender: UIKeyCommand) {
        closeTab()
    }
    
    @objc func findInPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        if tabOverview.isPresented || tabOverview.isTransitionRunning {
            setTabOverviewVisible(false, animated: false)
        }
        browserChrome.showActionBar(.findInPage, animated: true)
    }
    
    @objc func reloadPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage,
              let session = tabManager.selectedTab?.session else {
            return
        }
        if session.isOpen() {
            session.reload()
        } else {
            reloadTerminatedTab()
        }
    }
    
    @objc func hardReloadPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage,
              let session = tabManager.selectedTab?.session else {
            return
        }
        if session.isOpen() {
            session.reload(flags: GeckoSessionLoadFlags.bypassCache)
        } else {
            reloadTerminatedTab()
        }
    }
    
    @objc func zoomInKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        browserChrome.onPageZoomIn?()
    }
    
    @objc func zoomOutKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        browserChrome.onPageZoomOut?()
    }
    
    @objc func actualSizeKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        setSelectedPageZoomLevel(PageZoomLevels.defaultLevel)
    }
    
    @objc func showHistoryKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTabMode == .regular else {
            return
        }
        toggleLibrary(section: .history)
    }
    
    @objc func goBackKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTab?.state.navigationState.canGoBack == true else {
            return
        }
        browserChrome.onBack?()
    }
    
    @objc func goForwardKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTab?.state.navigationState.canGoForward == true else {
            return
        }
        browserChrome.onForward?()
    }
    
    @objc func showBookmarksKeyCommand(_ sender: UIKeyCommand) {
        toggleLibrary(section: .bookmarks)
    }
    
    @objc func addBookmarkKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        presentBookmarkEditor(addToFavorites: false)
    }
    
    @objc func editBookmarksKeyCommand(_ sender: UIKeyCommand) {
        presentLibrary(initialSection: .bookmarks, startsEditingBookmarks: true)
    }
    
    @objc func showDownloadsKeyCommand(_ sender: UIKeyCommand) {
        toggleLibrary(section: .downloads)
    }
    
    @objc func showTabOverviewKeyCommand(_ sender: UIKeyCommand) {
        guard !tabOverview.isTransitionRunning else {
            return
        }
        setTabOverviewVisible(!tabOverview.isPresented, animated: true)
    }
    
    @objc func previousTabKeyCommand(_ sender: UIKeyCommand) {
        selectRelativeTab(offset: -1)
    }
    
    @objc func nextTabKeyCommand(_ sender: UIKeyCommand) {
        selectRelativeTab(offset: 1)
    }
    
    private func selectRelativeTab(offset: Int) {
        let tabs = tabManager.activeTabs
        guard tabs.count > 1 else {
            return
        }
        let index = (tabManager.selectedTabIndex + offset + tabs.count) % tabs.count
        selectTab(at: index, mode: tabManager.selectedTabMode)
    }
    
    @objc func selectTabKeyCommand(_ sender: UIKeyCommand) {
        guard let number = (sender.propertyList as? NSNumber)?.intValue else {
            return
        }
        let tabs = tabManager.activeTabs
        let index = number == 9 ? tabs.indices.last : tabs.indices.contains(number - 1) ? number - 1 : nil
        guard let index,
              index != tabManager.selectedTabIndex else {
            return
        }
        selectTab(at: index, mode: tabManager.selectedTabMode)
    }
    
    @objc func reopenLastClosedTabKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTabMode == .regular,
              let closedTab = TabManagementStore.shared.recentlyClosedTabs(limit: 1).first else {
            return
        }
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        _ = tabManager.restoreRecentlyClosedTab(id: closedTab.id)
    }
    
    @objc func toggleSidebarKeyCommand(_ sender: UIKeyCommand) {
        browserChrome.onSidebar?()
    }
    
    @objc func closeOtherTabsKeyCommand(_ sender: UIKeyCommand) {
        let mode = tabManager.selectedTabMode
        let tabs = tabManager.activeTabs
        guard tabs.count > 1,
              let selectedTabID = tabManager.selectedTab?.id else {
            return
        }
        
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        tabs.indices.reversed().forEach { index in
            if tabs[index].id != selectedTabID {
                tabManager.removeTab(at: index, mode: mode)
            }
        }
    }
    
    private var hasSelectedWebPage: Bool {
        guard let urlString = tabManager.selectedTab?.url else {
            return false
        }
        return URL(string: urlString)?.host != nil
    }
}
