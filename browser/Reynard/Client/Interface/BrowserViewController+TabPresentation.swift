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
        if mode == tabManager.selectedTabMode,
           index != tabManager.selectedTabIndex {
            if tabOverview.isPresented || tabOverview.isTransitionRunning {
                tabManager.selectTab(at: index, mode: mode)
                return
            }
            
            captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode) { [weak self] _ in
                self?.tabManager.selectTab(at: index, mode: mode)
            }
            return
        }
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func closeTab(at index: Int, mode: TabMode) {
        if (tabOverview.isPresented || tabOverview.isTransitionRunning),
           tabOverview.mode == .regularTabs,
           mode == .regular,
           tabManager.regularTabs.count == 1 {
            tabOverview.prepareNextTabChangesWithoutAnimation()
            tabManager.removeTab(at: index, mode: mode)
            tabOverview.prepareNextTabChangesWithoutAnimation()
            createTabFromOverview(mode: .regular)
            return
        }
        
        tabManager.removeTab(at: index, mode: mode)
    }
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode) {
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
    
    // MARK: - TabOverviewDelegate
    
    func tabOverviewDidRequestClearTabs(_ tabOverview: TabOverview) {
        clearTabsForCurrentOverviewMode()
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
        tabBar.setPendingExpansion(at: nil)
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
    
    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        if visible {
            if browserChrome.performAfterTransition({ [weak self] in
                self?.setTabOverviewVisible(true, animated: animated)
            }) {
                return
            }
            
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
            let tabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
            guard !tabs.isEmpty else {
                return
            }
            
            if tabManager.selectedTabMode != mode,
               let tabIndex = tabs.indices.max(by: {
                   tabs[$0].state.selectionOrder < tabs[$1].state.selectionOrder
               }) {
                tabManager.selectTab(at: tabIndex, mode: mode)
            }
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
        tabBar.setPendingExpansion(at: nil)
        
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
        tabOverview.prepareNextTabChangesWithoutAnimation()
        createTabFromOverview(mode: .regular)
    }
    
    func createTabFromOverview(mode: TabMode) {
        homepageOverlayCoordinator.prepareHomepageForNewTab(mode: mode)
        let createdIndex = tabManager.createTab(
            selecting: true,
            target: .end,
            mode: mode
        )
        let createdTabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        
        switch Prefs.NewTabSettings.newTabDisplayOption {
        case .homepage, .blankPage:
            let createdTabID = createdTabs[createdIndex].id
            
            captureThumbnail(forTabAt: createdIndex, mode: mode) { [weak self] previewImage in
                guard let self,
                      (mode == .private ? self.tabManager.privateTabs : self.tabManager.regularTabs)[safe: createdIndex]?.id == createdTabID else {
                    return
                }
                
                self.tabOverview.prepareDismissSelection(to: createdIndex, mode: mode, previewImage: previewImage)
                self.scrollTabOverviewToTab(at: createdIndex)
                self.tabBar.setPendingExpansion(at: createdIndex)
                self.setTabOverviewVisible(false, animated: true)
                self.scheduleAutomaticKeyboardFocusForNewTab(
                    (mode == .private ? self.tabManager.privateTabs : self.tabManager.regularTabs)[safe: createdIndex]
                )
            }
        case .customURL:
            applyNewTabDisplayOption(toTabAt: createdIndex)
            tabOverview.prepareDismissSelection(to: createdIndex, mode: mode, previewImage: nil)
            scrollTabOverviewToTab(at: createdIndex)
            tabBar.setPendingExpansion(at: createdIndex)
            setTabOverviewVisible(false, animated: true)
        }
    }
}
