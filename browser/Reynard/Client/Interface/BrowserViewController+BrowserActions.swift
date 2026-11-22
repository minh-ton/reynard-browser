//
//  BrowserViewController+BrowserActions.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController {
    func presentShareSheet(
        items: [Any],
        sourceView: UIView,
        sourceRect: CGRect,
        applicationActivities: [UIActivity]? = nil,
        onActivityPerformed: ((UIActivity.ActivityType) -> Void)? = nil,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        guard !items.isEmpty else {
            return
        }
        
        let activityController = UIActivityViewController(
            activityItems: items,
            applicationActivities: applicationActivities
        )
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceRect
        }
        if onActivityPerformed != nil || completion != nil {
            activityController.completionWithItemsHandler = { activityType, completed, _, error in
                if completed, let activityType {
                    onActivityPerformed?(activityType)
                }
                completion?(completed, error)
            }
        }
        present(activityController, animated: true)
    }
    
    func presentContentModal(_ rootViewController: UIViewController) {
        let navigationController = ContentModalNavigationController(
            rootViewController: rootViewController
        ) { [weak self] in
            self?.requestContentKeyboardFocus()
        }
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    func presentLibrary(
        initialSection: LibrarySection = .bookmarks,
        startsEditingBookmarks: Bool = false
    ) {
        if browserLayout.interfaceIdiom == .pad,
           browserLayout.chromeMode == .pad {
            sidebarCoordinator.showSection(
                initialSection,
                startsEditingBookmarks: startsEditingBookmarks
            )
            return
        }
        
        let libraryController = LibraryViewController(
            initialSection: initialSection,
            isPrivateMode: tabManager.selectedTab?.isPrivate == true,
            startsEditingBookmarks: startsEditingBookmarks,
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        presentContentModal(libraryController)
    }
    
    func toggleLibrary(section: LibrarySection) {
        if browserLayout.interfaceIdiom == .pad,
           browserLayout.chromeMode == .pad {
            (splitViewController as? SidebarViewController)?.toggleSection(section)
            return
        }
        
        guard let navigationController = presentedViewController as? ContentModalNavigationController,
              let libraryController = navigationController.viewControllers.first as? LibraryViewController else {
            presentLibrary(initialSection: section)
            return
        }
        libraryController.toggleSection(section)
    }
    
    func performErrorPageAction(_ action: WebContentErrorView.Action) {
        guard let tab = tabManager.selectedTab,
              let loadError = tab.state.loadError else {
            return
        }
        
        switch action {
        case .back:
            tabManager.goBack()
        case .retry:
            if !tab.session.isOpen() {
                tabManager.selectTab(at: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
            } else {
                tab.session.reload()
            }
        case let .openLink(url):
            let index = tabManager.createTab(selecting: true, target: .afterSelected)
            guard let tab = tabManager.activeTabs[safe: index] else {
                return
            }
            tabManager.browse(to: url.absoluteString, in: tab)
        case .acceptCertificate, .continueHTTP:
            let succeeded = action == .acceptCertificate
            ? tab.session.addCertException(for: loadError)
            : tab.session.reloadWithHttpsOnlyException(for: loadError)
            
            if !succeeded {
                let alert = UIAlertController(
                    title: NSLocalizedString("Unable to Open Page", comment: ""),
                    message: NSLocalizedString("Try Again", tableName: "WebContentErrorLocalizable", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                present(alert, animated: true)
            }
        }
    }
    
    func createNewTab(mode: TabMode? = nil) {
        let targetMode = mode ?? (tabOverview.isPresented ? tabOverview.mode.tabMode : tabManager.selectedTabMode)
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        
        if tabOverview.isPresented {
            tabOverview.prepareNextTabChangesWithoutAnimation()
            createTabFromOverview(mode: targetMode)
        } else {
            let createdIndex = tabManager.createTab(selecting: true, mode: targetMode)
            applyNewTabDisplayOption(toTabAt: createdIndex, mode: targetMode)
            tabBar.setPendingExpansion(at: createdIndex)
            setTabOverviewVisible(false, animated: true)
        }
    }
    
    func closeAllTabs() {
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        let mode = tabManager.selectedTabMode
        let shouldCreateNewTab = mode == .regular && !tabManager.regularTabs.isEmpty
        tabManager.removeAllTabs(mode: mode)
        if shouldCreateNewTab {
            createNewTab(mode: .regular)
        }
    }
    
    func closeTab() {
        guard tabManager.selectedTab != nil else {
            return
        }
        
        let mode = tabManager.selectedTabMode
        closeTab(at: tabManager.selectedTabIndex, mode: mode)
        if mode == .regular && tabManager.regularTabs.isEmpty {
            createNewTab(mode: .regular)
        }
    }
    
    func createNewTabAnimated(mode: TabMode) {
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        let target: TabInsertionTarget = tabManager.selectedTabMode == mode ? .afterSelected : .end
        let createdIndex = tabManager.createTab(
            selecting: false,
            target: target,
            mode: mode
        )
        guard let tab = tabManager.tabs(for: mode)[safe: createdIndex] else {
            return
        }
        
        applyNewTabDisplayOption(toTabAt: createdIndex, mode: mode)
        tabBar.setPendingExpansion(at: createdIndex)
        browserChrome.addressBar.animateAutomaticTabTransition(to: tab) { [weak self] in
            self?.tabManager.selectTab(at: createdIndex, mode: mode)
        }
    }
}
