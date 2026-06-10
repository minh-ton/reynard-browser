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
            let sourceView = browserUI.browserChrome.sharePopoverSourceView()
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
        browserUI.browserChrome.clearAddressBarAutocomplete()
        restoreSearchChrome(clearSuggestions: true)
        view.endEditing(true)
        
        if tabOverviewPresentation.isVisible {
            let overviewMode = browserUI.tabOverviewCollection.mode
            prepareOverviewFakeInsertionSlot(for: overviewMode) { [weak self] in
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
    
    func dismissKeyboard() {
        if isSearchScrollMode && searchViewController.parent != nil {
            restoreSearchChrome(clearSuggestions: true)
            return
        }
        
        browserUI.browserChrome.clearAddressBarAutocomplete()
        view.endEditing(true)
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
    
    func backButtonClicked() {
        goBack()
    }
    
    func forwardButtonClicked() {
        goForward()
    }
    
    func shareButtonClicked() {
        presentShareSheet()
    }
    
    func menuButtonClicked() {
        presentMenuSheet()
    }
    
    func tabsButtonClicked() {
        showTabOverview()
    }
    
    @objc func tabsTapped() {
        showTabOverview()
    }
    
    @objc func doneTapped() {
        if tabOverviewPresentation.isVisible {
            let targetMode: TabMode = browserUI.tabOverviewCollection.mode == .privateTabs ? .private : .regular
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
        if tabOverviewPresentation.isVisible,
           browserUI.tabOverviewCollection.mode == .privateTabs {
            pendingExpandedTabBarIndex = nil
            tabManager.removeAllTabs(mode: .private)
            return
        }
        
        if tabOverviewPresentation.isVisible,
           browserUI.tabOverviewCollection.mode == .regularTabs {
            pendingExpandedTabBarIndex = nil
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
