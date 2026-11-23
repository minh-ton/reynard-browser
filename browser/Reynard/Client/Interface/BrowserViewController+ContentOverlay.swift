//
//  BrowserViewController+ContentOverlay.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: SearchOverlayCoordinatorDelegate, HomepageOverlayCoordinatorDelegate, AddressBarSearchDelegate {
    // MARK: - Search Overlay Delegate
    
    var searchLayout: BrowserLayout {
        return browserLayout
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
    
    var isHomepageTabOverviewPresented: Bool {
        return tabOverview.isPresented
    }
    
    var isHomepageShowingFullscreenMedia: Bool {
        return isShowingFullscreenMedia
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
        
        let tab = tabManager.createTab(selecting: disposition != .backgroundTab, target: target, mode: mode)
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
