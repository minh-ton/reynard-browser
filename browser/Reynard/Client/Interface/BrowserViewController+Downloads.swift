//
//  BrowserViewController+Downloads.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension BrowserViewController: DownloadsCoordinatorDelegate {
    var downloadsShouldRefreshLayoutForStoreChange: Bool {
        return !sidebarCoordinator.hostsSidebar
        && browserLayout.interfaceIdiom == .pad
        && browserLayout.chromeMode == .pad
    }
    
    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary) {
        browserChrome.updateDownload(summary)
    }
    
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator) {
        updateBrowserLayout(animated: false)
    }
}
