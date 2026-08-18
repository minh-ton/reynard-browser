//
//  BrowserViewController+AddressBar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit
import GeckoView

extension BrowserViewController: AddressBarDelegate, AddressBarGestureDelegate {
    // MARK: - Address Bar State
    
    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let displayText: String?
        if case let .pending(text) = selectedTab?.state.displayState {
            displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            displayText = nil
        }
        
        let selectedURL = selectedTab?.url
        browserChrome.setAddressBarText(
            displayText?.isEmpty == false ? displayText : selectedURL,
            locationText: selectedURL,
            locationTitle: selectedTab?.title,
            showsBarMenu: displayText?.isEmpty != false && selectedURL?.isEmpty == false
        )
        browserChrome.setAddressBarLoadingProgress(
            selectedTab?.state.loadingState.progress ?? 0,
            isLoading: selectedTab?.state.loadingState.isLoading ?? false
        )
        addonCoordinator.prepareMenuIcons()
        let usesDesktopWebsite = selectedTab.flatMap { tab in
            tab.url.flatMap { url in
                sessionManager.isDesktopMode(for: url, tabID: tab.id)
            }
        }
        browserChrome.updateAddressBarMenu(
            url: selectedURL,
            usesDesktopWebsite: usesDesktopWebsite
        )
    }
    
    // MARK: - AddressBarDelegate
    
    func addressBarDidRequestReloadOrStop(_ addressBar: AddressBar) {
        if tabManager.selectedTab?.session.isOpen() == false {
            reloadTerminatedTab()
            return
        }
        
        tabManager.reloadOrStopSelectedTab()
    }
    
    func addressBarDidRequestHardReload(_ addressBar: AddressBar) {
        if tabManager.selectedTab?.session.isOpen() == false {
            reloadTerminatedTab()
            return
        }
        
        tabManager.hardReloadSelectedTab()
    }
    
    func addressBarAddonItems(_ addressBar: AddressBar) -> [AddressBarMenu.AddonItem] {
        addonCoordinator.currentSiteMenuItems().map { item in
            AddressBarMenu.AddonItem(
                menuItem: item,
                image: addonCoordinator.menuIcon(for: item.addon)
            )
        }
    }
    
    func addressBar(_ addressBar: AddressBar, didSelectAddon item: AddonMenuItem) {
        addonCoordinator.activateMenuItem(item)
    }
    
    func addressBarDidRequestFindInPage(_ addressBar: AddressBar) {
        guard tabManager.selectedTab != nil else {
            return
        }
        
        browserChrome.showActionBar(.findInPage, animated: true)
    }
    
    func addressBarDidRequestPageZoom(_ addressBar: AddressBar) {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }
        
        browserChrome.setPageZoomLevel(selectedTab.session.settings.pageZoom.level)
        browserChrome.showActionBar(.pageZoom, animated: true)
    }
    
    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar) {
        guard tabManager.changeWebsiteModeForSelectedTab() else {
            return
        }
        
        refreshAddressBar()
    }
    
    func addressBarDidRequestWebsiteSettings(_ addressBar: AddressBar) {
        presentWebsiteSettings()
    }
    
    func addressBar(_ addressBar: AddressBar, didRequestBookmarkInFavorites favorites: Bool) {
        presentBookmarkEditor(addToFavorites: favorites)
    }
    
    func addressBarShareableURL(_ addressBar: AddressBar) -> URL? {
        guard let selectedTab = tabManager.selectedTab else {
            return nil
        }
        
        return tabManager.shareableURL(for: selectedTab)
    }
    
    func addressBarTabCount(_ addressBar: AddressBar) -> Int {
        return tabManager.activeTabs.count
    }
    
    func addressBarDidRequestCloseThisTab(_ addressBar: AddressBar) {
        closeTab()
    }
    
    func addressBarDidRequestCloseAllTabs(_ addressBar: AddressBar) {
        closeAllTabs()
    }
    
    func addressBar(
        _ addressBar: AddressBar,
        didRequestShareLink url: URL
    ) {
        presentShareSheet(
            items: [url],
            sourceView: addressBar,
            sourceRect: addressBar.bounds
        )
    }
    
    // MARK: - AddressBarGestureDelegate
    
    var transitionContainerView: UIView {
        return view
    }
    
    var transitionContentView: ContentView {
        return contentView
    }
    
    var chromeMode: BrowserChromeMode {
        return browserLayout.chromeMode
    }
    
    var isSearchFocused: Bool {
        return searchOverlayCoordinator.isFocused
    }
    
    var isTabOverviewPresented: Bool {
        return tabOverview.isPresented
    }
    
    var isTabOverviewTransitionRunning: Bool {
        return tabOverview.isTransitionRunning
    }
    
    var selectedTabIndex: Int {
        return tabManager.selectedTabIndex
    }
    
    var selectedTabMode: TabMode {
        return tabManager.selectedTabMode
    }
    
    var activeTabs: [Tab] {
        return tabManager.activeTabs
    }
    
    func pageBackgroundColor(for tab: Tab) -> UIColor {
        return sessionManager.pageBackgroundColor(for: tab.session)
    }
    
    func selectTabFromGesture(at index: Int, mode: TabMode) {
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func createTabForSwipe() -> Int {
        let mode = tabManager.selectedTabMode
        captureTabThumbnailIfNeeded()
        homepageOverlayCoordinator.prepareHomepageForNewTab(mode: mode)
        let index = tabManager.createTab(selecting: false)
        
        if Prefs.NewTabSettings.newTabDisplayOption == .customURL {
            applyNewTabDisplayOption(toTabAt: index)
            return index
        }
        
        if let tab = tabManager.activeTabs[safe: index],
           let previewImage = homepageOverlayCoordinator.previewImage(for: tab) {
            tabManager.updateThumbnail(previewImage, forTabAt: index, mode: mode)
        }
        
        return index
    }
    
    func setPendingTabExpansion(at index: Int?) {
        tabBar.setPendingExpansion(at: index)
    }
    
    func presentTabOverviewFromGesture(animated: Bool) {
        setTabOverviewVisible(true, animated: animated)
    }
    
    func addressBarTransitionWillBegin(prepareForGesture: Bool) {
        toolbarController.lock(for: .addressBarTransition)
        guard prepareForGesture else {
            return
        }
        browserChrome.dismissActionBar(animated: false)
        captureTabThumbnailIfNeeded()
    }
    
    func addressBarTransitionDidEnd() {
        toolbarController.unlock(for: .addressBarTransition)
    }
    
    private func captureTabThumbnailIfNeeded() {
        if let tab = tabManager.activeTabs[safe: tabManager.selectedTabIndex],
           homepageOverlayCoordinator.needsHomepageThumbnail(for: tab) {
            if let thumbnail = homepageOverlayCoordinator.previewImage(for: tab) {
                tabManager.updateThumbnail(thumbnail, forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
            }
            return
        }
        
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
    }
    
    func storedContentPreview(from tab: Tab) -> UIImage? {
        guard homepageOverlayCoordinator.needsHomepageThumbnail(for: tab) else {
            return nil
        }
        
        return tab.thumbnail
    }
    
    // MARK: - Page Zoom
    
    func setSelectedPageZoomToPreviousLevel() {
        setSelectedPageZoomLevel(browserChrome.previousPageZoomLevel())
    }
    
    func setSelectedPageZoomToNextLevel() {
        setSelectedPageZoomLevel(browserChrome.nextPageZoomLevel())
    }
    
    func setSelectedPageZoomLevel(_ level: Int) {
        guard let selectedTab = tabManager.selectedTab,
              let url = selectedTab.url else {
            return
        }
        
        browserChrome.setPageZoomLevel(level)
        sessionManager.setPageZoom(level, of: selectedTab.session, for: url, tabID: selectedTab.id)
    }
    
    // MARK: - Website Actions
    
    private func presentWebsiteSettings() {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              let settingsController = SiteSettingsViewController(
                url: url,
                session: selectedTab.session,
                trackingProtection: sessionManager.trackingProtection
              ) else {
            return
        }
        
        presentContentModal(settingsController)
    }
    
    func presentBookmarkEditor(addToFavorites: Bool) {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString) else {
            return
        }
        
        let title = selectedTab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmarkController: EditBookmarkViewController
        if addToFavorites {
            bookmarkController = EditBookmarkViewController(
                title: title,
                url: url,
                limitsToFavorites: true
            )
        } else if let bookmark = BookmarkStore.shared.bookmark(savedFor: url) {
            bookmarkController = EditBookmarkViewController(bookmark: bookmark)
        } else {
            bookmarkController = EditBookmarkViewController(title: title, url: url)
        }
        
        presentContentModal(bookmarkController)
    }
}
