//
//  BrowserViewController+TabPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: TabBarDataSource, TabOverviewDataSource, TabOverviewDelegate, TabOverviewPresentationContext {
    // MARK: - Shared Tab Data
    
    var tabs: [Tab] {
        return tabManager.activeTabs
    }
    
    var selectedTabID: UUID? {
        return tabManager.selectedTab?.id
    }
    
    var selectedMode: TabMode {
        return tabManager.selectedTabMode
    }
    
    func selectTab(at index: Int, mode: TabMode) {
        browserChrome.dismissActionBar(animated: false)
        toolbarController.reset()
        guard let tab = tabManager.tabs(for: mode)[safe: index] else {
            return
        }
        
        if mode == tabManager.selectedTabMode,
           tab !== tabManager.selectedTab {
            if tabOverview.isPresented || tabOverview.isTransitionRunning {
                tabManager.selectTab(tab)
                return
            }
            
            captureThumbnail(for: tabManager.selectedTab)
            tabManager.selectTab(tab)
            return
        }
        tabManager.selectTab(tab)
    }
    
    func closeTab(at index: Int, mode: TabMode) {
        toolbarController.reset()
        guard let tab = tabManager.tabs(for: mode)[safe: index] else {
            return
        }
        
        let isTabOverviewActive = tabOverview.isPresented || tabOverview.isTransitionRunning
        if isTabOverviewActive,
           tabOverview.mode == .regularTabs,
           mode == .regular,
           tabManager.regularTabs.count == 1 {
            tabOverview.prepareNextTabChangesWithoutAnimation()
            tabManager.removeTab(tab, behavior: .none)
            createTabFromOverview(mode: .regular)
            return
        }
        
        let behavior: TabRemovalBehavior = isTabOverviewActive ? .none : .recent
        tabManager.removeTab(tab, behavior: behavior)
    }
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode) {
        toolbarController.reset()
        tabManager.moveTab(from: sourceIndex, to: destinationIndex, mode: mode)
    }
    
    // MARK: - TabOverviewDataSource
    
    var regularTabs: [Tab] {
        return tabManager.regularTabs
    }
    
    var privateTabs: [Tab] {
        return tabManager.privateTabs
    }
    
    var selectedIndex: Int {
        return tabManager.selectedTabIndex
    }
    
    func captureThumbnail(forTabAt index: Int, mode: TabMode) -> UIImage? {
        return captureThumbnail(for: tabManager.tabs(for: mode)[safe: index])
    }
    
    // MARK: - TabOverviewDelegate
    
    func tabOverviewDidRequestClearTabs(_ tabOverview: TabOverview) {
        clearTabsForCurrentOverviewMode()
    }
    
    func tabOverviewDidRequestClearTabsOlderThan(_ tabOverview: TabOverview, age: TabOverviewClearTabsMenu.Age) {
        clearTabsOlderThan(age)
    }
    
    func tabOverviewDidRequestNewTab(_ tabOverview: TabOverview) {
        createNewTab()
    }
    
    func tabOverviewDidRequestDone(_ tabOverview: TabOverview) {
        dismissTabOverviewSelectingMostRecentTabIfNeeded()
    }
    
    func tabOverviewDidRequestDismiss(_ tabOverview: TabOverview, animated: Bool) {
        setTabOverviewVisible(false, animated: animated)
    }
    
    func tabOverviewDidRequestClearPendingTabExpansion(_ tabOverview: TabOverview) {
        tabBar.setPendingExpansion(to: nil)
    }
    
    // MARK: - TabOverviewPresentationContext
    
    var containerView: UIView {
        return view
    }
    
    func setSearchFocused(_ focused: Bool, animated: Bool) {
        searchOverlayCoordinator.setFocused(focused, animated: animated)
    }
    
    func endEditing() {
        view.endEditing(true)
    }
    
    func updateLayout(animated: Bool, duration: TimeInterval) {
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func prepareTabOverviewPresentation() {
        homepageOverlayCoordinator.updatePresentation(animated: false)
        view.layoutIfNeeded()
    }
    
    func tabOverviewDidFinishDismissal() {
        toolbarController.unlock(for: .tabOverview)
        requestHomepageAddressBarFocus()
        requestContentKeyboardFocus()
    }
    
    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        if visible {
            toolbarController.lock(for: .tabOverview)
            if browserChrome.addressBar.performAfterTransition({ [weak self] in
                self?.setTabOverviewVisible(true, animated: animated)
            }) {
                return
            }
            
            browserChrome.dismissActionBar(animated: false)
            dismissAddressBarEditingAndOverlays()
            contentView.resetFocusedInputRelocation()
            homepageOverlayCoordinator.tabOverviewWillPresent()
            searchOverlayCoordinator.tabOverviewWillPresent()
        }
        tabOverview.setPresented(visible, animated: animated)
        if !visible {
            homepageOverlayCoordinator.updatePresentation(animated: animated)
        }
    }
    
    // MARK: - Tab Overview Actions
    
    private func dismissTabOverviewSelectingMostRecentTabIfNeeded() {
        if tabOverview.isPresented {
            let mode = tabOverview.mode.tabMode
            let tabs = tabManager.tabs(for: mode)
            guard !tabs.isEmpty else {
                return
            }
            
            if tabManager.selectedTabMode != mode,
               let tab = tabs.max(by: { $0.state.selectionOrder < $1.state.selectionOrder }) {
                tabManager.selectTab(tab)
            }
            scrollTabOverviewToTab(at: tabManager.selectedTabIndex)
            tabOverview.prepareDismissSelectionForCurrentTab()
        }
        setTabOverviewVisible(false, animated: true)
    }
    
    func scrollTabOverviewToTab(at index: Int) {
        guard let itemIndex = tabOverview.itemIndex(forTabAt: index) else {
            return
        }
        
        let collectionView = tabOverview.currentCollectionView()
        collectionView.scrollToItem(
            at: IndexPath(item: itemIndex, section: 0),
            at: .centeredVertically,
            animated: false
        )
        collectionView.layoutIfNeeded()
    }
    
    private func clearTabsForCurrentOverviewMode() {
        tabBar.setPendingExpansion(to: nil)
        
        guard tabOverview.isPresented else {
            tabManager.removeAllTabs(mode: nil)
            return
        }
        
        let mode = tabOverview.mode.tabMode
        guard mode == .regular else {
            tabManager.removeAllTabs(mode: mode)
            return
        }
        
        if !tabManager.regularTabs.isEmpty {
            tabOverview.prepareNextTabChangesWithoutAnimation()
        }
        tabManager.removeAllTabs(mode: .regular)
        createTabFromOverview(mode: .regular)
    }
    
    private func clearTabsOlderThan(_ age: TabOverviewClearTabsMenu.Age) {
        guard let cutoffDate = age.cutoffDate() else {
            return
        }
        
        tabBar.setPendingExpansion(to: nil)
        let mode = tabOverview.mode.tabMode
        let tabs = tabManager.tabs(for: mode)
        let oldTabIDs = TabManagementStore.shared.tabIDs(olderThan: cutoffDate, isPrivate: mode == .private)
        let oldTabs = tabs.filter { oldTabIDs.contains($0.id) }
        guard !oldTabs.isEmpty else {
            return
        }
        
        if oldTabs.count == tabs.count {
            clearTabsForCurrentOverviewMode()
            return
        }
        
        oldTabs.reversed().forEach { tabManager.removeTab($0, behavior: .none) }
    }
    
    func createTabFromOverview(mode: TabMode) {
        tabOverview.holdTabChanges()
        let tab = tabManager.createTab(
            selecting: true,
            target: .end,
            mode: mode
        )
        applyNewTabDisplayOption(to: tab) { [weak self] previewImage in
            guard let self else {
                return
            }
            
            self.tabOverview.releaseTabChanges()
            guard self.tabManager.selectedTab === tab else {
                return
            }
            
            self.tabOverview.prepareDismissSelection(to: self.tabManager.selectedTabIndex, mode: mode, previewImage: previewImage)
            self.scrollTabOverviewToTab(at: self.tabManager.selectedTabIndex)
            self.tabBar.setPendingExpansion(to: tab)
            self.setTabOverviewVisible(false, animated: true)
        }
    }
}
