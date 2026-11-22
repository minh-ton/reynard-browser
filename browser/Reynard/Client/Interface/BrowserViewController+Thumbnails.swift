//
//  BrowserViewController+Thumbnails.swift
//  Reynard
//
//  Created by Minh Ton on 22/11/26.
//

import UIKit

extension BrowserViewController {
    // MARK: - Tab Thumbnails
    
    @discardableResult
    func captureThumbnail(forTabAt index: Int, mode: TabMode) -> UIImage? {
        let tabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard let tab = tabs[safe: index] else {
            return nil
        }
        
        let thumbnail = homepageOverlayCoordinator.isHomepageTab(tab)
        ? homepageOverlayCoordinator.makeThumbnail(for: tab)
        : makeWebThumbnail(for: tab)
        guard let thumbnail else {
            return nil
        }
        
        tabManager.updateThumbnail(thumbnail, forTabAt: index, mode: mode)
        return thumbnail
    }
    
    func storedContentPreview(from tab: Tab) -> UIImage? {
        guard homepageOverlayCoordinator.isHomepageTab(tab) else {
            return nil
        }
        
        return tab.thumbnail
    }
    
    func captureHistoryThumbnail(isPreparedForNavigation: Bool = false) {
        guard let tab = tabManager.selectedTab,
              let url = tab.url,
              let thumbnail = makeWebThumbnail(for: tab) else {
            return
        }
        
        tabManager.updateThumbnail(thumbnail, forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
        tabManager.updateHistoryThumbnail(
            thumbnail,
            for: tab,
            url: url,
            isPreparedForNavigation: isPreparedForNavigation
        )
    }
    
    private func makeWebThumbnail(for tab: Tab) -> UIImage? {
        guard tabManager.selectedTab === tab,
              !contentView.isHidden,
              contentView.isDisplaying(session: tab.session) else {
            return nil
        }
        
        return contentView.makeWebThumbnail()
    }
}
