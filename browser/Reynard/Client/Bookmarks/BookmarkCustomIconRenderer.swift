//
//  BookmarkCustomIconRenderer.swift
//  Reynard
//

import UIKit

enum BookmarkCustomIconRenderer {
    static func image(for icon: BookmarkCustomIcon) -> UIImage? {
        switch icon {
        case let .raster(data):
            return UIImage(data: data, scale: UIScreen.main.scale)
        case let .symbol(name, color):
            let tint = UIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
            return UIImage(systemName: name)?.withTintColor(tint, renderingMode: .alwaysOriginal)
        }
    }
}
