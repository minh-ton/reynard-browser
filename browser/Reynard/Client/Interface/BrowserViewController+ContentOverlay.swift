//
//  BrowserViewController+ContentOverlay.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: ContentOverlayCoordinatorHost, SearchOverlayCoordinatorDelegate {
    var overlayParentViewController: UIViewController {
        return self
    }
    
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
    
    var isSearchAddressBarShowingAutocomplete: Bool {
        return browserChrome.isShowingAddressBarAutocomplete
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
}
