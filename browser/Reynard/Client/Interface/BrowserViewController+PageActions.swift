//
//  BrowserViewController+PageActions.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import GeckoView
import UIKit

extension BrowserViewController {
    // MARK: - Find in Page
    
    func showFindInPage() {
        guard tabManager.selectedTab != nil else {
            return
        }
        
        browserChrome.showActionBar(.findInPage(), animated: true)
    }
    
    // MARK: - Reader
    
    func showReader() {
        guard let tab = tabManager.selectedTab else {
            return
        }
        
        guard tab.state.readerMode.isActive else {
            _ = tabManager.readerMode.enter(in: tab)
            return
        }
        
        let controller = ReaderSettingsViewController(
            tabID: tab.id,
            tabManager: tabManager,
            readerMode: tabManager.readerMode
        )
        controller.onFindInPage = { [weak self] in
            guard let self,
                  self.tabManager.selectedTab === tab else {
                return
            }
            
            self.browserChrome.showActionBar(.findInPage(), animated: true)
        }
        
        controller.configurePresentation(asPopover: browserLayout.chromeMode == .pad)
        if controller.modalPresentationStyle == .pageSheet {
            controller.onVisibilityChanged = { [weak self] visible in
                guard let self else {
                    return
                }
                
                if visible {
                    self.toolbarController.collapseBottomToolbar()
                } else if !self.browserChrome.isShowingFindInPage {
                    self.toolbarController.restoreBottomToolbar()
                }
            }
        }
        
        if let popover = controller.popoverPresentationController {
            let sourceButton = browserChrome.addressBar.addressBarButton
            popover.sourceView = sourceButton
            popover.sourceRect = sourceButton.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = controller
        }
        
        present(controller, animated: true)
    }
    
    // MARK: - Page Zoom
    
    func showPageZoom() {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }
        
        browserChrome.setPageZoomLevel(selectedTab.session.settings.pageZoom.level)
        browserChrome.showActionBar(.pageZoom, animated: true)
    }
    
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
    
    // MARK: - Error Page
    
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
                tabManager.selectTab(tab)
            } else {
                tab.session.reload()
            }
        case let .openLink(url):
            let tab = tabManager.createTab(selecting: true, target: .afterSelected)
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
}
