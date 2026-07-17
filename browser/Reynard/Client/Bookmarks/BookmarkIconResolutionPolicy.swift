//
//  BookmarkIconResolutionPolicy.swift
//  Reynard
//

enum BookmarkIconResolutionSource: Equatable {
    case custom
    case favicon
    case fallback
}

enum BookmarkIconResolutionPolicy {
    nonisolated static func source(
        hasCustomIcon: Bool,
        hasFavicon: Bool
    ) -> BookmarkIconResolutionSource {
        if hasCustomIcon {
            return .custom
        }
        if hasFavicon {
            return .favicon
        }
        return .fallback
    }
}
