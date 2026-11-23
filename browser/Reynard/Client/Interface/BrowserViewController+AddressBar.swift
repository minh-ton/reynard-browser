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
        let hasDisplayText = displayText?.isEmpty == false
        let hasSelectedURL = selectedURL?.isEmpty == false
        browserChrome.setAddressBarText(
            hasDisplayText ? displayText : selectedURL,
            locationText: selectedURL,
            locationTitle: selectedTab?.title,
            showsBarMenu: !hasDisplayText && hasSelectedURL,
            isErrorPage: selectedTab?.state.loadError != nil
        )
        
        browserChrome.addressBar.setLoadingProgress(
            selectedTab?.state.loadingState.progress ?? 0,
            isLoading: selectedTab?.state.loadingState.isLoading ?? false
        )
        
        addonCoordinator.prepareMenuIcons()
        let usesDesktopWebsite = selectedTab.flatMap { tab in
            tab.url.flatMap { url in
                sessionManager.isDesktopMode(for: url, tabID: tab.id)
            }
        }
        browserChrome.addressBar.updateMenu(
            url: selectedURL,
            usesDesktopWebsite: usesDesktopWebsite,
            readerMode: selectedTab?.state.readerMode ?? ReaderModeState()
        )
        
        refreshAddressBarAudioButton()
    }
    
    func refreshAddressBarAudioButton() {
        let selectedTab = tabManager.selectedTab
        let playingTabs = tabsPlayingAudio
        browserChrome.addressBar.updateAudioButton(
            isVisible: !playingTabs.isEmpty,
            isMuted: selectedTab?.isMuted == true ||
            (!playingTabs.isEmpty && playingTabs.allSatisfy(\.isMuted))
        )
    }
    
    private var tabsPlayingAudio: [Tab] {
        return tabManager.activeTabs.filter { $0.state.isPlayingAudio }
    }
    
    // MARK: - AddressBarDelegate
    
    func addressBarAudioMenuState(_ addressBar: AddressBar) -> AddressBarMenu.AudioState? {
        let playingTabs = tabsPlayingAudio
        guard !playingTabs.isEmpty else {
            return nil
        }
        
        let selectedTab = tabManager.selectedTab
        return AddressBarMenu.AudioState(
            playingTabs: playingTabs.map { tab in
                let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return AddressBarMenu.AudioTabItem(
                    id: tab.id,
                    title: title.isEmpty ? tab.url ?? NSLocalizedString("Untitled", comment: "") : title,
                    favicon: tab.favicon,
                    isMuted: tab.isMuted
                )
            },
            selectedTabID: selectedTab?.id,
            isSelectedTabMuted: selectedTab?.isMuted ?? false
        )
    }
    
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
    
    func addressBar(_ addressBar: AddressBar, didSelectAudioAction action: AddressBarMenu.AudioAction) {
        switch action {
        case let .selectTab(tabID):
            guard let tab = tabManager.activeTabs.first(where: { $0.id == tabID }) else {
                return
            }
            
            tabManager.selectTab(tab)
        case let .setMuted(tabID, muted):
            tabManager.setMuted(muted, for: tabID)
        case let .muteOtherTabs(excluding: tabID):
            tabManager.muteOtherPlayingTabs(excluding: tabID)
        }
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
        showFindInPage()
    }
    
    func addressBarDidRequestReader(_ addressBar: AddressBar) {
        showReader()
    }
    
    func addressBarDidRequestPageZoom(_ addressBar: AddressBar) {
        showPageZoom()
    }
    
    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar) {
        guard tabManager.changeWebsiteModeForSelectedTab() else {
            return
        }
        
        refreshAddressBar()
    }
    
    func addressBarDidRequestHideToolbar(_ addressBar: AddressBar) {
        toolbarController.collapseUntilReset()
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
        
        return selectedTab.shareableURL
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
    
    func pageBackgroundColor(for tab: Tab) -> UIColor {
        return sessionManager.pageBackgroundColor(for: tab.session)
    }
    
    func selectTabFromGesture(at index: Int, mode: TabMode) {
        guard let tab = tabManager.tabs(for: mode)[safe: index] else {
            return
        }
        
        tabManager.selectTab(tab)
    }
    
    func createTabForSwipe() -> Tab {
        captureThumbnail(for: tabManager.selectedTab)
        let tab = tabManager.createTab(selecting: false)
        
        if Prefs.NewTabSettings.newTabDisplayOption == .customURL {
            applyNewTabDisplayOption(to: tab)
        } else {
            captureThumbnail(for: tab)
        }
        
        return tab
    }
    
    func setPendingTabExpansion(to tab: Tab?) {
        tabBar.setPendingExpansion(to: tab)
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
        captureThumbnail(for: tabManager.selectedTab)
    }
    
    func addressBarTransitionDidEnd() {
        toolbarController.unlock(for: .addressBarTransition)
    }
}
