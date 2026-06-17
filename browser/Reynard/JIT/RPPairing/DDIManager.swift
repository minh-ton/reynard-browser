//
//  DDIManager.swift
//  Reynard
//
//  Created by Minh Ton on 23/3/26.
//

import Foundation

final class DDIManager: NSObject {
    enum DDIError: LocalizedError {
        case alreadyInProgress
        case cancelled
        case appSupportDirUnavail
        case invalidRuntimeVersion
        case invalidRemoteURL
        
        var errorDescription: String? {
            switch self {
            case .alreadyInProgress:
                return "A Developer Disk Image download is already in progress."
            case .cancelled:
                return "Developer Disk Image download was cancelled."
            case .appSupportDirUnavail:
                return "Unable to access the app Application Support directory."
            case .invalidRuntimeVersion:
                return "Unable to determine the iOS version needed for Developer Disk Image download."
            case .invalidRemoteURL:
                return "Developer Disk Image source URL is invalid."
            }
        }
    }
    
    static let shared = DDIManager()
    
    private struct DownloadItem {
        let remoteURL: URL
        let destinationURL: URL
    }
    
    private struct DownloadPlan {
        let rootDirectoryURL: URL
        let items: [DownloadItem]
    }
    
    private struct ActiveDownload {
        var plan: DownloadPlan
        var currentIndex: Int
        var currentTask: URLSessionDownloadTask?
        let progressHandler: (Double) -> Void
        let completion: (Result<Void, Error>) -> Void
    }
    
    private let fileManager: FileManager
    private let stateQueue = DispatchQueue(label: "com.minh-ton.ddi-manager-queue", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private var activeDownload: ActiveDownload?
    
    override init() {
        self.fileManager = .default
        super.init()
    }
    
    func hasRequiredDDIFiles() -> Bool {
        guard let plan = try? makeDownloadPlan() else {
            return false
        }
        
        return plan.items.allSatisfy { fileManager.fileExists(atPath: $0.destinationURL.path) }
    }
    
    func ensureRequiredDDIFiles(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if hasRequiredDDIFiles() {
            DispatchQueue.main.async {
                progress(1)
                completion(.success(()))
            }
            return
        }
        
        stateQueue.async {
            if self.activeDownload != nil {
                self.dispatchCompletion(.failure(DDIError.alreadyInProgress), completion)
                return
            }
            
            do {
                let plan = try self.makeDownloadPlan()
                try self.ensureDDIRootDirectoryExists(at: plan.rootDirectoryURL)
                
                self.activeDownload = ActiveDownload(
                    plan: plan,
                    currentIndex: 0,
                    currentTask: nil,
                    progressHandler: progress,
                    completion: completion
                )
                
                self.dispatchProgress(0, handler: progress)
                self.startNextDownloadLocked()
            } catch {
                self.dispatchCompletion(.failure(error), completion)
            }
        }
    }
    
    func cancelActiveDownload() {
        stateQueue.async {
            guard let active = self.activeDownload else {
                _ = try? self.removeDDIRootDirectory()
                return
            }
            
            active.currentTask?.cancel()
            self.finishActiveDownloadLocked(result: .failure(DDIError.cancelled), shouldCleanup: true)
        }
    }
    
    private func startNextDownloadLocked() {
        guard var active = activeDownload else {
            return
        }
        
        guard active.currentIndex < active.plan.items.count else {
            finishActiveDownloadLocked(result: .success(()), shouldCleanup: false)
            return
        }
        
        let item = active.plan.items[active.currentIndex]
        
        do {
            try fileManager.createDirectory(
                at: item.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            if fileManager.fileExists(atPath: item.destinationURL.path) {
                try fileManager.removeItem(at: item.destinationURL)
            }
        } catch {
            finishActiveDownloadLocked(result: .failure(error), shouldCleanup: true)
            return
        }
        
        let task = session.downloadTask(with: item.remoteURL)
        active.currentTask = task
        activeDownload = active
        task.resume()
    }
    
    private func completeCurrentFileDownload(location: URL, taskIdentifier: Int) {
        guard var active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }
        
        let item = active.plan.items[active.currentIndex]
        
        do {
            try fileManager.createDirectory(
                at: item.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            if fileManager.fileExists(atPath: item.destinationURL.path) {
                try fileManager.removeItem(at: item.destinationURL)
            }
            
            try fileManager.moveItem(at: location, to: item.destinationURL)
        } catch {
            finishActiveDownloadLocked(result: .failure(error), shouldCleanup: true)
            return
        }
        
        active.currentTask = nil
        active.currentIndex += 1
        activeDownload = active
        
        let completedRatio = Double(active.currentIndex) / Double(active.plan.items.count)
        dispatchProgress(completedRatio, handler: active.progressHandler)
        startNextDownloadLocked()
    }
    
    private func handleDownloadProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }
        
        let fileProgress: Double
        if totalBytesExpectedToWrite > 0 {
            fileProgress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        } else {
            fileProgress = 0
        }
        
        let overallProgress = (Double(active.currentIndex) + fileProgress) / Double(active.plan.items.count)
        dispatchProgress(min(max(overallProgress, 0), 0.999), handler: active.progressHandler)
    }
    
    private func handleTaskFailure(taskIdentifier: Int, error: Error) {
        guard let active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }
        
        if let urlError = error as? URLError, urlError.code == .cancelled {
            finishActiveDownloadLocked(result: .failure(DDIError.cancelled), shouldCleanup: true)
            return
        }
        
        finishActiveDownloadLocked(result: .failure(error), shouldCleanup: false)
    }
    
    private func finishActiveDownloadLocked(result: Result<Void, Error>, shouldCleanup: Bool) {
        guard let active = activeDownload else {
            return
        }
        
        active.currentTask?.cancel()
        activeDownload = nil
        
        if shouldCleanup {
            _ = try? removeDDIRootDirectory()
        }
        
        if case .success = result {
            dispatchProgress(1, handler: active.progressHandler)
        }
        
        dispatchCompletion(result, active.completion)
    }
    
    private func dispatchProgress(_ value: Double, handler: @escaping (Double) -> Void) {
        let clamped = min(max(value, 0), 1)
        DispatchQueue.main.async {
            handler(clamped)
        }
    }
    
    private func dispatchCompletion(
        _ result: Result<Void, Error>,
        _ completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
    
    private func ensureDDIRootDirectoryExists(at rootDirectoryURL: URL) throws {
        guard !fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return
        }
        
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }
    
    private func removeDDIRootDirectory() throws {
        let rootDirectoryURL = try ddiRootDirectoryURL()
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return
        }
        
        try fileManager.removeItem(at: rootDirectoryURL)
    }
    
    private func makeDownloadPlan() throws -> DownloadPlan {
        let rootDirectoryURL = try ddiRootDirectoryURL()
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        
        if operatingSystemVersion.majorVersion >= 17 {
            let baseURLString = "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized"
            guard let baseURL = URL(string: baseURLString) else {
                throw DDIError.invalidRemoteURL
            }
            
            let fileNames = ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
            let items = fileNames.map { fileName in
                DownloadItem(
                    remoteURL: baseURL.appendingPathComponent(fileName),
                    destinationURL: rootDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
                )
            }
            
            return DownloadPlan(rootDirectoryURL: rootDirectoryURL, items: items)
        }
        
        guard operatingSystemVersion.majorVersion > 0 else {
            throw DDIError.invalidRuntimeVersion
        }
        
        let versionString = "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion)"
        let baseURLString = "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/DeveloperDiskImages/\(versionString)"
        
        guard let baseURL = URL(string: baseURLString) else {
            throw DDIError.invalidRemoteURL
        }
        
        let fileNames = ["DeveloperDiskImage.dmg", "DeveloperDiskImage.dmg.signature"]
        let items = fileNames.map { fileName in
            DownloadItem(
                remoteURL: baseURL.appendingPathComponent(fileName),
                destinationURL: rootDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            )
        }
        
        return DownloadPlan(rootDirectoryURL: rootDirectoryURL, items: items)
    }
    
    private func ddiRootDirectoryURL() throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DDIError.appSupportDirUnavail
        }
        
        return applicationSupportDirectory.appendingPathComponent("DDI", isDirectory: true)
    }
}

extension DDIManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        stateQueue.async {
            self.handleDownloadProgress(
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
            self.completeCurrentFileDownload(location: location, taskIdentifier: downloadTask.taskIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        
        stateQueue.async {
            self.handleTaskFailure(taskIdentifier: task.taskIdentifier, error: error)
        }
    }
}
