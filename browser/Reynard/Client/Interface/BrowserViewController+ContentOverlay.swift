//
//  BrowserViewController+ContentOverlay.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: ContentOverlayCoordinatorHost, SearchOverlayCoordinatorDelegate {
    // MARK: - ContentOverlayCoordinatorHost

    var overlayParentViewController: UIViewController {
        self
    }

    // MARK: - SearchOverlayCoordinatorDelegate

    var searchLayout: BrowserLayout {
        browserLayout
    }

    var searchChrome: BrowserChrome {
        browserChrome
    }

    var searchContentView: ContentView {
        contentView
    }

    var searchSelectedTabMode: TabMode {
        tabManager.selectedTabMode
    }

    var searchSelectedTabID: UUID? {
        tabManager.selectedTab?.id
    }

    var searchActiveTabs: [Tab] {
        tabManager.activeTabs
    }

    var isSearchAddressBarEditing: Bool {
        browserChrome.isAddressBarEditing
    }

    var isSearchAddressBarShowingAutocomplete: Bool {
        browserChrome.isShowingAddressBarAutocomplete
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
