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
                let createdIndex = self.tabManager.createTab(
                    selecting: true,
                    target: .end,
                    mode: overviewMode.tabMode
                )
                self.tabBar.setPendingExpansion(at: createdIndex)
            }
        } else {
            let createdIndex = tabManager.createTab(selecting: true)
            tabBar.setPendingExpansion(at: createdIndex)
            setTabOverviewVisible(false, animated: true)
        }
    }
    
    func goBack() {
        tabManager.goBack()
    }
    
    func goForward() {
        tabManager.goForward()
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
                if let tabIndex = targetTabs.indices.max(by: {
                    targetTabs[$0].state.selectionOrder < targetTabs[$1].state.selectionOrder
                }) {
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
        tabBar.setPendingExpansion(at: nil)
        
        if tabOverview.isPresented,
           tabOverview.mode == .privateTabs {
            tabManager.removeAllTabs(mode: .private)
            return
        }
        
        if tabOverview.isPresented,
           tabOverview.mode == .regularTabs {
            tabManager.removeAllTabs(mode: .regular)
            return
        }
        
        tabManager.removeAllTabs(mode: nil)
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
