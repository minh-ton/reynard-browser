//
//  DownloadFileIconProvider.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import MobileCoreServices

final class DownloadFileIconProvider {
    static let shared = DownloadFileIconProvider()
    
    private let thumbnailGenerator = QLThumbnailGenerator.shared
    private let thumbnailCache = NSCache<NSURL, UIImage>()
    private let placeholderCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    
    func placeholderIcon(for fileURL: URL) -> UIImage? {
        let fileName = fileURL.lastPathComponent
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: nil)
        if let cachedImage = placeholderCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let placeholderFileURL = placeholderFileURL(fileName: fileName, mimeType: nil),
              let image = documentInteractionIcon(for: placeholderFileURL) else {
            return nil
        }
        
        placeholderCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    func genericPlaceholderIcon() -> UIImage? {
        let cacheKey: NSString = "generic"
        if let cachedImage = placeholderCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let placeholderFileURL = placeholderFileURL(fileName: "generic-file", mimeType: nil),
              let image = documentInteractionIcon(
                for: placeholderFileURL,
                uti: kUTTypeData as String,
                name: "Downloading"
              ) else {
            return nil
        }
        
        placeholderCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    func icon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        if let cachedImage = thumbnailCache.object(forKey: fileURL as NSURL) {
            completion(cachedImage)
            return
        }
        
        generateIcon(for: fileURL, size: size, contentTypeIdentifier: nil) { [weak self] image in
            if let image {
                self?.thumbnailCache.setObject(image, forKey: fileURL as NSURL)
                completion(image)
                return
            }
            
            self?.fallbackIcon(for: fileURL, size: size, completion: completion)
        }
    }
    
    func cachedIcon(for fileURL: URL) -> UIImage? {
        return thumbnailCache.object(forKey: fileURL as NSURL)
    }
    
    private func generateIcon(
        for fileURL: URL,
        size: CGSize,
        contentTypeIdentifier: String?,
        representationTypes: QLThumbnailGenerator.Request.RepresentationTypes = .all,
        completion: @escaping (UIImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: UIScreen.main.scale,
            representationTypes: representationTypes
        )
        request.iconMode = true
        if #available(iOS 14.0, *),
           let contentTypeIdentifier,
           let contentType = UTType(contentTypeIdentifier) {
            request.contentType = contentType
        }
        
        thumbnailGenerator.generateBestRepresentation(for: request) { thumbnail, _ in
            DispatchQueue.main.async {
                completion(thumbnail?.uiImage)
            }
        }
    }
    
    private func fallbackIcon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let fileName = fileURL.lastPathComponent
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: nil)
        if let cachedImage = placeholderCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        guard let placeholderFileURL = placeholderFileURL(fileName: fileName, mimeType: nil) else {
            completion(nil)
            return
        }
        
        generateIcon(
            for: placeholderFileURL,
            size: size,
            contentTypeIdentifier: resolvedContentTypeIdentifier(fileName: fileName, mimeType: nil),
            representationTypes: .icon
        ) { [weak self] image in
            let resolvedImage = image ?? self?.documentInteractionIcon(for: placeholderFileURL)
            if let resolvedImage {
                self?.placeholderCache.setObject(resolvedImage, forKey: cacheKey)
            }
            completion(resolvedImage)
        }
    }
    
    private func placeholderFileURL(fileName: String, mimeType: String?) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let placeholderDirectory = cachesDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("IconPlaceholders", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: placeholderDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        
        let contentTypeIdentifier = resolvedContentTypeIdentifier(fileName: fileName, mimeType: mimeType)
        let existingExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let preferredExtension = existingExtension.isEmpty
        ? (preferredFilenameExtension(from: contentTypeIdentifier) ?? "")
        : existingExtension
        let placeholderName = preferredExtension.isEmpty ? "generic-file" : "generic-file.\(preferredExtension)"
        let placeholderFileURL = placeholderDirectory.appendingPathComponent(placeholderName)
        
        if !fileManager.fileExists(atPath: placeholderFileURL.path) {
            fileManager.createFile(atPath: placeholderFileURL.path, contents: Data())
        }
        
        return placeholderFileURL
    }
    
    private func placeholderCacheKey(fileName: String, mimeType: String?) -> NSString {
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension as NSString
        }
        if let mimeType, !mimeType.isEmpty {
            return mimeType.lowercased() as NSString
        }
        return "generic"
    }
    
    private func resolvedContentTypeIdentifier(fileName: String, mimeType: String?) -> String? {
        if let mimeType {
            if let uti = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
            )?.takeRetainedValue() {
                return uti as String
            }
        }
        
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension
        guard !pathExtension.isEmpty else {
            return nil
        }
        
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as CFString,
            nil
        )?.takeRetainedValue() as String?
    }
    
    private func preferredFilenameExtension(from contentTypeIdentifier: String?) -> String? {
        guard let contentTypeIdentifier else {
            return nil
        }
        return UTTypeCopyPreferredTagWithClass(
            contentTypeIdentifier as CFString,
            kUTTagClassFilenameExtension
        )?.takeRetainedValue() as String?
    }
    
    private func documentInteractionIcon(for fileURL: URL, uti: String? = nil, name: String? = nil) -> UIImage? {
        let controller = UIDocumentInteractionController(url: fileURL)
        controller.uti = uti
        controller.name = name
        
        return bestDocumentInteractionIcon(from: controller.icons)
    }
    
    private func bestDocumentInteractionIcon(from icons: [UIImage]) -> UIImage? {
        return icons.last
    }
}
