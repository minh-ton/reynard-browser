//
//  BrowserViewController+KeyCommands.swift
//  Reynard
//
//  Created by Minh Ton on 15/8/26.
//

import GeckoView
import UIKit

extension BrowserViewController: GeckoViewKeyCommandDelegate {
    func keyCommand(forInput input: String, modifierFlags: UIKeyModifierFlags) -> UIKeyCommand? {
        let modifiers = modifierFlags.intersection([.command, .control, .alternate, .shift])
        guard let command = ApplicationMenuBuilder.keyCommands.first(where: {
            guard $0.modifierFlags == modifiers else {
                return false
            }
            
            return $0.input?.caseInsensitiveCompare(input) == .orderedSame
        }) else {
            return nil
        }
        
        guard hasSelectedWebPage || !shouldDispatchKeyCommandToContent(command) else {
            return nil
        }
        
        return command
    }
    
    func shouldDispatchKeyCommandToContent(_ command: UIKeyCommand) -> Bool {
        return command.action != #selector(focusAddressBarKeyCommand(_:))
    }
    
    func contentDidHandleKeyCommand(_ command: UIKeyCommand) {
        browserChrome.addressBar.showKeyCommandHint(command)
    }
}

extension BrowserViewController {
    @objc func newTabKeyCommand(_ sender: UIKeyCommand) {
        createNewTab()
    }
    
    @objc func newPrivateTabKeyCommand(_ sender: UIKeyCommand) {
        createNewTab(mode: .private)
    }
    
    @objc func focusAddressBarKeyCommand(_ sender: UIKeyCommand) {
        if tabOverview.isPresented || tabOverview.isTransitionRunning {
            setTabOverviewVisible(false, animated: false)
        }
        
        browserChrome.addressBar.focusForHardwareKeyboard()
    }
    
    @objc func closeTabKeyCommand(_ sender: UIKeyCommand) {
        if tabOverview.isPresented || tabOverview.isTransitionRunning {
            closeTab()
            return
        }
        
        guard let tab = tabManager.selectedTab else {
            return
        }
        
        toolbarController.reset()
        let mode = tabManager.selectedTabMode
        tabManager.removeTab(tab, behavior: .adjacent)
        
        if mode == .regular && tabManager.regularTabs.isEmpty {
            createNewTab(mode: .regular)
        }
    }
    
    @objc func printPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage,
              let tab = tabManager.selectedTab,
              tab.session.isOpen(),
              UIPrintInteractionController.isPrintingAvailable else {
            return
        }
        
        Task { @MainActor in
            do {
                let pdfFileURL = try await PagePrintPreparationAlert.prepare {
                    try await tab.session.printToPDF()
                }
                try await PagePrintPresenter.present(pdfFileURL: pdfFileURL, jobName: tab.title)
            } catch {
                return
            }
        }
    }
    
    @objc func findInPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        
        if tabOverview.isPresented || tabOverview.isTransitionRunning {
            setTabOverviewVisible(false, animated: false)
        }
        
        browserChrome.showActionBar(.findInPage(), animated: true)
    }
    
    @objc func reloadPageKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage,
              let session = tabManager.selectedTab?.session else {
            return
        }
        
        if session.isOpen() {
            exitFullscreenIfNeeded()
            session.reload()
        } else {
            reloadTerminatedTab()
        }
    }
    
    @objc func toggleReaderKeyCommand(_ sender: UIKeyCommand) {
        guard let tab = tabManager.selectedTab else {
            return
        }
        
        if tab.state.readerMode.isActive {
            _ = tabManager.readerMode.exit(in: tab)
        } else if tab.state.readerMode.isReaderable {
            _ = tabManager.readerMode.enter(in: tab)
        }
    }
    
    @objc func zoomInKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        
        browserChrome.onPageZoomIn?()
    }
    
    @objc func zoomOutKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        
        browserChrome.onPageZoomOut?()
    }
    
    @objc func actualSizeKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        
        setSelectedPageZoomLevel(PageZoomLevels.defaultLevel)
    }
    
    @objc func showHistoryKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTabMode == .regular else {
            return
        }
        
        toggleLibrary(section: .history)
    }
    
    @objc func goBackKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.canGoBack else {
            return
        }
        
        exitFullscreenIfNeeded()
        browserChrome.onBack?()
    }
    
    @objc func goForwardKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTab?.state.navigationState.canGoForward == true else {
            return
        }
        
        exitFullscreenIfNeeded()
        browserChrome.onForward?()
    }
    
    @objc func showBookmarksKeyCommand(_ sender: UIKeyCommand) {
        toggleLibrary(section: .bookmarks)
    }
    
    @objc func addBookmarkKeyCommand(_ sender: UIKeyCommand) {
        guard hasSelectedWebPage else {
            return
        }
        
        presentBookmarkEditor(addToFavorites: false)
    }
    
    @objc func editBookmarksKeyCommand(_ sender: UIKeyCommand) {
        presentLibrary(initialSection: .bookmarks, startsEditingBookmarks: true)
    }
    
    @objc func showDownloadsKeyCommand(_ sender: UIKeyCommand) {
        toggleLibrary(section: .downloads)
    }
    
    @objc func showSettingsKeyCommand(_ sender: UIKeyCommand) {
        toggleLibrary(section: .settings)
    }
    
    @objc func showTabOverviewKeyCommand(_ sender: UIKeyCommand) {
        guard !tabOverview.isTransitionRunning else {
            return
        }
        
        setTabOverviewVisible(!tabOverview.isPresented, animated: true)
    }
    
    @objc func previousTabKeyCommand(_ sender: UIKeyCommand) {
        selectRelativeTab(offset: -1)
    }
    
    @objc func nextTabKeyCommand(_ sender: UIKeyCommand) {
        selectRelativeTab(offset: 1)
    }
    
    private func selectRelativeTab(offset: Int) {
        let tabs = tabManager.activeTabs
        guard tabs.count > 1 else {
            return
        }
        
        let index = (tabManager.selectedTabIndex + offset + tabs.count) % tabs.count
        selectTab(at: index, mode: tabManager.selectedTabMode)
    }
    
    @objc func selectTabKeyCommand(_ sender: UIKeyCommand) {
        guard let number = (sender.propertyList as? NSNumber)?.intValue else {
            return
        }
        
        let tabs = tabManager.activeTabs
        let index = number == 9 ? tabs.indices.last : tabs.indices.contains(number - 1) ? number - 1 : nil
        guard let index,
              index != tabManager.selectedTabIndex else {
            return
        }
        
        selectTab(at: index, mode: tabManager.selectedTabMode)
    }
    
    @objc func reopenLastClosedTabKeyCommand(_ sender: UIKeyCommand) {
        guard tabManager.selectedTabMode == .regular,
              let closedTab = TabManagementStore.shared.recentlyClosedTabs(limit: 1).first else {
            return
        }
        
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        _ = tabManager.restoreRecentlyClosedTab(id: closedTab.id)
    }
    
    @objc func toggleSidebarKeyCommand(_ sender: UIKeyCommand) {
        browserChrome.onSidebar?()
    }
    
    @objc func closeOtherTabsKeyCommand(_ sender: UIKeyCommand) {
        let tabs = tabManager.activeTabs
        guard tabs.count > 1,
              let selectedTab = tabManager.selectedTab else {
            return
        }
        
        toolbarController.reset()
        dismissAddressBarEditingAndOverlays()
        tabs.filter { $0 !== selectedTab }.reversed().forEach { tabManager.removeTab($0, behavior: .none) }
    }
    
    private var hasSelectedWebPage: Bool {
        guard let urlString = tabManager.selectedTab?.url else {
            return false
        }
        
        return URL(string: urlString)?.host != nil
    }
}
