//
//  NavigationState.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation

struct NavigationHistoryConfiguration {
    static let standard = NavigationHistoryConfiguration()

    let maximumEntryCount: Int
    let maximumCachedTabCount: Int
    let maximumEncodedURLBytes: Int
    let maximumPreviewBytes: Int

    init(
        maximumEntryCount: Int = 200,
        maximumCachedTabCount: Int = 24,
        maximumEncodedURLBytes: Int = 64 * 1024,
        maximumPreviewBytes: Int = 1024 * 1024
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumCachedTabCount = max(1, maximumCachedTabCount)
        self.maximumEncodedURLBytes = max(1, maximumEncodedURLBytes)
        self.maximumPreviewBytes = max(1, maximumPreviewBytes)
    }
}

struct NavigationPersistencePolicy {
    private let maximumEncodedURLBytes: Int

    init(configuration: NavigationHistoryConfiguration = .standard) {
        maximumEncodedURLBytes = configuration.maximumEncodedURLBytes
    }

    func persistableURL(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue.utf8.count <= maximumEncodedURLBytes,
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return trimmedValue
    }
}

#if canImport(UIKit)
import UIKit
typealias NavigationPreviewImage = UIImage
#else
final class NavigationPreviewImage {
    private let data: Data

    init?(data: Data) {
        self.data = data
    }

    func jpegData(compressionQuality: Double) -> Data? {
        return data
    }
}
#endif

struct NavigationAvailability: Equatable {
    let canGoBack: Bool
    let canGoForward: Bool
}

struct NavigationPreviewImages {
    let backImage: NavigationPreviewImage?
    let forwardImage: NavigationPreviewImage?
}

enum SessionNavigationAvailability: Equatable {
    case unavailable
    case available(back: Bool, forward: Bool)
    
    var canGoBack: Bool {
        guard case let .available(back, _) = self else {
            return false
        }
        return back
    }
    
    var canGoForward: Bool {
        guard case let .available(_, forward) = self else {
            return false
        }
        return forward
    }
}

enum NavigationAction {
    case session
    case load(String)
}

struct NavigationTransition {
    let action: NavigationAction
    let availability: NavigationAvailability
}
