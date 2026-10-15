//
//  FxADebugLog.swift
//  Reynard
//
//  A small on-device log for the Mozilla account / Sync code, viewable from
//  Settings > Firefox Sync > Sync Debug Log. It never records tokens, codes,
//  passwords or keys, only what happened and when.
//

import Foundation

nonisolated final class FxADebugLog: @unchecked Sendable {
    static let shared = FxADebugLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 500
    private let fileURL: URL?
    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        self.formatter = formatter

        if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            fileURL = directory.appendingPathComponent("FxASyncDebugLog.txt")
        } else {
            fileURL = nil
        }

        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let text = String(data: data, encoding: .utf8) {
            lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
    }

    func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        lines.append("\(formatter.string(from: Date())) \(message)")
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        persistLocked()
    }

    func contents() -> String {
        lock.lock()
        defer { lock.unlock() }
        if lines.isEmpty {
            return "(empty)"
        }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
        persistLocked()
    }

    private func persistLocked() {
        guard let fileURL else {
            return
        }
        let text = lines.joined(separator: "\n")
        try? text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}
