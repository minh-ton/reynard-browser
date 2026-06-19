//
//  FilePickerDocumentPicker.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

extension FilePicker {
    func presentDocumentPicker() {
        guard let presenter = UIApplication.shared.topViewController() else {
            finish(with: nil)
            return
        }
        
        let picker = documentPicker()
        picker.delegate = self
        picker.presentationController?.delegate = self
        picker.allowsMultipleSelection = mode == .multiple
        presenter.present(picker, animated: true)
        presentedController = picker
    }
    
    private func documentPicker() -> UIDocumentPickerViewController {
        if #available(iOS 14.0, *) {
            if mode == .folder {
                return UIDocumentPickerViewController(
                    forOpeningContentTypes: [UTType.folder],
                    asCopy: false
                )
            }
            
            let contentTypes = acceptedTypes.documentTypeIdentifiers.compactMap { UTType($0) }
            return UIDocumentPickerViewController(
                forOpeningContentTypes: contentTypes.isEmpty ? [UTType.item] : contentTypes
            )
        }
        
        let legacyTypes = acceptedTypes.legacyDocumentTypes.isEmpty
        ? [kUTTypeItem as String]
        : acceptedTypes.legacyDocumentTypes
        return UIDocumentPickerViewController(documentTypes: legacyTypes, in: .open)
    }
    
    func prepareDocumentResult(from urls: [URL]) async -> SelectionResult? {
        let selectedURLs = mode == .multiple ? urls : Array(urls.prefix(1))
        let mode = self.mode
        let stagingDirectoryURL = self.stagingDirectoryURL
        
        return await Task.detached(priority: .userInitiated) {
            switch mode {
            case .folder:
                guard let url = selectedURLs.first else { return nil }
                return try? Self.stageFolder(from: url, in: stagingDirectoryURL)
            case .single, .multiple:
                return try? Self.stageFiles(from: selectedURLs, in: stagingDirectoryURL)
            }
        }.value
    }
}
