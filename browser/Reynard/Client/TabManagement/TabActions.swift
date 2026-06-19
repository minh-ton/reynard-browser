//
//  TabActions.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation
import GeckoView

extension TabManager {
    @discardableResult
    func createTab(
        selecting: Bool,
        windowId: String? = nil,
        target: TabInsertionTarget = .end,
        mode: TabMode? = nil
    ) -> Int {
        let mode = mode ?? selectedTabMode
        return addTab(
            selecting: selecting,
            windowId: windowId,
            at: index(for: target, mode: mode),
            isPrivate: mode == .private
        )
    }
    
    @discardableResult
    func createRegularTab(
        selecting: Bool,
        windowId: String? = nil,
        target: TabInsertionTarget = .end,
        url: String? = nil,
        loadImmediately: Bool = false
    ) -> Tab? {
        let tabIndex = createTab(
            selecting: selecting,
            windowId: windowId,
            target: target,
            mode: .regular
        )
        guard regularTabs.indices.contains(tabIndex) else {
            return nil
        }
        
        let tab = regularTabs[tabIndex]
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            loadImmediately ? browse(to: url, in: tab) : (tab.state.displayState = .pending(url))
        }
        return tab
    }
    
    @discardableResult
    func openExternalURL(_ url: URL) -> Tab? {
        let tab = tabForExternalLoad()
        browse(to: url.absoluteString, in: tab)
        return tab
    }
    
    func reloadOrStopSelectedTab() {
        guard let selectedTab else {
            return
        }
        
        selectedTab.state.loadingState.isLoading ? selectedTab.session.stop() : selectedTab.session.reload()
    }
    
    var activeTabs: [Tab] {
        return selectedTabMode == .private ? privateTabs : regularTabs
    }
    
    func index(for target: TabInsertionTarget, mode: TabMode) -> Int? {
        let tabs = mode == .private ? privateTabs : regularTabs
        switch target {
        case .end:
            return tabs.count
        case .afterSelected:
            guard selectedTabMode == mode,
                  selectedTabIndex >= 0 else {
                return tabs.count
            }
            return selectedTabIndex + 1
        case let .index(index):
            return index
        }
    }
    
    private func tabForExternalLoad() -> Tab {
        if let selectedTab,
           selectedTab.isPrivate == (selectedTabMode == .private),
           isBlankTab(selectedTab) {
            return selectedTab
        }
        
        let tabIndex = createTab(selecting: true)
        return activeTabs[tabIndex]
    }
    
    private func isBlankTab(_ tab: Tab) -> Bool {
        guard let url = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else {
            return true
        }
        
        return url.lowercased().hasPrefix("about:blank")
    }
}

extension TabManagerImplementation {
    @discardableResult
    func changeWebsiteModeForSelectedTab() -> Bool {
        guard let tab = selectedTab,
              let url = tab.url,
              let navigationAction = sessionManager.toggleWebsiteMode(
                for: url,
                tabID: tab.id
              ) else {
            return false
        }
        
        switch navigationAction {
        case .reload:
            sessionManager.updateSettings(of: tab.session, for: url, tabID: tab.id)
            tab.session.reload()
        case let .load(overrideURL):
            tab.state.displayState = .pending(overrideURL)
            tab.state.suppressInitialNavigation = false
            sessionManager.updateSettings(of: tab.session, for: overrideURL, tabID: tab.id)
            tab.session.load(overrideURL, flags: GeckoSessionLoadFlags.replaceHistory)
        }
        return true
    }
}
