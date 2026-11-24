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
    let activeCount: Int
    let aggregateProgress: Float
    let hasUnviewedCompletedDownloads: Bool
    
    var showsToolbarButton: Bool {
        return activeCount > 0 || hasUnviewedCompletedDownloads
    }
}

struct DownloadStoreSnapshot {
    let items: [DownloadItemSnapshot]
}

struct DownloadItemSnapshot {
    enum State: Equatable {
        case downloading
        case paused
        case cancelled
        case failed
        case completed
    }
    
    let id: UUID
    let fileName: String
    let fileURL: URL?
    let sourceURL: URL
    let originalURL: URL?
    let mimeType: String?
    let state: State
    let canPause: Bool
    let fileExists: Bool
    let totalBytes: Int64?
    let downloadedBytes: Int64
    let bytesPerSecond: Int64
    let addedAt: Date
}

final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    
    struct WebExtensionDownloadItem {
        let id: Int
        let fileName: String
        let localFilePath: String
        let mimeType: String?
        let addedAt: Date
    }
    
    struct PendingDownload {
        let fileName: String
        fileprivate let startHandler: (_ initiatorID: UUID) -> WebExtensionDownloadItem?
    }
    
    private struct StorageURLs {
        let downloadsDirectoryURL: URL
        let appDataDirectoryURL: URL
        let manifestFileURL: URL
    }
    
    private enum PersistedDownloadState: String, Codable {
        case inProgress = "active"
        case cancelled
        case completed
        case failed
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
        var state: PersistedDownloadState?
        
        var effectiveState: PersistedDownloadState {
            return state ?? .completed
        }
    }
    
    private struct ProgressSample {
        let bytesWritten: Int64
        let timestamp: TimeInterval
    }
    
    private final class ActiveDownload {
        let id: UUID
        let initiatorID: UUID
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
        var isPaused: Bool
        
        init(
            id: UUID,
            initiatorID: UUID,
            sourceURL: URL,
            originalURL: URL?,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            task: URLSessionDownloadTask
        ) {
            self.id = id
            self.initiatorID = initiatorID
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
            self.isPaused = false
        }
    }
    
    private struct CapturedDownloadControls {
        let cancel: () -> Void
        let pause: () -> Void
        let resume: () -> Void
    }
    
    private final class CapturedDownload {
        let id: UUID
        let initiatorID: UUID
        let localFilePath: String
        let sourceURL: URL
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        let controls: CapturedDownloadControls?
        weak var originatingSession: GeckoSession?
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        var isPaused: Bool
        
        init(
            id: UUID,
            initiatorID: UUID,
            localFilePath: String,
            sourceURL: URL,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            expectedBytes: Int64?,
            controls: CapturedDownloadControls? = nil,
            originatingSession: GeckoSession? = nil
        ) {
            self.id = id
            self.initiatorID = initiatorID
            self.localFilePath = localFilePath
            self.sourceURL = sourceURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.controls = controls
            self.originatingSession = originatingSession
            self.expectedBytes = expectedBytes
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
            self.isPaused = false
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
    private var unviewedDownloadInitiatorIDs: [UUID: UUID] = [:]
    private var nextWebExtensionDownloadID = 1
    
    // MARK: - Lifecycle
    
    override init() {
        self.fileManager = .default
        
        guard let documentsDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory is unavailable")
        }
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        let downloadsDirectoryURL = documentsDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        let appDataDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
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
    
    func summary(for initiatorID: UUID) -> DownloadStoreSummary {
        stateQueue.sync {
            makeSummaryLocked(for: initiatorID)
        }
    }
    
    // MARK: - Pending Downloads
    
    func pendingDownload(from response: ExternalResponseInfo, session: GeckoSession) -> PendingDownload? {
        guard let sourceURL = URL(string: response.url) else {
            return nil
        }
        
        let fileName = sanitizedFileName(
            suggestedFileName: response.filename,
            sourceURL: sourceURL
        )
        let controls = CapturedDownloadControls(
            cancel: response.cancel,
            pause: response.pause,
            resume: response.resume
        )
        
        return PendingDownload(
            fileName: fileName,
            startHandler: { [weak self] initiatorID in
                self?.beginCapturedDownload(
                    initiatorID: initiatorID,
                    localFilePath: response.localFilePath,
                    sourceURL: sourceURL,
                    fileName: fileName,
                    mimeType: response.mimeType,
                    expectedBytes: response.contentLength,
                    controls: controls,
                    originatingSession: session
                )
                return nil
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
            startHandler: { [weak self] initiatorID in
                self?.enqueueDownload(
                    initiatorID: initiatorID,
                    sourceURL: sourceURL,
                    originalURL: URL(string: request.originalUrl ?? ""),
                    suggestedFileName: request.filename,
                    mimeType: "application/pdf"
                )
                return nil
            }
        )
    }
    
    func pendingDownload(from options: [String: Any?]) -> PendingDownload? {
        guard let urlString = options["url"] as? String,
              let sourceURL = URL(string: urlString) else {
            return nil
        }
        
        let suggestedFileName = options["filename"] as? String
        let mimeType = options["mimeType"] as? String
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            ),
            startHandler: { [weak self] initiatorID in
                self?.beginWebExtensionDownload(
                    initiatorID: initiatorID,
                    sourceURL: sourceURL,
                    suggestedFileName: suggestedFileName,
                    mimeType: mimeType
                )
            }
        )
    }
    
    @discardableResult
    func startDownload(_ pendingDownload: PendingDownload, initiatorID: UUID) -> WebExtensionDownloadItem? {
        return pendingDownload.startHandler(initiatorID)
    }
    
    // MARK: - Captured Download Events
    
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
    
    func failCapturedDownloads(for session: GeckoSession) {
        stateQueue.sync {
            let terminatedDownloads = capturedDownloads.values.filter {
                $0.originatingSession === session
            }
            for download in terminatedDownloads {
                capturedDownloads.removeValue(forKey: download.localFilePath)
                storePersistedEntryLocked(
                    makePersistedEntry(for: download, state: .failed)
                )
            }
            if !terminatedDownloads.isEmpty {
                postDidChange()
            }
        }
    }
    
    // MARK: - Download Management
    
    func cancel(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                self.activeDownloads.removeValue(forKey: active.task.taskIdentifier)
                self.storePersistedEntryLocked(
                    self.makePersistedEntry(for: active, state: .cancelled)
                )
                active.task.cancel()
                self.postDidChange()
                return
            }
            
            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }) else {
                return
            }
            
            self.capturedDownloads.removeValue(forKey: captured.localFilePath)
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: captured, state: .cancelled)
            )
            captured.controls?.cancel()
            self.postDidChange()
        }
    }
    
    func pause(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                guard !active.isPaused else {
                    return
                }
                
                active.task.suspend()
                active.isPaused = true
                active.bytesPerSecond = 0
                active.lastProgressSample = nil
                self.postDidChange()
                return
            }
            
            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }),
                  let controls = captured.controls,
                  !captured.isPaused else {
                return
            }
            
            controls.pause()
            captured.isPaused = true
            captured.bytesPerSecond = 0
            captured.lastProgressSample = nil
            self.postDidChange()
        }
    }
    
    func resume(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                guard active.isPaused else {
                    return
                }
                
                active.task.resume()
                active.isPaused = false
                active.bytesPerSecond = 0
                active.lastProgressSample = nil
                self.postDidChange()
                return
            }
            
            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }),
                  let controls = captured.controls,
                  captured.isPaused else {
                return
            }
            
            controls.resume()
            captured.isPaused = false
            captured.bytesPerSecond = 0
            captured.lastProgressSample = nil
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
            let removedDownloads = self.persistedDownloads.filter { entry in
                guard entry.effectiveState != .inProgress else {
                    return false
                }
                return startDate.map { entry.addedAt >= $0 } ?? true
            }
            let removedIDs = Set(removedDownloads.map(\.id))
            self.persistedDownloads.removeAll { removedIDs.contains($0.id) }
            
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
            
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }
    
    func markCompletedAsViewed() {
        stateQueue.async {
            guard !self.unviewedDownloadInitiatorIDs.isEmpty else {
                return
            }
            
            self.unviewedDownloadInitiatorIDs.removeAll()
            self.postDidChange()
        }
    }
    
    // MARK: - Captured Downloads
    
    private func beginCapturedDownload(
        initiatorID: UUID,
        localFilePath: String,
        sourceURL: URL,
        fileName: String,
        mimeType: String?,
        expectedBytes: Int64?,
        controls: CapturedDownloadControls,
        originatingSession: GeckoSession
    ) {
        stateQueue.sync {
            self.prepareStorageLocked()
            
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            let active = CapturedDownload(
                id: UUID(),
                initiatorID: initiatorID,
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                expectedBytes: expectedBytes,
                controls: controls,
                originatingSession: originatingSession
            )
            self.capturedDownloads[localFilePath] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
            self.postDidStartDownload()
            self.postDidChange()
        }
    }
    
    private func beginWebExtensionDownload(
        initiatorID: UUID,
        sourceURL: URL,
        suggestedFileName: String?,
        mimeType: String?
    ) -> WebExtensionDownloadItem? {
        return stateQueue.sync {
            self.prepareStorageLocked()
            
            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            let localFilePath = self.fileManager.temporaryDirectory
                .appendingPathComponent(
                    "WebExtension-\(UUID().uuidString)",
                    isDirectory: false
                )
                .path
            let downloadID = self.nextWebExtensionDownloadID
            self.nextWebExtensionDownloadID += 1
            let addedAt = Date()
            
            let active = CapturedDownload(
                id: UUID(),
                initiatorID: initiatorID,
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: addedAt,
                expectedBytes: nil
            )
            self.capturedDownloads[localFilePath] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
            self.postDidStartDownload()
            self.postDidChange()
            
            return WebExtensionDownloadItem(
                id: downloadID,
                fileName: destinationURL.lastPathComponent,
                localFilePath: localFilePath,
                mimeType: mimeType,
                addedAt: addedAt
            )
        }
    }
    
    // MARK: - URL Session Downloads
    
    private func enqueueDownload(
        initiatorID: UUID,
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
                initiatorID: initiatorID,
                sourceURL: sourceURL,
                originalURL: originalURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                task: task
            )
            
            self.activeDownloads[task.taskIdentifier] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
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
                    state: active.isPaused ? .paused : .downloading,
                    canPause: true,
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
                let canPause = active.controls != nil
                return DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: nil,
                    mimeType: active.mimeType,
                    state: active.isPaused && canPause ? .paused : .downloading,
                    canPause: canPause,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt
                )
            }
        
        let activeItems = (sessionItems + capturedItems)
            .sorted { $0.addedAt > $1.addedAt }
        
        let terminalItems = persistedDownloads
            .compactMap { entry -> DownloadItemSnapshot? in
                guard entry.effectiveState != .inProgress else {
                    return nil
                }
                
                let fileURL = storage.downloadsDirectoryURL.appendingPathComponent(entry.relativePath, isDirectory: false)
                let isCompleted = entry.effectiveState == .completed
                let itemState: DownloadItemSnapshot.State
                if entry.effectiveState == .cancelled {
                    itemState = .cancelled
                } else if isCompleted {
                    itemState = .completed
                } else {
                    itemState = .failed
                }
                return DownloadItemSnapshot(
                    id: entry.id,
                    fileName: entry.fileName,
                    fileURL: isCompleted ? fileURL : nil,
                    sourceURL: URL(string: entry.sourceURLString) ?? storage.downloadsDirectoryURL,
                    originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                    mimeType: entry.mimeType,
                    state: itemState,
                    canPause: false,
                    fileExists: isCompleted && fileManager.fileExists(atPath: fileURL.path),
                    totalBytes: isCompleted ? entry.fileSize : nil,
                    downloadedBytes: isCompleted ? entry.fileSize : 0,
                    bytesPerSecond: 0,
                    addedAt: entry.addedAt
                )
            }
        
        return DownloadStoreSnapshot(items: activeItems + terminalItems)
    }
    
    private func makeSummaryLocked(for initiatorID: UUID) -> DownloadStoreSummary {
        let activeProgress = activeDownloads.values
            .filter { $0.initiatorID == initiatorID }
            .map { ($0.expectedBytes, $0.downloadedBytes) }
        + capturedDownloads.values
            .filter { $0.initiatorID == initiatorID }
            .map { ($0.expectedBytes, $0.downloadedBytes) }
        let hasUnknownExpectedBytes = activeProgress.contains { $0.0 == nil }
        let totalExpectedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.0 ?? 0, 0)
        }
        let totalDownloadedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + min(item.1, item.0 ?? item.1)
        }
        let aggregateProgress: Float
        if totalExpectedBytes > 0 && !hasUnknownExpectedBytes {
            aggregateProgress = Float(totalDownloadedBytes) / Float(totalExpectedBytes)
        } else {
            aggregateProgress = 0
        }
        
        let hasUnviewedCompletedDownloads = persistedDownloads.contains {
            unviewedDownloadInitiatorIDs[$0.id] == initiatorID
        }
        return DownloadStoreSummary(
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
        
        if var entries = try? JSONDecoder().decode([PersistedDownloadEntry].self, from: data) {
            var markedInterruptedDownloadsAsFailed = false
            for index in entries.indices where entries[index].effectiveState == .inProgress {
                entries[index].state = .failed
                let destinationURL = storage.downloadsDirectoryURL.appendingPathComponent(
                    entries[index].relativePath,
                    isDirectory: false
                )
                try? fileManager.removeItem(at: destinationURL)
                markedInterruptedDownloadsAsFailed = true
            }
            persistedDownloads = entries.sorted { $0.addedAt > $1.addedAt }
            if markedInterruptedDownloadsAsFailed {
                savePersistedDownloadsLocked()
            }
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
    
    private func makePersistedEntry(
        for download: ActiveDownload,
        state: PersistedDownloadState,
        fileSize: Int64 = 0
    ) -> PersistedDownloadEntry {
        return PersistedDownloadEntry(
            id: download.id,
            fileName: download.fileName,
            relativePath: download.destinationURL.lastPathComponent,
            sourceURLString: download.sourceURL.absoluteString,
            originalURLString: download.originalURL?.absoluteString,
            mimeType: download.mimeType,
            fileSize: fileSize,
            addedAt: download.addedAt,
            state: state
        )
    }
    
    private func makePersistedEntry(
        for download: CapturedDownload,
        state: PersistedDownloadState,
        fileSize: Int64 = 0
    ) -> PersistedDownloadEntry {
        return PersistedDownloadEntry(
            id: download.id,
            fileName: download.fileName,
            relativePath: download.destinationURL.lastPathComponent,
            sourceURLString: download.sourceURL.absoluteString,
            originalURLString: nil,
            mimeType: download.mimeType,
            fileSize: fileSize,
            addedAt: download.addedAt,
            state: state
        )
    }
    
    private func storePersistedEntryLocked(_ entry: PersistedDownloadEntry) {
        if let index = persistedDownloads.firstIndex(where: { $0.id == entry.id }) {
            persistedDownloads[index] = entry
        } else {
            persistedDownloads.insert(entry, at: 0)
        }
        savePersistedDownloadsLocked()
    }
    
    // MARK: - Files
    
    private func resolvedFileName(
        suggestedFileName: String?,
        sourceURL: URL,
        mimeType: String?
    ) -> String {
        let initialName = sanitizedFileName(
            suggestedFileName: suggestedFileName,
            sourceURL: sourceURL
        )
        
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
    
    private func sanitizedFileName(suggestedFileName: String?, sourceURL: URL) -> String {
        let fallbackName = sourceURL.lastPathComponent.isEmpty
        ? NSLocalizedString("Download", comment: "")
        : sourceURL.lastPathComponent
        let candidateName: String
        if let suggestedFileName = suggestedFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggestedFileName.isEmpty {
            candidateName = suggestedFileName
        } else {
            candidateName = fallbackName
        }
        return sanitizeFileName(candidateName)
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
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed)
            )
            postDidChange()
            return
        }
        
        let sourceFileURL = URL(fileURLWithPath: localFilePath)
        prepareStorageLocked()
        
        guard importFileLocked(from: sourceFileURL, to: active.destinationURL) else {
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed)
            )
            postDidChange()
            return
        }
        
        let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
        storePersistedEntryLocked(
            makePersistedEntry(for: active, state: .completed, fileSize: fileSize)
        )
        unviewedDownloadInitiatorIDs[active.id] = active.initiatorID
        postDidChange()
    }
    
    private func updateCapturedProgress(_ active: CapturedDownload, bytesReceived: Int64) {
        active.downloadedBytes = bytesReceived
        guard !active.isPaused else {
            postDidChange()
            return
        }
        
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
            
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .completed, fileSize: fileSize)
            )
            unviewedDownloadInitiatorIDs[active.id] = active.initiatorID
        } catch {
            try? fileManager.removeItem(at: temporaryLocation)
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed)
            )
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
        
        guard !active.isPaused else {
            postDidChange()
            return
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
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }
        
        storePersistedEntryLocked(
            makePersistedEntry(for: active, state: .failed)
        )
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
