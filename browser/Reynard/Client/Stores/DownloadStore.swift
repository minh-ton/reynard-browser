//
//  DownloadStore.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import Foundation
import GeckoView
import UniformTypeIdentifiers
import MobileCoreServices

struct DownloadStoreSummary {
    let totalCount: Int
    let activeCount: Int
    let aggregateProgress: Float
    let hasUnviewedCompletedDownloads: Bool
    
    var showsToolbarButton: Bool {
        return activeCount > 0 || (hasUnviewedCompletedDownloads && totalCount > 0)
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
    let fileExists: Bool
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

    struct CompletedDownloadImport {
        let fileURL: URL
        let mimeType: String?
        let fileSize: Int64
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
            task: URLSessionDownloadTask
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.originalURL = originalURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.task = task
            self.expectedBytes = nil
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
        }
    }
    
    private final class CapturedDownload {
        let id: UUID
        let localFilePath: String
        let sourceURL: URL
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        
        init(
            id: UUID,
            localFilePath: String,
            sourceURL: URL,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            expectedBytes: Int64?
        ) {
            self.id = id
            self.localFilePath = localFilePath
            self.sourceURL = sourceURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.expectedBytes = expectedBytes
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
        }
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.DownloadStore.Queue", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private var activeDownloads: [Int: ActiveDownload] = [:]
    private var capturedDownloads: [String: CapturedDownload] = [:]
    private var persistedDownloads: [PersistedDownloadEntry] = []
    private var lastSessionProgressNotificationTime: TimeInterval = 0
    private var hasUnviewedCompletedDownloads = false
    
    // MARK: - Lifecycle
    
    override init() {
        self.fileManager = .default
        let directories = ReynardDirectories.shared
        let downloadsDirectoryURL = directories.downloads
        let appDataDirectoryURL = directories.appData
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
    
    // MARK: - Downloads
    
    func currentSnapshot() -> DownloadStoreSnapshot {
        stateQueue.sync {
            makeSnapshotLocked()
        }
    }
    
    // MARK: - Pending Downloads
    
    func pendingDownload(from response: ExternalResponseInfo) -> PendingDownload? {
        guard let sourceURL = URL(string: response.url) else {
            return nil
        }
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: response.filename,
                sourceURL: sourceURL,
                mimeType: response.mimeType
            ),
            startHandler: { [weak self] in
                self?.beginCapturedDownload(
                    localFilePath: response.localFilePath,
                    sourceURL: sourceURL,
                    suggestedFileName: response.filename,
                    mimeType: response.mimeType,
                    expectedBytes: response.contentLength
                )
            }
        )
    }
    
    func pendingDownload(from request: SavePdfInfo) -> PendingDownload? {
        let candidateURLs = [request.url, request.originalUrl].compactMap { $0 }.compactMap(URL.init(string:))
        guard let sourceURL = candidateURLs.first(where: { URLUtils.isWebURL($0) }) else {
            return nil
        }
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: request.filename,
                sourceURL: sourceURL,
                mimeType: "application/pdf"
            ),
            startHandler: { [weak self] in
                self?.enqueueDownload(
                    sourceURL: sourceURL,
                    originalURL: URL(string: request.originalUrl ?? ""),
                    suggestedFileName: request.filename,
                    mimeType: "application/pdf"
                )
            }
        )
    }
    
    func start(_ download: PendingDownload) {
        download.startHandler()
    }

    func importCompletedDownload(
        from sourceFileURL: URL,
        sourceURL: URL,
        suggestedFileName: String?,
        mimeType: String?
    ) -> CompletedDownloadImport? {
        stateQueue.sync {
            prepareStorageLocked()

            let fileName = resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = makeUniqueDestinationURLLocked(for: fileName)
            guard importFileLocked(from: sourceFileURL, to: destinationURL) else {
                return nil
            }

            let fileSize = resolvedFileSize(at: destinationURL) ?? 0
            persistedDownloads.insert(
                PersistedDownloadEntry(
                    id: UUID(),
                    fileName: destinationURL.lastPathComponent,
                    relativePath: destinationURL.lastPathComponent,
                    sourceURLString: sourceURL.absoluteString,
                    originalURLString: nil,
                    mimeType: mimeType,
                    fileSize: fileSize,
                    addedAt: Date()
                ),
                at: 0
            )
            savePersistedDownloadsLocked()
            hasUnviewedCompletedDownloads = true
            postDidStartDownload()
            postDidChange()

            return CompletedDownloadImport(
                fileURL: destinationURL,
                mimeType: mimeType,
                fileSize: fileSize
            )
        }
    }

    func updateCapturedDownload(localFilePath: String, bytesReceived: Int64) -> Bool {
        return stateQueue.sync {
            guard let active = capturedDownloads[localFilePath] else {
                return false
            }
            
            updateCapturedProgress(active, bytesReceived: bytesReceived)
            return true
        }
    }
    
    func completeCapturedDownload(localFilePath: String, succeeded: Bool) {
        stateQueue.sync {
            self.completeCapturedDownloadLocked(
                localFilePath: localFilePath,
                succeeded: succeeded
            )
        }
    }
    
    // MARK: - Download Management
    
    func cancel(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                self.activeDownloads.removeValue(forKey: active.task.taskIdentifier)
                active.task.cancel()
                self.postDidChange()
                return
            }
            
            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }) else {
                return
            }
            
            self.capturedDownloads.removeValue(forKey: captured.localFilePath)
            self.postDidChange()
        }
    }
    
    func removeDownload(id: UUID) {
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
    
    func clearCompletedDownloadFiles(since startDate: Date? = nil) {
        stateQueue.async {
            let removedDownloads: [PersistedDownloadEntry]
            if let startDate {
                removedDownloads = self.persistedDownloads.filter { $0.addedAt >= startDate }
                self.persistedDownloads.removeAll { $0.addedAt >= startDate }
            } else {
                removedDownloads = self.persistedDownloads
                self.persistedDownloads.removeAll()
            }
            
            let fileURLs: [URL]
            if startDate == nil {
                fileURLs = (try? self.fileManager.contentsOfDirectory(
                    at: self.storage.downloadsDirectoryURL,
                    includingPropertiesForKeys: nil
                )) ?? []
            } else {
                fileURLs = removedDownloads.map {
                    self.storage.downloadsDirectoryURL.appendingPathComponent($0.relativePath, isDirectory: false)
                }
            }
            
            for fileURL in Set(fileURLs) {
                try? self.fileManager.removeItem(at: fileURL)
            }
            
            if !self.fileManager.fileExists(atPath: self.storage.downloadsDirectoryURL.path) {
                try? self.fileManager.createDirectory(
                    at: self.storage.downloadsDirectoryURL,
                    withIntermediateDirectories: true
                )
            }
            
            for active in self.activeDownloads.values {
                if let startDate, active.addedAt < startDate {
                    continue
                }
                
                if self.fileManager.fileExists(atPath: active.destinationURL.path) {
                    try? self.fileManager.removeItem(at: active.destinationURL)
                }
            }
            
            self.persistedDownloads.removeAll()
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }
    
    func markCompletedAsViewed() {
        stateQueue.async {
            guard self.hasUnviewedCompletedDownloads else {
                return
            }
            
            self.hasUnviewedCompletedDownloads = false
            self.postDidChange()
        }
    }
    
    // MARK: - Active Downloads
    
    private func beginCapturedDownload(
        localFilePath: String,
        sourceURL: URL,
        suggestedFileName: String?,
        mimeType: String?,
        expectedBytes: Int64?
    ) {
        stateQueue.sync {
            self.prepareStorageLocked()
            
            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            self.capturedDownloads[localFilePath] = CapturedDownload(
                id: UUID(),
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                expectedBytes: expectedBytes
            )
            self.postDidStartDownload()
            self.postDidChange()
        }
    }
    
    private func enqueueDownload(
        sourceURL: URL,
        originalURL: URL?,
        suggestedFileName: String?,
        mimeType: String?
    ) {
        stateQueue.async {
            self.prepareStorageLocked()
            
            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            
            let task = self.session.downloadTask(with: sourceURL)
            let active = ActiveDownload(
                id: UUID(),
                sourceURL: sourceURL,
                originalURL: originalURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                task: task
            )
            
            self.activeDownloads[task.taskIdentifier] = active
            task.resume()
            self.postDidStartDownload()
            self.postDidChange()
        }
    }
    
    // MARK: - Snapshots
    
    private func makeSnapshotLocked() -> DownloadStoreSnapshot {
        let sessionItems = activeDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: active.originalURL,
                    mimeType: active.mimeType,
                    state: .downloading,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt
                )
            }
            .sorted { $0.addedAt > $1.addedAt }
        
        let capturedItems = capturedDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: nil,
                    mimeType: active.mimeType,
                    state: .downloading,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt
                )
            }
        
        let activeItems = (sessionItems + capturedItems)
            .sorted { $0.addedAt > $1.addedAt }
        
        let completedItems = persistedDownloads
            .map { entry in
                let fileURL = storage.downloadsDirectoryURL.appendingPathComponent(entry.relativePath, isDirectory: false)
                return DownloadItemSnapshot(
                    id: entry.id,
                    fileName: entry.fileName,
                    fileURL: fileURL,
                    sourceURL: URL(string: entry.sourceURLString) ?? storage.downloadsDirectoryURL,
                    originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                    mimeType: entry.mimeType,
                    state: .completed,
                    fileExists: fileManager.fileExists(atPath: fileURL.path),
                    totalBytes: entry.fileSize,
                    downloadedBytes: entry.fileSize,
                    bytesPerSecond: 0,
                    addedAt: entry.addedAt
                )
            }
        
        return DownloadStoreSnapshot(summary: makeSummaryLocked(), items: activeItems + completedItems)
    }
    
    private func makeSummaryLocked() -> DownloadStoreSummary {
        let activeProgress = activeDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        + capturedDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        let totalExpectedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.0 ?? 0, 0)
        }
        let totalDownloadedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + min(item.1, item.0 ?? item.1)
        }
        let aggregateProgress: Float
        if totalExpectedBytes > 0 {
            aggregateProgress = Float(totalDownloadedBytes) / Float(totalExpectedBytes)
        } else {
            aggregateProgress = 0
        }
        
        return DownloadStoreSummary(
            totalCount: persistedDownloads.count + activeProgress.count,
            activeCount: activeProgress.count,
            aggregateProgress: min(max(aggregateProgress, 0), 1),
            hasUnviewedCompletedDownloads: hasUnviewedCompletedDownloads
        )
    }
    
    // MARK: - Persistence
    
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
    
    // MARK: - Files
    
    private func resolvedFileName(suggestedFileName: String?, sourceURL: URL, mimeType: String?) -> String {
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? NSLocalizedString("Download", comment: "") : sourceURL.lastPathComponent
        let initialName = sanitizeFileName(suggestedFileName ?? fallbackName)
        
        guard URL(fileURLWithPath: initialName).pathExtension.isEmpty,
              let mimeType,
              let contentType = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
              )?.takeRetainedValue(),
              let preferredExtension = UTTypeCopyPreferredTagWithClass(
                contentType,
                kUTTagClassFilenameExtension
              )?.takeRetainedValue() as String? else {
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
        
        return sanitized.isEmpty ? NSLocalizedString("Download", comment: "") : sanitized
    }
    
    private func makeUniqueDestinationURLLocked(for fileName: String) -> URL {
        let candidateURL = storage.downloadsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        let activeNames = Set(
            activeDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
            + capturedDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
        )
        
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
    
    private func importFileLocked(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return false
        }
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try? fileManager.removeItem(at: sourceURL)
            }
            
            return true
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return false
        }
    }
    
    // MARK: - Transfer Lifecycle
    
    private func completeCapturedDownloadLocked(localFilePath: String, succeeded: Bool) {
        guard let active = capturedDownloads.removeValue(forKey: localFilePath) else {
            try? fileManager.removeItem(at: URL(fileURLWithPath: localFilePath))
            return
        }
        
        guard succeeded else {
            postDidChange()
            return
        }
        
        let sourceFileURL = URL(fileURLWithPath: localFilePath)
        prepareStorageLocked()
        
        guard importFileLocked(from: sourceFileURL, to: active.destinationURL) else {
            postDidChange()
            return
        }
        
        let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
        persistedDownloads.insert(
            PersistedDownloadEntry(
                id: active.id,
                fileName: active.fileName,
                relativePath: active.destinationURL.lastPathComponent,
                sourceURLString: active.sourceURL.absoluteString,
                originalURLString: nil,
                mimeType: active.mimeType,
                fileSize: fileSize,
                addedAt: active.addedAt
            ),
            at: 0
        )
        savePersistedDownloadsLocked()
        hasUnviewedCompletedDownloads = true
        postDidChange()
    }
    
    private func updateCapturedProgress(_ active: CapturedDownload, bytesReceived: Int64) {
        active.downloadedBytes = bytesReceived
        updateTransferRate(
            totalBytesWritten: bytesReceived,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )
        postDidChange()
    }
    
    private func updateTransferRate(
        totalBytesWritten: Int64,
        bytesPerSecond: inout Int64,
        lastProgressSample: inout ProgressSample?
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previousSample = lastProgressSample {
            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaBytes = max(totalBytesWritten - previousSample.bytesWritten, 0)
            let instantaneousSpeed = Int64(Double(deltaBytes) / deltaTime)
            if bytesPerSecond == 0 {
                bytesPerSecond = instantaneousSpeed
            } else {
                let smoothedSpeed = (Double(bytesPerSecond) * 0.65) + (Double(instantaneousSpeed) * 0.35)
                bytesPerSecond = Int64(smoothedSpeed)
            }
        }
        lastProgressSample = ProgressSample(bytesWritten: totalBytesWritten, timestamp: now)
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
        
        postDidChange()
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
        
        updateTransferRate(
            totalBytesWritten: totalBytesWritten,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )
        
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSessionProgressNotificationTime >= 0.5 {
            lastSessionProgressNotificationTime = now
            postDidChange()
        }
    }
    
    private func failDownload(taskIdentifier: Int) {
        guard activeDownloads.removeValue(forKey: taskIdentifier) != nil else {
            return
        }
        
        postDidChange()
    }
    
    // MARK: - Notifications
    
    private func postDidChange() {
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
