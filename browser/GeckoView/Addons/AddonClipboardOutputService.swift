//
//  AddonClipboardOutputService.swift
//  Reynard
//

import Foundation
import UIKit

@MainActor
protocol AddonPasteboardWriting {
    func writePNG(_ data: Data) throws -> Int
}

@MainActor
private struct SystemAddonPasteboardWriter: AddonPasteboardWriting {
    func writePNG(_ data: Data) throws -> Int {
        let pasteboard = UIPasteboard.general
        let beforeChangeCount = pasteboard.changeCount
        pasteboard.setItems([[AddonStagedFile.clipboardPasteboardType: data]])
        guard pasteboard.changeCount > beforeChangeCount,
              pasteboard.contains(pasteboardTypes: [AddonStagedFile.clipboardPasteboardType]) else {
            throw GeckoHandlerError("iOS did not retain the PNG on the pasteboard")
        }
        return pasteboard.changeCount
    }
}

@MainActor
final class AddonClipboardOutputService {
    static let shared = AddonClipboardOutputService(writer: SystemAddonPasteboardWriter())

    private let writer: any AddonPasteboardWriting

    init(writer: any AddonPasteboardWriting) {
        self.writer = writer
    }

    func writePNG(_ data: Data) throws -> Int {
        try writer.writePNG(data)
    }
}
