//
//  AddonIconLoader.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum AddonIconLoader {
    static func loadImage(from iconURLString: String?, targetSize: CGSize) -> UIImage? {
        guard let iconURLString,
              let url = URL(string: iconURLString),
              let data = loadData(from: url) else {
            return nil
        }
        
        if iconURLString.lowercased().hasSuffix(".svg") {
            return SVGIconRenderer.render(data: data, size: targetSize)
        }
        
        guard let image = UIImage(data: data) else {
            return nil
        }
        return resizedImage(from: image, targetSize: targetSize)
    }
    
    private static func loadData(from url: URL) -> Data? {
        switch url.scheme?.lowercased() {
        case "file":
            return try? Data(contentsOf: url)
        case "jar":
            return jarEntryData(from: url)
        default:
            return nil
        }
    }
    
    private static func jarEntryData(from url: URL) -> Data? {
        let absoluteString = url.absoluteString
        guard absoluteString.hasPrefix("jar:") else {
            return nil
        }
        
        let jarString = String(absoluteString.dropFirst(4))
        let components = jarString.components(separatedBy: "!/")
        guard components.count == 2,
              let archiveURL = URL(string: components[0]),
              archiveURL.isFileURL,
              let archiveData = try? Data(contentsOf: archiveURL) else {
            return nil
        }
        
        return ZipArchiveReader.entryData(in: archiveData, path: components[1])
    }
    
    private static func resizedImage(from image: UIImage, targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
