//
//  BrowserViewController+AddressBar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

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
        tabManager.reloadOrStopSelectedTab()
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
    
    func selectTabFromGesture(at index: Int, mode: TabMode) {
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func createTabForSwipe() -> Int {
        return tabManager.createTab(selecting: true)
    }
    
    func setPendingTabExpansion(at index: Int?) {
        tabBar.setPendingExpansion(at: index)
    }
    
    func presentTabOverviewFromGesture(animated: Bool) {
        setTabOverviewVisible(true, animated: animated)
    }
    
    // MARK: - Website Actions
    
    private func presentWebsiteSettings() {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              let settingsController = SiteSettingsViewController(url: url, session: selectedTab.session) else {
            return
        }
        
        let navigationController = UINavigationController(rootViewController: settingsController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    private func presentBookmarkEditor(addToFavorites: Bool) {
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
        
        let navigationController = UINavigationController(rootViewController: bookmarkController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}
