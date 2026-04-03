//
//  DownloadStore.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import Foundation
import GeckoView
import UniformTypeIdentifiers

extension Notification.Name {
    static let downloadStoreDidChange = Notification.Name("me.minh-ton.reynard.download-store-did-change")
    static let downloadStoreDidStartDownload = Notification.Name("me.minh-ton.reynard.download-store-did-start-download")
}

struct DownloadStoreSummary {
    let activeCount: Int
    let aggregateProgress: Float
    let hasUnviewedCompletedDownloads: Bool
    
    var showsToolbarButton: Bool {
        activeCount > 0 || hasUnviewedCompletedDownloads
    }
}

struct DownloadStoreSnapshot {
    let summary: DownloadStoreSummary
    let items: [DownloadItemSnapshot]
}

struct DownloadItemSnapshot {
    enum State: Equatable {
        case downloading
        case completed
    }
    
    let id: UUID
    let fileName: String
    let fileURL: URL?
    let sourceURL: URL
    let originalURL: URL?
    let mimeType: String?
    let state: State
    let totalBytes: Int64?
    let downloadedBytes: Int64
    let bytesPerSecond: Int64
    let addedAt: Date
}

final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    
    struct PendingDownload {
        let fileName: String
        fileprivate let startHandler: () -> Void
    }
    
    private struct StorageURLs {
        let downloadsDirectoryURL: URL
        let appDataDirectoryURL: URL
        let manifestFileURL: URL
    }
    
    private struct PersistedDownloadEntry: Codable {
        let id: UUID
        let fileName: String
        let relativePath: String
        let sourceURLString: String
        let originalURLString: String?
        let mimeType: String?
        let fileSize: Int64
        let addedAt: Date
    }
    
    private struct DownloadRequest {
        let sourceURL: URL
        let originalURL: URL?
        let suggestedFileName: String?
        let mimeType: String?
        let expectedBytes: Int64?
        let requestMethod: String?
        let requestHeaders: [String: String]
    }
    
    private struct ProgressSample {
        let bytesWritten: Int64
        let timestamp: TimeInterval
    }
    
    private final class ActiveDownload {
        let id: UUID
        let sourceURL: URL
        let originalURL: URL?
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        let task: URLSessionDownloadTask
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        
        init(
            id: UUID,
            sourceURL: URL,
            originalURL: URL?,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            task: URLSessionDownloadTask,
            expectedBytes: Int64?
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.originalURL = originalURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.task = task
            self.expectedBytes = expectedBytes
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
        }
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "me.minh-ton.reynard.download-store-state", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private var activeDownloads: [Int: ActiveDownload] = [:]
    private var persistedDownloads: [PersistedDownloadEntry] = []
    private var hasQueuedProgressNotification = false
    private var hasUnviewedCompletedDownloads = false
    
    override init() {
        self.fileManager = .default
        
        guard let documentsDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory is unavailable")
        }
        
        let downloadsDirectoryURL = documentsDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        let appDataDirectoryURL = documentsDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
        let manifestFileURL = appDataDirectoryURL.appendingPathComponent("DownloadStore", isDirectory: false)
        self.storage = StorageURLs(
            downloadsDirectoryURL: downloadsDirectoryURL,
            appDataDirectoryURL: appDataDirectoryURL,
            manifestFileURL: manifestFileURL
        )
        
        super.init()
        
        stateQueue.sync {
            self.prepareStorageLocked()
            self.loadPersistedDownloadsLocked()
        }
    }
    
    func snapshot() -> DownloadStoreSnapshot {
        stateQueue.sync {
            makeSnapshotLocked()
        }
    }
    
    func prepareDownload(from response: ExternalResponseInfo) -> PendingDownload? {
        guard let sourceURL = URL(string: response.url), isSupportedDownloadURL(sourceURL) else {
            return nil
        }
        
        let request = DownloadRequest(
            sourceURL: sourceURL,
            originalURL: nil,
            suggestedFileName: response.filename,
            mimeType: response.mimeType,
            expectedBytes: response.contentLength,
            requestMethod: response.requestMethod,
            requestHeaders: response.requestHeaders
        )
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: request.suggestedFileName,
                sourceURL: request.sourceURL,
                mimeType: request.mimeType
            ),
            startHandler: { [weak self] in
                self?.enqueueDownload(request)
            }
        )
    }
    
    func prepareDownload(from request: SavePdfInfo) -> PendingDownload? {
        let candidateURLs = [request.url, request.originalUrl].compactMap { $0 }.compactMap(URL.init(string:))
        guard let sourceURL = candidateURLs.first(where: isSupportedDownloadURL) else {
            return nil
        }
        
        let downloadRequest = DownloadRequest(
            sourceURL: sourceURL,
            originalURL: URL(string: request.originalUrl ?? ""),
            suggestedFileName: request.filename,
            mimeType: "application/pdf",
            expectedBytes: nil,
            requestMethod: "GET",
            requestHeaders: [:]
        )
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: downloadRequest.suggestedFileName,
                sourceURL: downloadRequest.sourceURL,
                mimeType: downloadRequest.mimeType
            ),
            startHandler: { [weak self] in
                self?.enqueueDownload(downloadRequest)
            }
        )
    }
    
    func startDownload(_ download: PendingDownload) {
        download.startHandler()
    }
    
    func cancelDownload(id: UUID) {
        stateQueue.async {
            guard let active = self.activeDownloads.values.first(where: { $0.id == id }) else {
                return
            }
            
            self.activeDownloads.removeValue(forKey: active.task.taskIdentifier)
            active.task.cancel()
            self.postDidChange()
        }
    }
    
    func deleteDownloadedItem(id: UUID) {
        stateQueue.async {
            guard let index = self.persistedDownloads.firstIndex(where: { $0.id == id }) else {
                return
            }
            
            let entry = self.persistedDownloads.remove(at: index)
            let fileURL = self.storage.downloadsDirectoryURL.appendingPathComponent(entry.relativePath, isDirectory: false)
            
            if self.fileManager.fileExists(atPath: fileURL.path) {
                try? self.fileManager.removeItem(at: fileURL)
            }
            
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }
    
    func markCompletedDownloadsViewed() {
        stateQueue.async {
            guard self.hasUnviewedCompletedDownloads else {
                return
            }
            
            self.hasUnviewedCompletedDownloads = false
            self.postDidChange()
        }
    }
    
    private func enqueueDownload(_ request: DownloadRequest) {
        stateQueue.async {
            self.prepareStorageLocked()
            
            let fileName = self.resolvedFileName(
                suggestedFileName: request.suggestedFileName,
                sourceURL: request.sourceURL,
                mimeType: request.mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            
            var urlRequest = URLRequest(url: request.sourceURL)
            if let method = request.requestMethod?.uppercased(), method == "GET" {
                urlRequest.httpMethod = method
            }
            
            self.applyMirroredHeaders(request.requestHeaders, to: &urlRequest)
            
            let task = self.session.downloadTask(with: urlRequest)
            let active = ActiveDownload(
                id: UUID(),
                sourceURL: request.sourceURL,
                originalURL: request.originalURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: request.mimeType,
                addedAt: Date(),
                task: task,
                expectedBytes: request.expectedBytes
            )
            
            self.activeDownloads[task.taskIdentifier] = active
            task.resume()
            self.postDidStartDownload()
            self.postDidChange()
        }
    }
    
    private func makeSnapshotLocked() -> DownloadStoreSnapshot {
        let activeItems = activeDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: active.originalURL,
                    mimeType: active.mimeType,
                    state: .downloading,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt
                )
            }
            .sorted { $0.addedAt > $1.addedAt }
        
        let completedItems = persistedDownloads
            .map { entry in
                DownloadItemSnapshot(
                    id: entry.id,
                    fileName: entry.fileName,
                    fileURL: storage.downloadsDirectoryURL.appendingPathComponent(entry.relativePath, isDirectory: false),
                    sourceURL: URL(string: entry.sourceURLString) ?? storage.downloadsDirectoryURL,
                    originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                    mimeType: entry.mimeType,
                    state: .completed,
                    totalBytes: entry.fileSize,
                    downloadedBytes: entry.fileSize,
                    bytesPerSecond: 0,
                    addedAt: entry.addedAt
                )
            }
        
        return DownloadStoreSnapshot(summary: makeSummaryLocked(), items: activeItems + completedItems)
    }
    
    private func makeSummaryLocked() -> DownloadStoreSummary {
        let activeItems = Array(activeDownloads.values)
        let totalExpectedBytes = activeItems.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.expectedBytes ?? 0, 0)
        }
        let totalDownloadedBytes = activeItems.reduce(Int64(0)) { partialResult, item in
            partialResult + min(item.downloadedBytes, item.expectedBytes ?? item.downloadedBytes)
        }
        let aggregateProgress: Float
        if totalExpectedBytes > 0 {
            aggregateProgress = Float(totalDownloadedBytes) / Float(totalExpectedBytes)
        } else {
            aggregateProgress = 0
        }
        
        return DownloadStoreSummary(
            activeCount: activeItems.count,
            aggregateProgress: min(max(aggregateProgress, 0), 1),
            hasUnviewedCompletedDownloads: hasUnviewedCompletedDownloads
        )
    }
    
    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.downloadsDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: storage.appDataDirectoryURL, withIntermediateDirectories: true)
        
        guard !fileManager.fileExists(atPath: storage.manifestFileURL.path) else {
            return
        }
        
        let emptyManifest = (try? JSONEncoder().encode([PersistedDownloadEntry]())) ?? Data("[]".utf8)
        fileManager.createFile(atPath: storage.manifestFileURL.path, contents: emptyManifest)
    }
    
    private func loadPersistedDownloadsLocked() {
        guard let data = try? Data(contentsOf: storage.manifestFileURL) else {
            persistedDownloads = []
            savePersistedDownloadsLocked()
            return
        }
        
        if data.isEmpty {
            persistedDownloads = []
            savePersistedDownloadsLocked()
            return
        }
        
        if let decoded = try? JSONDecoder().decode([PersistedDownloadEntry].self, from: data) {
            persistedDownloads = decoded.sorted { $0.addedAt > $1.addedAt }
            return
        }
        
        persistedDownloads = []
        savePersistedDownloadsLocked()
    }
    
    private func savePersistedDownloadsLocked() {
        guard let data = try? JSONEncoder().encode(persistedDownloads.sorted { $0.addedAt > $1.addedAt }) else {
            return
        }
        
        try? data.write(to: storage.manifestFileURL, options: .atomic)
    }
    
    private func resolvedFileName(suggestedFileName: String?, sourceURL: URL, mimeType: String?) -> String {
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? "Download" : sourceURL.lastPathComponent
        let initialName = sanitizeFileName(suggestedFileName ?? fallbackName)
        
        guard URL(fileURLWithPath: initialName).pathExtension.isEmpty,
              let mimeType,
              let contentType = UTType(mimeType: mimeType),
              let preferredExtension = contentType.preferredFilenameExtension else {
            return initialName
        }
        
        return "\(initialName).\(preferredExtension)"
    }
    
    private func sanitizeFileName(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/:\n\r")
        let sanitized = trimmedValue
            .components(separatedBy: invalidCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        
        return sanitized.isEmpty ? "Download" : sanitized
    }
    
    private func makeUniqueDestinationURLLocked(for fileName: String) -> URL {
        let candidateURL = storage.downloadsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        let activeNames = Set(activeDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() })
        
        guard !fileManager.fileExists(atPath: candidateURL.path), !activeNames.contains(fileName.lowercased()) else {
            let fileURL = URL(fileURLWithPath: fileName)
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let extensionName = fileURL.pathExtension
            
            for index in 2...10_000 {
                let candidateName: String
                if extensionName.isEmpty {
                    candidateName = "\(baseName) \(index)"
                } else {
                    candidateName = "\(baseName) \(index).\(extensionName)"
                }
                
                let duplicateURL = storage.downloadsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
                if !fileManager.fileExists(atPath: duplicateURL.path), !activeNames.contains(candidateName.lowercased()) {
                    return duplicateURL
                }
            }
            
            return storage.downloadsDirectoryURL.appendingPathComponent(UUID().uuidString, isDirectory: false)
        }
        
        return candidateURL
    }
    
    private func applyMirroredHeaders(_ headers: [String: String], to request: inout URLRequest) {
        let allowedHeaders: Set<String> = [
            "accept",
            "accept-language",
            "authorization",
            "cookie",
            "origin",
            "referer",
            "user-agent",
        ]
        
        for (header, value) in headers {
            guard allowedHeaders.contains(header.lowercased()) else {
                continue
            }
            
            request.setValue(value, forHTTPHeaderField: header)
        }
    }
    
    private func isSupportedDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        return scheme == "http" || scheme == "https"
    }
    
    private func completeDownload(taskIdentifier: Int, temporaryLocation: URL) {
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }
        
        prepareStorageLocked()
        
        do {
            if fileManager.fileExists(atPath: active.destinationURL.path) {
                try fileManager.removeItem(at: active.destinationURL)
            }
            
            try fileManager.moveItem(at: temporaryLocation, to: active.destinationURL)
            let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
            
            persistedDownloads.insert(
                PersistedDownloadEntry(
                    id: active.id,
                    fileName: active.fileName,
                    relativePath: active.destinationURL.lastPathComponent,
                    sourceURLString: active.sourceURL.absoluteString,
                    originalURLString: active.originalURL?.absoluteString,
                    mimeType: active.mimeType,
                    fileSize: fileSize,
                    addedAt: active.addedAt
                ),
                at: 0
            )
            savePersistedDownloadsLocked()
            hasUnviewedCompletedDownloads = true
        } catch {
            try? fileManager.removeItem(at: temporaryLocation)
        }
        
        postDidChange(throttled: true)
    }
    
    private func resolvedFileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        
        return size.int64Value
    }
    
    private func updateProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let active = activeDownloads[taskIdentifier] else {
            return
        }
        
        active.downloadedBytes = totalBytesWritten
        if totalBytesExpectedToWrite > 0 {
            active.expectedBytes = totalBytesExpectedToWrite
        }
        
        let now = ProcessInfo.processInfo.systemUptime
        if let previousSample = active.lastProgressSample {
            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaBytes = max(totalBytesWritten - previousSample.bytesWritten, 0)
            let instantaneousSpeed = Int64(Double(deltaBytes) / deltaTime)
            if active.bytesPerSecond == 0 {
                active.bytesPerSecond = instantaneousSpeed
            } else {
                let smoothedSpeed = (Double(active.bytesPerSecond) * 0.65) + (Double(instantaneousSpeed) * 0.35)
                active.bytesPerSecond = Int64(smoothedSpeed)
            }
        }
        active.lastProgressSample = ProgressSample(bytesWritten: totalBytesWritten, timestamp: now)
        
        postDidChange()
    }
    
    private func failDownload(taskIdentifier: Int) {
        guard activeDownloads.removeValue(forKey: taskIdentifier) != nil else {
            return
        }
        
        postDidChange()
    }
    
    private func postDidChange(throttled: Bool = false) {
        if throttled {
            guard !hasQueuedProgressNotification else {
                return
            }
            
            hasQueuedProgressNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else {
                    return
                }
                
                self.stateQueue.async {
                    self.hasQueuedProgressNotification = false
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .downloadStoreDidChange, object: self)
                    }
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidChange, object: self)
        }
    }
    
    private func postDidStartDownload() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidStartDownload, object: self)
        }
    }
}

extension DownloadStore: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        stateQueue.async {
            self.updateProgress(
                taskIdentifier: downloadTask.taskIdentifier,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        stateQueue.sync {
            self.completeDownload(taskIdentifier: downloadTask.taskIdentifier, temporaryLocation: location)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        
        stateQueue.async {
            _ = error
            self.failDownload(taskIdentifier: task.taskIdentifier)
        }
    }
}
