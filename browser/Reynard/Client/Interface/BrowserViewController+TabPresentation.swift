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
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func closeTab(at index: Int, mode: TabMode) {
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
            contentView.resetFocusedInputRelocation()
            searchOverlayCoordinator.tabOverviewWillPresent()
        }
        tabOverview.setPresented(visible, animated: animated)
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
        }
        setTabOverviewVisible(false, animated: true)
    }
    
    private func clearTabsForCurrentOverviewMode() {
        tabBar.setPendingExpansion(at: nil)
        
        guard tabOverview.isPresented else {
            tabManager.removeAllTabs(mode: nil)
            return
        }
        
        tabManager.removeAllTabs(mode: tabOverview.mode.tabMode)
    }
}
