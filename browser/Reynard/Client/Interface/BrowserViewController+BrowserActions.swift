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
        let defaultMode = tabOverview.isPresented
            ? tabOverview.mode.tabMode
            : tabManager.selectedTabMode.defaultingToPrivateBrowsing()
        let targetMode = mode ?? defaultMode
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        
        if tabOverview.isPresented {
            tabOverview.prepareNextTabChangesWithoutAnimation()
            createTabFromOverview(mode: targetMode)
        } else {
            homepageOverlayCoordinator.prepareHomepageForNewTab(mode: targetMode)
            let createdIndex = tabManager.createTab(selecting: true, mode: targetMode)
            applyNewTabDisplayOption(toTabAt: createdIndex)
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
        let sourceIndex = tabManager.selectedTabIndex
        let sourceMode = tabManager.selectedTabMode
        captureThumbnail(forTabAt: sourceIndex, mode: sourceMode) { [weak self] _ in
            guard let self else {
                return
            }
            
            self.toolbarController.reset()
            self.dismissAddressBarEditingAndOverlays()
            self.homepageOverlayCoordinator.prepareHomepageForNewTab(mode: mode)
            let target: TabInsertionTarget = self.tabManager.selectedTabMode == mode ? .afterSelected : .end
            let createdIndex = self.tabManager.createTab(
                selecting: false,
                target: target,
                mode: mode
            )
            let tabs = mode == .private ? self.tabManager.privateTabs : self.tabManager.regularTabs
            guard let tab = tabs[safe: createdIndex] else {
                return
            }
            
            self.prepareNewTab(tab, at: createdIndex, mode: mode) { [weak self] in
                guard let self else {
                    return
                }
                
                self.tabBar.setPendingExpansion(at: createdIndex)
                self.browserChrome.animateAutomaticTabTransition(to: tab) { [weak self] in
                    self?.tabManager.selectTab(at: createdIndex, mode: mode)
                }
            }
        }
    }
    
    private func prepareNewTab(
        _ tab: Tab,
        at index: Int,
        mode: TabMode,
        completion: @escaping () -> Void
    ) {
        switch Prefs.NewTabSettings.newTabDisplayOption {
        case .homepage, .blankPage:
            captureThumbnail(forTabAt: index, mode: mode) { _ in
                completion()
            }
        case .customURL:
            if URLUtils.normalizedNewTabURL(from: Prefs.NewTabSettings.customNewTabURL) != nil {
                tabManager.browse(to: Prefs.NewTabSettings.customNewTabURL, in: tab)
            }
            completion()
        }
    }
}
