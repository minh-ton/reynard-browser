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
    
    func browseHomepageFavorite(_ favorite: BookmarkSnapshot) {
        tabManager.browse(to: favorite.url.absoluteString)
    }
    
    func endHomepageEditing() {
        view.endEditing(true)
    }
    
    func updateHomepageLayout(animated: Bool, duration: TimeInterval) {
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func browseHomepagePerformanceExternalURL(_ url: URL) {
        tabManager.browse(to: url.absoluteString)
    }
    
    func openHomepagePerformanceSettings() {
        if browserLayout.interfaceIdiom == .pad,
           browserLayout.chromeMode == .pad {
            sidebarCoordinator.showSection(.settings)
            return
        }
        presentLibrary(initialSection: .settings)
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
        homepageOverlayCoordinator.addressBarDidBeginEditing(addressBar)
        searchOverlayCoordinator.addressBarDidBeginEditing(addressBar)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        homepageOverlayCoordinator.addressBarDidEndEditing(addressBar)
        searchOverlayCoordinator.addressBarDidEndEditing(addressBar)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool) {
        searchOverlayCoordinator.addressBar(addressBar, didChangeText: text, previousText: previousText, isDelete: isDelete)
        homepageOverlayCoordinator.addressBar(addressBar, didChangeText: text, previousText: previousText, isDelete: isDelete)
    }
}
