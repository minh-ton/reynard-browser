//
//  DownloadImagePreview.swift
//  Reynard
//

import Foundation
import QuickLook
import UniformTypeIdentifiers
import MobileCoreServices

final class DownloadImagePreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(fileURL: URL, title: String) {
        previewItemURL = fileURL
        previewItemTitle = title
        super.init()
    }
}

final class DownloadImagePreviewDataSource: NSObject, QLPreviewControllerDataSource {
    let item: DownloadImagePreviewItem

    init(item: DownloadImagePreviewItem) {
        self.item = item
        super.init()
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return item
    }
}

enum DownloadImageTypeDetector {
    static func isImage(fileName: String, mimeType: String?) -> Bool {
        if #available(iOS 14.0, *) {
            if let mimeType,
               let type = UTType(mimeType: mimeType),
               type.conforms(to: .image) {
                return true
            }

            let pathExtension = URL(fileURLWithPath: fileName).pathExtension
            if !pathExtension.isEmpty,
               let type = UTType(filenameExtension: pathExtension),
               type.conforms(to: .image) {
                return true
            }
            return false
        }

        if let mimeType,
           let identifier = UTTypeCreatePreferredIdentifierForTag(
               kUTTagClassMIMEType,
               mimeType as CFString,
               nil
           )?.takeRetainedValue(),
           UTTypeConformsTo(identifier, kUTTypeImage) {
            return true
        }

        let pathExtension = URL(fileURLWithPath: fileName).pathExtension
        guard !pathExtension.isEmpty,
              let identifier = UTTypeCreatePreferredIdentifierForTag(
                  kUTTagClassFilenameExtension,
                  pathExtension as CFString,
                  nil
              )?.takeRetainedValue() else {
            return false
        }
        return UTTypeConformsTo(identifier, kUTTypeImage)
    }

    static func prefersSystemPreview(fileName: String, mimeType: String?) -> Bool {
        if mimeType?.lowercased() == "image/gif" {
            return true
        }
        return URL(fileURLWithPath: fileName).pathExtension.lowercased() == "gif"
    }
}
