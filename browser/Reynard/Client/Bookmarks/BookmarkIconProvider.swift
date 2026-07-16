//
//  BookmarkIconProvider.swift
//  Reynard
//

import UIKit

struct ResolvedBookmarkIcon {
    let image: UIImage?
    let tintColor: UIColor?
}

@MainActor
final class BookmarkIconProvider {
    static let shared = BookmarkIconProvider()

    private let bookmarkStore: BookmarkStore
    private let faviconStore: FaviconStore
    private let customImageCache = NSCache<NSString, UIImage>()
    private var bookmarksWithoutCustomIcons = Set<String>()
    private var storeObserver: NSObjectProtocol?

    convenience init() {
        self.init(
            bookmarkStore: .shared,
            faviconStore: .shared
        )
    }

    init(bookmarkStore: BookmarkStore, faviconStore: FaviconStore) {
        self.bookmarkStore = bookmarkStore
        self.faviconStore = faviconStore
        storeObserver = NotificationCenter.default.addObserver(
            forName: .bookmarkStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateCustomIcons()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    func cachedIcon(for bookmark: BookmarkSnapshot) -> ResolvedBookmarkIcon {
        cachedIcon(bookmarkGUID: bookmark.guid, url: bookmark.url)
    }

    func cachedIcon(bookmarkGUID: String, url: URL) -> ResolvedBookmarkIcon {
        if let customImage = customImage(for: bookmarkGUID) {
            return ResolvedBookmarkIcon(image: customImage, tintColor: nil)
        }
        if let favicon = faviconStore.cachedFavicon(for: url) {
            return ResolvedBookmarkIcon(image: favicon, tintColor: nil)
        }
        return fallbackIcon
    }

    func icon(for bookmark: BookmarkSnapshot) async -> ResolvedBookmarkIcon {
        await icon(bookmarkGUID: bookmark.guid, url: bookmark.url)
    }

    func icon(bookmarkGUID: String, url: URL) async -> ResolvedBookmarkIcon {
        if let customImage = customImage(for: bookmarkGUID) {
            return ResolvedBookmarkIcon(image: customImage, tintColor: nil)
        }
        if let favicon = await faviconStore.favicon(for: url) {
            return ResolvedBookmarkIcon(image: favicon, tintColor: nil)
        }
        return fallbackIcon
    }

    func customImage(for bookmarkGUID: String) -> UIImage? {
        if let cached = customImageCache.object(forKey: bookmarkGUID as NSString) {
            return cached
        }
        guard !bookmarksWithoutCustomIcons.contains(bookmarkGUID),
              let icon = bookmarkStore.customIcon(for: bookmarkGUID),
              let image = BookmarkCustomIconRenderer.image(for: icon) else {
            bookmarksWithoutCustomIcons.insert(bookmarkGUID)
            return nil
        }
        customImageCache.setObject(image, forKey: bookmarkGUID as NSString)
        return image
    }

    func invalidateCustomIcons() {
        customImageCache.removeAllObjects()
        bookmarksWithoutCustomIcons.removeAll()
    }

    private var fallbackIcon: ResolvedBookmarkIcon {
        ResolvedBookmarkIcon(
            image: UIImage(named: "reynard.globe"),
            tintColor: .secondaryLabel
        )
    }
}
