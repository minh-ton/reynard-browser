//
//  BrowserViewController+Presentation.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

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
                if completed,
                   let activityType {
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
    
    func presentWebsiteSettings() {
        guard let selectedTab = tabManager.selectedTab,
              let urlString = selectedTab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              let settingsController = SiteSettingsViewController(
                url: url,
                session: selectedTab.session,
                trackingProtection: sessionManager.trackingProtection
              ) else {
            return
        }
        
        presentContentModal(settingsController)
    }
    
    func presentBookmarkEditor(addToFavorites: Bool) {
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
        
        presentContentModal(bookmarkController)
    }
}
