//
//  FilePickerAcceptedTypes.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
import UniformTypeIdentifiers

extension FilePicker {
    static func resolveAcceptedTypes(from mimeTypes: [String]) -> AcceptedTypes {
        let filters = mimeTypes
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        if filters.isEmpty || filters.contains("*/*") {
            return AcceptedTypes(
                documentTypeIdentifiers: [kUTTypeItem as String],
                legacyDocumentTypes: [kUTTypeItem as String],
                mediaTypes: [kUTTypeImage as String, kUTTypeMovie as String],
                captureMediaKind: nil
            )
        }
        
        var documentTypeIdentifiers: [String] = []
        var legacyDocumentTypes: [String] = []
        var mediaTypes: Set<String> = []
        var captureMediaKinds: Set<MediaKind> = []
        var hasNonCaptureType = false
        
        for filter in filters {
            switch filter {
            case "image/*":
                documentTypeIdentifiers.append(kUTTypeImage as String)
                legacyDocumentTypes.append(kUTTypeImage as String)
                mediaTypes.insert(kUTTypeImage as String)
                captureMediaKinds.insert(.image)
                continue
            case "video/*":
                documentTypeIdentifiers.append(kUTTypeMovie as String)
                legacyDocumentTypes.append(kUTTypeMovie as String)
                mediaTypes.insert(kUTTypeMovie as String)
                captureMediaKinds.insert(.video)
                continue
            case "audio/*":
                documentTypeIdentifiers.append(kUTTypeAudio as String)
                legacyDocumentTypes.append(kUTTypeAudio as String)
                hasNonCaptureType = true
                continue
            default:
                break
            }
            
            guard let typeIdentifier = typeIdentifier(forAcceptFilter: filter) else {
                hasNonCaptureType = true
                continue
            }
            
            documentTypeIdentifiers.append(typeIdentifier)
            legacyDocumentTypes.append(typeIdentifier)
            if typeConforms(typeIdentifier, to: kUTTypeImage as String) {
                mediaTypes.insert(kUTTypeImage as String)
                captureMediaKinds.insert(.image)
            }
            if typeConforms(typeIdentifier, to: kUTTypeMovie as String) {
                mediaTypes.insert(kUTTypeMovie as String)
                captureMediaKinds.insert(.video)
            }
            if !typeConforms(typeIdentifier, to: kUTTypeImage as String) &&
                !typeConforms(typeIdentifier, to: kUTTypeMovie as String) {
                hasNonCaptureType = true
            }
        }
        
        if documentTypeIdentifiers.isEmpty {
            documentTypeIdentifiers = [kUTTypeItem as String]
        }
        if legacyDocumentTypes.isEmpty {
            legacyDocumentTypes = [kUTTypeItem as String]
        }
        
        return AcceptedTypes(
            documentTypeIdentifiers: Array(Set(documentTypeIdentifiers)).sorted(),
            legacyDocumentTypes: Array(Set(legacyDocumentTypes)).sorted(),
            mediaTypes: Array(mediaTypes).sorted(),
            captureMediaKind: hasNonCaptureType || captureMediaKinds.count != 1
            ? nil
            : captureMediaKinds.first
        )
    }
    
    private static func typeIdentifier(forAcceptFilter filter: String) -> String? {
        if filter.hasPrefix(".") {
            let filenameExtension = String(filter.dropFirst())
            guard !filenameExtension.isEmpty else { return nil }
            return typeIdentifier(forFilenameExtension: filenameExtension)
        }
        
        if filter.contains("/") {
            return typeIdentifier(forMIMEType: filter)
        }
        
        return filter
    }
    
    private static func typeIdentifier(forFilenameExtension filenameExtension: String) -> String? {
        if #available(iOS 14.0, *) {
            return UTType(filenameExtension: filenameExtension)?.identifier
        }
        
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            filenameExtension as CFString,
            nil
        )?.takeRetainedValue() as String?
    }
    
    private static func typeIdentifier(forMIMEType mimeType: String) -> String? {
        if #available(iOS 14.0, *) {
            return UTType(mimeType: mimeType)?.identifier
        }
        
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassMIMEType,
            mimeType as CFString,
            nil
        )?.takeRetainedValue() as String?
    }
    
    static func typeConforms(_ typeIdentifier: String, to parentIdentifier: String) -> Bool {
        if #available(iOS 14.0, *) {
            guard let type = UTType(typeIdentifier),
                  let parentType = UTType(parentIdentifier) else {
                return false
            }
            return type.conforms(to: parentType)
        }
        
        return UTTypeConformsTo(typeIdentifier as CFString, parentIdentifier as CFString)
    }
}
