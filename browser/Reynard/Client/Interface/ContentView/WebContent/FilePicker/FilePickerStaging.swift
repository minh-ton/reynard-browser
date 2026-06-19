//
//  FilePickerStaging.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
@preconcurrency import PhotosUI
import UniformTypeIdentifiers

extension FilePicker {
    // MARK: - File Staging
    
    nonisolated static func stageFiles(from urls: [URL], in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        let copiedURLs = try urls.map { try copyItem(at: $0, into: directory) }
        return SelectionResult(files: copiedURLs.map(\.path), filesInWebKitDirectory: [])
    }
    
    nonisolated static func stageImageData(_ imageData: Data, in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        let destinationURL = uniqueDestinationURL(in: directory, preferredName: "photo.jpg")
        try imageData.write(to: destinationURL, options: .atomic)
        return SelectionResult(files: [destinationURL.path], filesInWebKitDirectory: [])
    }
    
    nonisolated static func stageFolder(from url: URL, in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        
        let rootName = sanitizeFileName(url.lastPathComponent.isEmpty ? "Folder" : url.lastPathComponent)
        let destinationURL = directory.appendingPathComponent(rootName, isDirectory: true)
        
        try withSecurityScopedAccess(to: url) {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
        }
        
        let enumerator = FileManager.default.enumerator(
            at: destinationURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var entries: [FolderEntry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }
            
            let relativeComponent = fileURL.path.replacingOccurrences(of: destinationURL.path + "/", with: "")
            entries.append(
                FolderEntry(
                    filePath: fileURL.path,
                    relativePath: rootName + "/" + relativeComponent,
                    name: fileURL.lastPathComponent,
                    type: mimeType(for: fileURL),
                    lastModified: (resourceValues.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000
                )
            )
        }
        
        return SelectionResult(files: [destinationURL.path], filesInWebKitDirectory: entries)
    }
    
    nonisolated static func prepareDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    
    private nonisolated static func copyItem(at sourceURL: URL, into directory: URL) throws -> URL {
        try withSecurityScopedAccess(to: sourceURL) {
            let destinationURL = uniqueDestinationURL(
                in: directory,
                preferredName: sourceURL.lastPathComponent
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }
    
    private nonisolated static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }
    
    nonisolated static func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let sanitizedName = sanitizeFileName(preferredName.isEmpty ? "File" : preferredName)
        let extensionPart = URL(fileURLWithPath: sanitizedName).pathExtension
        let baseName = extensionPart.isEmpty
        ? sanitizedName
        : String(sanitizedName.dropLast(extensionPart.count + 1))
        
        var candidate = directory.appendingPathComponent(sanitizedName, isDirectory: false)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = "-\(index)"
            let fileName = extensionPart.isEmpty ? baseName + suffix : baseName + suffix + "." + extensionPart
            candidate = directory.appendingPathComponent(fileName, isDirectory: false)
            index += 1
        }
        return candidate
    }
    
    private nonisolated static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\n")
        let pieces = name.components(separatedBy: invalidCharacters)
        let sanitized = pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "File" : sanitized
    }
    
    private nonisolated static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension as CFString
        guard let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            ext,
            nil
        )?.takeRetainedValue() else {
            return "application/octet-stream"
        }
        guard let mime = UTTypeCopyPreferredTagWithClass(
            uti,
            kUTTagClassMIMEType
        )?.takeRetainedValue() else {
            return "application/octet-stream"
        }
        return mime as String
    }
    
    // MARK: - Item Provider Staging
    
    @available(iOS 14.0, *)
    static func stageItemProvider(
        _ itemProvider: NSItemProvider,
        acceptedMediaTypes: [String],
        in directory: URL
    ) async -> URL? {
        guard let typeIdentifier = preferredTypeIdentifier(
            for: itemProvider,
            acceptedMediaTypes: acceptedMediaTypes
        ) else {
            return nil
        }
        
        if let stagedURL = await loadStagedFileRepresentation(
            from: itemProvider,
            typeIdentifier: typeIdentifier,
            in: directory
        ) {
            return stagedURL
        }
        
        guard let data = await loadDataRepresentation(
            from: itemProvider,
            typeIdentifier: typeIdentifier
        ) else {
            return nil
        }
        
        let destinationURL = uniqueDestinationURL(
            in: directory,
            preferredName: preferredMediaFileName(sourceURL: nil, typeIdentifier: typeIdentifier)
        )
        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            return nil
        }
    }
    
    @available(iOS 14.0, *)
    private static func preferredTypeIdentifier(
        for itemProvider: NSItemProvider,
        acceptedMediaTypes: [String]
    ) -> String? {
        let registeredTypeIdentifiers = itemProvider.registeredTypeIdentifiers
        
        if acceptedMediaTypes.contains(kUTTypeMovie as String),
           let movieType = registeredTypeIdentifiers.first(where: {
               typeConforms($0, to: kUTTypeMovie as String)
           }) {
            return movieType
        }
        
        if acceptedMediaTypes.contains(kUTTypeImage as String),
           let imageType = registeredTypeIdentifiers.first(where: {
               typeConforms($0, to: kUTTypeImage as String)
           }) {
            return imageType
        }
        
        return registeredTypeIdentifiers.first
    }
    
    @available(iOS 14.0, *)
    private static func loadStagedFileRepresentation(
        from itemProvider: NSItemProvider,
        typeIdentifier: String,
        in directory: URL
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, _ in
                guard let sourceURL else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let destinationURL = uniqueDestinationURL(
                    in: directory,
                    preferredName: preferredMediaFileName(
                        sourceURL: sourceURL,
                        typeIdentifier: typeIdentifier
                    )
                )
                
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    @available(iOS 14.0, *)
    private static func loadDataRepresentation(
        from itemProvider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
    
    @available(iOS 14.0, *)
    private static func preferredMediaFileName(sourceURL: URL?, typeIdentifier: String) -> String {
        if let sourceURL {
            let name = sourceURL.lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        
        let baseName: String
        if typeConforms(typeIdentifier, to: kUTTypeMovie as String) {
            baseName = "Video"
        } else if typeConforms(typeIdentifier, to: kUTTypeImage as String) {
            baseName = "Photo"
        } else {
            baseName = "File"
        }
        
        if let type = UTType(typeIdentifier),
           let filenameExtension = type.preferredFilenameExtension {
            return baseName + "." + filenameExtension
        }
        
        return baseName
    }
}
