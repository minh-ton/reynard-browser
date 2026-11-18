//
//  BrowserViewController+ContentOverlay.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: ContentOverlayCoordinatorHost, SearchOverlayCoordinatorDelegate, HomepageOverlayCoordinatorDelegate, AddressBarSearchDelegate {
    // MARK: - Content Overlay Host
    
    var overlayParentViewController: UIViewController {
        return self
    }
    
    // MARK: - Search Overlay Delegate
    
    var searchLayout: BrowserLayout {
        return browserLayout
    }
    
    var searchChrome: BrowserChrome {
        return browserChrome
    }
    
    var searchContentView: ContentView {
        return contentView
    }
    
    var searchSelectedTabMode: TabMode {
        return tabManager.selectedTabMode
    }
    
    var searchSelectedTabID: UUID? {
        return tabManager.selectedTab?.id
    }
    
    var searchActiveTabs: [Tab] {
        return tabManager.activeTabs
    }
    
    var isSearchAddressBarEditing: Bool {
        return browserChrome.isAddressBarEditing
    }
    
    var searchWidthMode: SearchWidthMode {
        return isHalfSplitScreenOrSmaller ? .halfSplitScreenOrSmaller : .standard
    }
    
    func refreshSearchAddressBar() {
        refreshAddressBar()
    }
    
    func updateSearchLayout(animated: Bool, duration: TimeInterval) {
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func browseSearchTerm(_ term: String) {
        tabManager.browse(to: term)
    }
    
    func selectSearchTab(at index: Int, mode: TabMode) {
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func endSearchEditing() {
        view.endEditing(true)
        requestContentKeyboardFocus()
    }
    
    // MARK: - Homepage Overlay Delegate
    
    var homepageLayout: BrowserLayout {
        return browserLayout
    }
    
    var homepageGridWidth: HomepageGridWidth {
        if isHalfSplitScreenOrSmaller {
            return .fourColumn
        }
        if isSidebarOverlayLayout {
            return .sixColumn
        }
        return .eightColumn
    }
    
    var homepageSelectedTab: Tab? {
        return tabManager.selectedTab
    }
    
    var isHomepageTabOverviewPresented: Bool {
        return tabOverview.isPresented
    }
    
    var isHomepageShowingFullscreenMedia: Bool {
        return isShowingFullscreenMedia
    }
    
    var homepageChrome: BrowserChrome {
        return browserChrome
    }
    
    var homepageContentView: ContentView {
        return contentView
    }
    
    var homepageTabActions: ContextMenuTabActions {
        return ContextMenuTabActions(tabManager: tabManager, sessionManager: sessionManager)
    }
    
    func openURLFromHomepage(_ url: URL, disposition: TabOpenDisposition) {
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
        
        let tabIndex = tabManager.createTab(selecting: disposition != .backgroundTab, target: target, mode: mode)
        let tabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard let tab = tabs[safe: tabIndex] else {
            return
        }
        
        tabManager.browse(to: url.absoluteString, in: tab)
        guard disposition != .backgroundTab else {
            return
        }
        
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode) { [weak self] _ in
            guard let self else {
                return
            }
            
            self.tabBar.setPendingExpansion(at: tabIndex)
            self.browserChrome.animateAutomaticTabTransition(to: tab) { [weak self] in
                self?.tabManager.selectTab(at: tabIndex, mode: mode)
            }
        }
    }
    
    func shareURLFromHomepage(_ url: URL, sourceView: UIView) {
        presentShareSheet(
            items: [url],
            sourceView: sourceView,
            sourceRect: sourceView.bounds
        )
    }
    
    func openSettingsFromHomepage() {
        if browserLayout.interfaceIdiom == .pad,
           browserLayout.chromeMode == .pad {
            sidebarCoordinator.showSection(.settings)
            return
        }
        presentLibrary(initialSection: .settings)
    }
    
    func restoreClosedTabFromHomepage(id: UUID) -> Bool {
        return tabManager.restoreRecentlyClosedTab(id: id)
    }
    
    func endHomepageEditing() {
        view.endEditing(true)
        requestContentKeyboardFocus()
    }
    
    func updateHomepageLayout(animated: Bool, duration: TimeInterval) {
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    // MARK: - Address Bar Search Delegate
    
    func addressBarDidSubmit(_ searchTerm: String) {
        homepageOverlayCoordinator.addressBarDidSubmit(searchTerm)
        searchOverlayCoordinator.addressBarDidSubmit(searchTerm)
    }
    
    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        homepageOverlayCoordinator.addressBarDidTapDismiss(addressBar)
        searchOverlayCoordinator.addressBarDidTapDismiss(addressBar)
    }
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        // Like Safari: a sidebar floating over the page steps aside while the
        // user types an address, so the search panel has the whole window.
        if let sidebar = splitViewController as? SidebarViewController,
           sidebar.isFloatingOverContent {
            sidebar.setVisible(false)
        }
        toolbarController.lock(for: .addressBarEditing)
        homepageOverlayCoordinator.addressBarDidBeginEditing(addressBar)
        searchOverlayCoordinator.addressBarDidBeginEditing(addressBar)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        homepageOverlayCoordinator.addressBarDidEndEditing(addressBar)
        searchOverlayCoordinator.addressBarDidEndEditing(addressBar)
        toolbarController.unlock(for: .addressBarEditing)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool) {
        searchOverlayCoordinator.addressBar(addressBar, didChangeText: text, previousText: previousText, isDelete: isDelete)
        homepageOverlayCoordinator.addressBar(addressBar, didChangeText: text, previousText: previousText, isDelete: isDelete)
    }
    
    func addressBarCanNavigateSuggestions(_ addressBar: AddressBar) -> Bool {
        return searchOverlayCoordinator.canNavigateSuggestions
    }
    
    func addressBar(_ addressBar: AddressBar, didMoveSuggestionSelectionBy offset: Int) {
        searchOverlayCoordinator.moveSuggestionSelection(by: offset)
    }
    
    func addressBarDidRequestSubmitSelectedSuggestion(_ addressBar: AddressBar) -> Bool {
        return searchOverlayCoordinator.submitSelectedSuggestion()
    }
}
