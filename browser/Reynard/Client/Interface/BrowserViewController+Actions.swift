//
//  BrowserViewController+Actions.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import GeckoView
import ObjectiveC
import UIKit

private enum ActionsAssociatedKeys {
    static var addonController = 0
}

extension BrowserViewController {
    var addonController: AddonController {
        get {
            if let controller = objc_getAssociatedObject(self, &ActionsAssociatedKeys.addonController) as? AddonController {
                return controller
            }
            
            let controller = AddonController(controller: self)
            objc_setAssociatedObject(self, &ActionsAssociatedKeys.addonController, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return controller
        }
        set {
            objc_setAssociatedObject(self, &ActionsAssociatedKeys.addonController, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    func presentMenuSheet(initialSection: LibrarySection = .bookmarks) {
        let viewController = LibraryViewController(initialSection: initialSection, isPrivateMode: tabManager.selectedTab?.isPrivate == true) { [weak self] in
            self?.dismiss(animated: true)
        }
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    func presentShareSheet(url urlString: String? = nil) {
        let shareURL: URL?
        if let urlString {
            shareURL = URL(string: urlString)
        } else if let tab = tabManager.selectedTab {
            shareURL = tabManager.shareableURL(for: tab)
        } else {
            shareURL = nil
        }
        
        guard let url = shareURL else {
            return
        }
        
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            let sourceView = browserChrome.sharePopoverSourceView()
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }
    
    func showTabOverview() {
        setTabOverviewVisible(true, animated: true)
    }
    
    func hideTabOverview() {
        setTabOverviewVisible(false, animated: true)
    }
    
    func createNewTab() {
        browserChrome.clearAddressBarAutocomplete()
        searchOverlayCoordinator.endSearchSession()
        view.endEditing(true)
        
        if tabOverview.isPresented {
            let overviewMode = tabOverview.mode
            tabOverview.prepareNewTabInsertion { [weak self] in
                guard let self else {
                    return
                }
                _ = self.createTab(selecting: true, isPrivate: overviewMode == .privateTabs)
            }
        } else {
            _ = createTab(selecting: true)
            setTabOverviewVisible(false, animated: true)
        }
    }
    
    func goBack() {
        tabManager.goBack()
    }
    
    func goForward() {
        tabManager.goForward()
    }
    
    func changeWebsiteMode() {
        guard let tab = tabManager.selectedTab,
              let url = tab.url,
              let navigationAction = GeckoSessionController.shared.changeWebsiteMode(for: url, tabID: tab.id) else {
            return
        }
        
        switch navigationAction {
        case .reload:
            tab.session.updateSettings(GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id))
            tab.session.reload()
        case let .load(overrideURL):
            tab.pendingDisplayText = overrideURL
            tab.suppressInitialNavigation = false
            tab.session.updateSettings(GeckoSessionController.shared.sessionSettings(for: overrideURL, tabID: tab.id))
            tab.session.load(overrideURL, flags: GeckoSessionLoadFlags.replaceHistory)
        }
        
        refreshAddressBar()
    }
    
    @objc func tabsTapped() {
        showTabOverview()
    }
    
    @objc func doneTapped() {
        if tabOverview.isPresented {
            let targetMode = tabOverview.mode.tabMode
            let targetTabs = targetMode == .private ? tabManager.privateTabs : tabManager.regularTabs
            guard !targetTabs.isEmpty else {
                return
            }
            
            if tabManager.selectedTabMode != targetMode {
                var tabIndex: Int?
                for index in targetTabs.indices {
                    if tabIndex == nil || targetTabs[index].selectionOrder >= targetTabs[tabIndex!].selectionOrder {
                        tabIndex = index
                    }
                }
                
                if let tabIndex {
                    pendingSelectionAnimation = false
                    tabManager.selectTab(at: tabIndex, mode: targetMode)
                }
            }
        }
        hideTabOverview()
    }
    
    @objc func newTabTapped() {
        createNewTab()
    }
    
    @objc func clearAllTabsTapped() {
        if tabOverview.isPresented,
           tabOverview.mode == .privateTabs {
            tabBar.setPendingExpansion(at: nil)
            tabManager.removeAllTabs(mode: .private)
            return
        }
        
        if tabOverview.isPresented,
           tabOverview.mode == .regularTabs {
            tabBar.setPendingExpansion(at: nil)
            tabManager.removeAllTabs(mode: .regular)
            return
        }
        
        clearAllTabs()
    }
    
    @objc func shareTapped() {
        presentShareSheet()
    }
    
    @objc func padBackTapped() {
        goBack()
    }
    
    @objc func padForwardTapped() {
        goForward()
    }
    
    @objc func topBarMenuTapped() {
        presentMenuSheet()
    }
    
    @objc func presentWebsiteSettingsRequested() {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              let viewController = SiteSettingsViewController(url: url, session: selectedTab.session) else {
            return
        }
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    func presentBookmark(addToFavorites: Bool) {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString) else {
            return
        }
        
        let title = selectedTab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if addToFavorites {
            let viewController = EditBookmarkViewController(
                title: title,
                url: url,
                showsFavoritesHierarchyOnly: true
            )
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            present(navigationController, animated: true)
            return
        }
        
        let viewController: EditBookmarkViewController
        if let bookmark = BookmarkStore.shared.bookmark(for: url) {
            viewController = EditBookmarkViewController(bookmark: bookmark)
        } else {
            viewController = EditBookmarkViewController(title: title, url: url)
        }
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}

extension BrowserViewController: TabOverviewDataSource, TabOverviewDelegate {
    var tabOverviewSelectedMode: TabMode { tabManager.selectedTabMode }
    var tabOverviewRegularTabs: [Tab] { tabManager.regularTabs }
    var tabOverviewPrivateTabs: [Tab] { tabManager.privateTabs }

    func tabOverview(_ tabOverview: TabOverview, didSelectTabAt index: Int, mode: TabMode, previewImage: UIImage?) {
        tabOverview.prepareDismissSelection(to: index, mode: mode, previewImage: previewImage)
        tabOverview.reloadTabs()
        setTabOverviewVisible(false, animated: true)
    }

    func tabOverview(_ tabOverview: TabOverview, didCloseTabAt index: Int, mode: TabMode) {
        tabBar.setPendingExpansion(at: nil)
        tabManager.removeTab(at: index, mode: mode)
    }

    func tabOverview(_ tabOverview: TabOverview, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int, mode: TabMode) {
        tabManager.moveTab(from: sourceIndex, to: destinationIndex, mode: mode)
    }

    func tabOverviewDidRequestNewTab(_ tabOverview: TabOverview) {
        createNewTab()
    }

    func tabOverviewDidRequestDone(_ tabOverview: TabOverview) {
        doneTapped()
    }

    func tabOverviewDidRequestClear(_ tabOverview: TabOverview) {
        clearAllTabsTapped()
    }

    func tabOverview(_ tabOverview: TabOverview, didChangeMode mode: TabMode) {
        TabManagementStore.shared.saveLastTabOverview(mode == .private ? .private : .regular)
    }
}
