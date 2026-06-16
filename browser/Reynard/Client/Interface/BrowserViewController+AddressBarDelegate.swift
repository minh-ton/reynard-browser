//
//  BrowserViewController+AddressBarDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: AddressBarDelegate, AddressBarDataSource {
    func addonItems(for addressBar: AddressBar) -> [AddressBarMenu.AddonItem] {
        addonController.visibleMenuItemsForCurrentSite().map { item in
            AddressBarMenu.AddonItem(menuItem: item, image: addonController.iconImage(for: item.addon))
        }
    }

    func addressBarDidTapTrailingButton(_ addressBar: AddressBar) {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }

        if selectedTab.isLoading {
            selectedTab.session.stop()
        } else {
            selectedTab.session.reload()
        }
    }

    func addressBar(_ addressBar: AddressBar, didSelectAddon item: AddonMenuItem) {
        addonController.presentCurrentSiteSettings(for: item)
    }

    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar) {
        changeWebsiteMode()
    }

    func addressBarDidRequestWebsiteSettings(_ addressBar: AddressBar) {
        presentWebsiteSettingsRequested()
    }

    func addressBar(_ addressBar: AddressBar, didRequestBookmarkInFavorites favorites: Bool) {
        presentBookmark(addToFavorites: favorites)
    }
}
