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
            showsBarMenu: displayText?.isEmpty != false && selectedURL?.isEmpty == false,
            isErrorPage: selectedTab?.state.loadError != nil
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
            usesDesktopWebsite: usesDesktopWebsite,
            readerMode: selectedTab?.state.readerMode ?? ReaderModeState()
        )
        
        refreshAddressBarAudioButton()
    }
    
    func refreshAddressBarAudioButton() {
        let selectedTab = tabManager.selectedTab
        let playingTabs = tabsPlayingAudio
        browserChrome.updateAddressBarAudioButton(
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
            guard let index = tabManager.activeTabs.firstIndex(where: { $0.id == tabID }) else {
                return
            }
            tabManager.selectTab(at: index, mode: tabManager.selectedTabMode)
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
        guard tabManager.selectedTab != nil else {
            return
        }
        
        browserChrome.showActionBar(.findInPage(), animated: true)
    }
    
    func addressBarDidRequestReader(_ addressBar: AddressBar) {
        guard let tab = tabManager.selectedTab else { return }
        guard tab.state.readerMode.isActive else {
            _ = tabManager.readerMode.enter(in: tab)
            return
        }
        
        let controller = ReaderSettingsViewController(
            tabID: tab.id,
            tabManager: tabManager,
            readerMode: tabManager.readerMode
        )
        controller.onFindInPage = { [weak self] in
            guard let self, self.tabManager.selectedTab === tab else { return }
            self.browserChrome.showActionBar(.findInPage(), animated: true)
        }
        controller.configurePresentation(asPopover: browserLayout.chromeMode == .pad)
        if controller.modalPresentationStyle == .pageSheet {
            controller.onVisibilityChanged = { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.toolbarController.collapseBottomToolbar()
                } else if !self.browserChrome.isShowingFindInPage {
                    self.toolbarController.restoreBottomToolbar()
                }
            }
        }
        if let popover = controller.popoverPresentationController {
            let sourceButton = browserChrome.addressBarButton
            popover.sourceView = sourceButton
            popover.sourceRect = sourceButton.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = controller
        }
        present(controller, animated: true)
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
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: mode)
        let index = tabManager.createTab(selecting: false)
        applyNewTabDisplayOption(toTabAt: index, mode: mode)
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
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
    }
    
    func addressBarTransitionDidEnd() {
        toolbarController.unlock(for: .addressBarTransition)
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
