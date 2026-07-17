//
//  BookmarkCustomIcon.swift
//  Reynard
//

import Foundation

struct BookmarkIconColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func normalizedSRGB(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) -> BookmarkIconColor? {
        let components = [red, green, blue, alpha]
        guard components.allSatisfy(\.isFinite) else {
            return nil
        }
        return BookmarkIconColor(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            alpha: min(max(alpha, 0), 1)
        )
    }

    var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

enum BookmarkCustomIcon: Equatable, Sendable {
    case raster(Data)
    case symbol(name: String, color: BookmarkIconColor)

    var isValid: Bool {
        switch self {
        case let .raster(data):
            return !data.isEmpty && data.count <= BookmarkIconImagePolicy.maximumInputBytes
        case let .symbol(name, color):
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && color.isValid
        }
    }
}

enum BookmarkCustomIconMutation: Equatable, Sendable {
    case unchanged
    case set(BookmarkCustomIcon)
    case remove

    func resolved(over storedIcon: BookmarkCustomIcon?) -> BookmarkCustomIcon? {
        switch self {
        case .unchanged:
            return storedIcon
        case let .set(icon):
            return icon
        case .remove:
            return nil
        }
    }
}
