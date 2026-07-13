//
//  BrowserViewController+AddressBar.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit
import GeckoView

extension BrowserViewController: AddressBarDelegate, AddressBarGestureDelegate {
    // MARK: - Address Bar State
    
    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let displayText: String?
        if case let .pending(text) = selectedTab?.state.displayState {
            displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            displayText = nil
        }
        
        let selectedURL = selectedTab?.url
        browserChrome.setAddressBarText(
            displayText?.isEmpty == false ? displayText : selectedURL,
            locationText: selectedURL,
            locationTitle: selectedTab?.title,
            showsBarMenu: displayText?.isEmpty != false && selectedURL?.isEmpty == false
        )
        browserChrome.setAddressBarLoadingProgress(
            selectedTab?.state.loadingState.progress ?? 0,
            isLoading: selectedTab?.state.loadingState.isLoading ?? false
        )
        addonCoordinator.prepareMenuIcons()
        let usesDesktopWebsite = selectedTab.flatMap { tab in
            tab.url.flatMap { url in
                sessionManager.isDesktopMode(for: url, tabID: tab.id)
            }
        }
        browserChrome.updateAddressBarMenu(
            url: selectedURL,
            usesDesktopWebsite: usesDesktopWebsite
        )
    }
    
    // MARK: - AddressBarDelegate
    
    func addressBarDidRequestReloadOrStop(_ addressBar: AddressBar) {
        tabManager.reloadOrStopSelectedTab()
    }
    
    func addressBarAddonItems(_ addressBar: AddressBar) -> [AddressBarMenu.AddonItem] {
        addonCoordinator.currentSiteMenuItems().map { item in
            AddressBarMenu.AddonItem(
                menuItem: item,
                image: addonCoordinator.menuIcon(for: item.addon)
            )
        }
    }

    func addressBarDidRequestAddonList(_ addressBar: AddressBar) {
        browserChrome.performAfterAddressBarMenuDismissal { [weak self] in
            guard let self else { return }
            let controller = AddonQuickListViewController(
                itemProvider: { [weak self] in
                    guard let self else { return [] }
                    return self.addressBarAddonItems(addressBar)
                },
                onSelect: { [weak self] item, listController in
                    listController.dismiss(animated: true) {
                        self?.addonCoordinator.activateMenuItem(item)
                    }
                },
                onUninstall: { [weak self] addon in
                    self?.confirmAddonUninstall(addon)
                },
                onDiscover: { [weak self] listController in
                    LibrarySharedUtils.openLinkInBrowser(
                        "https://addons.mozilla.org/android/",
                        from: listController
                    )
                    self?.refreshAddressBar()
                },
                onInstallFromFile: { packageURL in
                    let stagedURL = try AddonsPreferencesViewController.stageAddonPackage(from: packageURL)
                    _ = try await AddonRuntime.shared.install(url: stagedURL.absoluteString)
                    _ = try await AddonRuntime.shared.list()
                },
                onUpdateAll: { [weak self] in
                    guard let self else {
                        return AddonUpdateBatchResult(updatedCount: 0, noUpdateCount: 0, pendingApprovalCount: 0, failedCount: 0)
                    }
                    let coordinator = self.addonCoordinator.updateCoordinator
                    if coordinator.hasPendingApprovals {
                        return await coordinator.completePendingUpdates { _, _ in }
                    }
                    return await coordinator.updateAllAddons { _, _ in }
                }
            )
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                navigationController.sheetPresentationController?.detents = [.medium(), .large()]
                navigationController.sheetPresentationController?.prefersGrabberVisible = true
            }
            self.present(navigationController, animated: true)
        }
    }

    func addressBarDidRequestPageZoom(_ addressBar: AddressBar) {
        browserChrome.showPageZoomDropdownFromAddressBarMenu()
    }

    func addressBarCurrentPageZoomLevel(_ addressBar: AddressBar) -> Int? {
        return tabManager.selectedTab?.session.settings.pageZoom.level
    }

    func addressBar(_ addressBar: AddressBar, didRequestPageZoomLevel level: Int) {
        setSelectedPageZoomLevel(level)
    }
    
    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar) {
        guard tabManager.changeWebsiteModeForSelectedTab() else {
            return
        }
        
        refreshAddressBar()
    }
    
    func addressBarDidRequestWebsiteSettings(_ addressBar: AddressBar) {
        presentWebsiteSettings()
    }

    func addressBarDidRequestSettings(_ addressBar: AddressBar) {
        browserChrome.performAfterAddressBarMenuDismissal { [weak self] in
            self?.presentLibrary(initialSection: .settings)
        }
    }
    
    func addressBar(_ addressBar: AddressBar, didRequestBookmarkInFavorites favorites: Bool) {
        presentBookmarkEditor(addToFavorites: favorites)
    }
    
    func addressBarShareableURL(_ addressBar: AddressBar) -> URL? {
        guard let selectedTab = tabManager.selectedTab else {
            return nil
        }
        
        return tabManager.shareableURL(for: selectedTab)
    }
    
    // MARK: - AddressBarGestureDelegate
    
    var transitionContainerView: UIView {
        return view
    }
    
    var transitionContentView: ContentView {
        return contentView
    }
    
    var chromeMode: BrowserChromeMode {
        return browserLayout.chromeMode
    }
    
    var isSearchFocused: Bool {
        return searchOverlayCoordinator.isFocused
    }
    
    var isTabOverviewPresented: Bool {
        return tabOverview.isPresented
    }
    
    var isTabOverviewTransitionRunning: Bool {
        return tabOverview.isTransitionRunning
    }
    
    var selectedTabIndex: Int {
        return tabManager.selectedTabIndex
    }
    
    var selectedTabMode: TabMode {
        return tabManager.selectedTabMode
    }
    
    var activeTabs: [Tab] {
        return tabManager.activeTabs
    }
    
    func selectTabFromGesture(at index: Int, mode: TabMode) {
        tabManager.selectTab(at: index, mode: mode)
    }
    
    func createTabForSwipe() -> Int {
        let mode = tabManager.selectedTabMode
        captureTabThumbnailIfNeeded()
        homepageOverlayCoordinator.prepareHomepageForNewTab(mode: mode)
        let index = tabManager.createTab(selecting: false)

        if Prefs.NewTabSettings.newTabDisplayOption == .customURL {
            applyNewTabDisplayOption(toTabAt: index)
            return index
        }

        if let tab = tabManager.activeTabs[safe: index],
           let previewImage = homepageOverlayCoordinator.previewImage(for: tab, size: contentView.bounds.size) {
            tabManager.updateThumbnail(previewImage, forTabAt: index, mode: mode)
        }
        return index
    }

    func setPendingTabExpansion(at index: Int?) {
        tabBar.setPendingExpansion(at: index)
    }
    
    func presentTabOverviewFromGesture(animated: Bool) {
        setTabOverviewVisible(true, animated: animated)
    }
    
    func addressBarGestureWillBegin() {
        browserChrome.dismissActionBar(animated: false)
        captureTabThumbnailIfNeeded()
    }

    private func captureTabThumbnailIfNeeded() {
        if let tab = tabManager.activeTabs[safe: tabManager.selectedTabIndex],
           homepageOverlayCoordinator.needsHomepageThumbnail(for: tab) {
            if let thumbnail = homepageOverlayCoordinator.previewImage(for: tab, size: contentView.bounds.size) {
                tabManager.updateThumbnail(thumbnail, forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
            }
            return
        }

        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
    }
    
    func storedContentPreview(from tab: Tab) -> UIImage? {
        guard homepageOverlayCoordinator.needsHomepageThumbnail(for: tab) else {
            return nil
        }

        return tab.thumbnail
    }

    // MARK: - Page Zoom
    
    func setSelectedPageZoomToPreviousLevel() {
        setSelectedPageZoomLevel(browserChrome.previousPageZoomLevel())
    }
    
    func setSelectedPageZoomToNextLevel() {
        setSelectedPageZoomLevel(browserChrome.nextPageZoomLevel())
    }
    
    func setSelectedPageZoomLevel(_ level: Int) {
        guard let selectedTab = tabManager.selectedTab,
              let url = selectedTab.url else {
            return
        }
        
        browserChrome.setPageZoomLevel(level)
        sessionManager.setPageZoom(level, of: selectedTab.session, for: url, tabID: selectedTab.id)
    }
    
    // MARK: - Website Actions

    private func confirmAddonUninstall(_ addon: Addon) {
        let addonName = addon.metaData.name ?? addon.id
        AlertPresenter.show(
            title: "Uninstall \(addonName)?",
            message: nil,
            buttons: [
                AlertPresenter.Button(title: "Cancel", style: .cancel),
                AlertPresenter.Button(title: "Uninstall", style: .destructive) { [weak self] in
                    Task { [weak self] in
                        do {
                            try await AddonRuntime.shared.uninstall(addon)
                            let installedAddons = try await AddonRuntime.shared.list()
                            guard !installedAddons.contains(where: { $0.id == addon.id }) else {
                                throw NSError(
                                    domain: "com.minh-ton.Reynard.AddonUninstall",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Gecko still reports this add-on as installed."]
                                )
                            }
                            await MainActor.run {
                                self?.refreshAddressBar()
                                self?.browserChrome.invalidateAddressBarMenuPresentation()
                            }
                        } catch {
                            await MainActor.run {
                                AlertPresenter.show(title: "Failed to uninstall add-on", message: "\(error)")
                            }
                        }
                    }
                },
            ]
        )
    }
    
    private func presentWebsiteSettings() {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              let settingsController = SiteSettingsViewController(
                url: url,
                session: selectedTab.session,
                onWebsiteModeChanged: { [weak self] mode in
                    guard let self else { return }
                    if self.tabManager.setPersistentWebsiteMode(mode, forSelectedTabWithID: selectedTab.id) {
                        self.refreshAddressBar()
                    }
                },
                onWebsiteSettingsReset: { [weak self] in
                    guard let self else { return }
                    if self.tabManager.resetWebsiteSettings(
                        forSelectedTabWithID: selectedTab.id
                    ) {
                        self.refreshAddressBar()
                    }
                }
              ) else {
            return
        }
        
        let navigationController = UINavigationController(rootViewController: settingsController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    private func presentBookmarkEditor(addToFavorites: Bool) {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString) else {
            return
        }
        
        let title = selectedTab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmarkController: EditBookmarkViewController
        if addToFavorites {
            bookmarkController = EditBookmarkViewController(
                title: title,
                url: url,
                limitsToFavorites: true
            )
        } else if let bookmark = BookmarkStore.shared.bookmark(savedFor: url) {
            bookmarkController = EditBookmarkViewController(bookmark: bookmark)
        } else {
            bookmarkController = EditBookmarkViewController(title: title, url: url)
        }
        
        let navigationController = UINavigationController(rootViewController: bookmarkController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}
