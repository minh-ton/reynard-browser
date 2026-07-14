//
//  BrowserViewController+BrowserActions.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController {
    func presentLibrary(initialSection: LibrarySection = .bookmarks) {
        if initialSection == .downloads {
            DownloadStore.shared.markCompletedAsViewed()
            if browserLayout.interfaceIdiom == .pad,
               browserLayout.chromeMode == .pad {
                sidebarCoordinator.showSection(.downloads)
                return
            }
        }
        
        let libraryController = LibraryViewController(
            initialSection: initialSection,
            isPrivateMode: tabManager.selectedTab?.isPrivate == true
        ) { [weak self] in
            self?.dismiss(animated: true)
        }
        let navigationController = UINavigationController(rootViewController: libraryController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    func presentShareSheet(url urlString: String? = nil) {
        let urlToShare: URL?
        if let urlString {
            urlToShare = URL(string: urlString)
        } else if let tab = tabManager.selectedTab {
            urlToShare = tabManager.shareableURL(for: tab)
        } else {
            urlToShare = nil
        }
        
        guard let url = urlToShare else {
            return
        }
        
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityController.popoverPresentationController {
            let sourceView = browserChrome.sharePopoverSourceView()
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(activityController, animated: true)
    }
    
    func createNewTab(intent: NewTabCreationIntent = .userInitiated) {
        dismissAddressBarEditingAndOverlays()
        
        if tabOverview.isPresented {
            tabOverview.prepareNextTabChangesWithoutAnimation()
            createTabFromOverview(mode: tabOverview.mode.tabMode, intent: intent)
        } else {
            homepageOverlayCoordinator.prepareHomepageForNewTab(mode: tabManager.selectedTabMode)
            let createdIndex = tabManager.createTab(selecting: true)
            applyNewTabDisplayOption(toTabAt: createdIndex)
            tabBar.setPendingExpansion(at: createdIndex)
            setTabOverviewVisible(false, animated: true)
            if intent.automaticallyFocusesAddressBar {
                scheduleAutomaticKeyboardFocusForNewTab(
                    tabManager.activeTabs[safe: createdIndex]
                )
            } else {
                cancelAutomaticKeyboardFocusForNewTab()
            }
        }
    }

    func scheduleAutomaticKeyboardFocusForNewTab(_ tab: Tab?) {
        guard Prefs.NewTabSettings.automaticallyOpensKeyboard,
              Prefs.NewTabSettings.newTabDisplayOption.supportsAutomaticKeyboardFocus,
              let tab else {
            cancelAutomaticKeyboardFocusForNewTab()
            return
        }

        pendingNewTabKeyboardFocusTabID = tab.id
        isPendingNewTabKeyboardFocusEventDispatchComplete = false
        isPendingNewTabContentReady = tab.state.hasFirstComposite
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pendingNewTabKeyboardFocusTabID == tab.id else {
                return
            }
            self.isPendingNewTabKeyboardFocusEventDispatchComplete = true
            self.fulfillPendingAutomaticKeyboardFocusIfPossible()
        }
    }

    func fulfillPendingAutomaticKeyboardFocusIfPossible() {
        guard let requestedTabID = pendingNewTabKeyboardFocusTabID else {
            return
        }
        let context = NewTabKeyboardFocusPolicy.Context(
            requestedTabID: requestedTabID,
            selectedTabID: tabManager.selectedTab?.id,
            isEnabled: Prefs.NewTabSettings.automaticallyOpensKeyboard,
            displayOptionSupportsFocus: Prefs.NewTabSettings.newTabDisplayOption.supportsAutomaticKeyboardFocus,
            isViewVisible: viewIfLoaded?.window != nil,
            isTabOverviewPresented: tabOverview.isPresented,
            isTransitionRunning: tabOverview.isTransitionRunning,
            isEventDispatchComplete: isPendingNewTabKeyboardFocusEventDispatchComplete,
            isContentReady: isPendingNewTabContentReady
        )
        if NewTabKeyboardFocusPolicy.shouldCancel(context) {
            cancelAutomaticKeyboardFocusForNewTab()
            return
        }
        guard NewTabKeyboardFocusPolicy.shouldFulfill(context) else {
            return
        }
        if browserChrome.focusAddressBar() {
            pendingNewTabKeyboardFocusTabID = nil
        }
    }

    func cancelAutomaticKeyboardFocusForNewTab() {
        pendingNewTabKeyboardFocusTabID = nil
        isPendingNewTabKeyboardFocusEventDispatchComplete = false
        isPendingNewTabContentReady = false
    }
}
