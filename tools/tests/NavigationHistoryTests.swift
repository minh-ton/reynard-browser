import Foundation

final class FaultInjectingNavigationHistoryFileSystem: NavigationHistoryFileSystem {
    enum Failure {
        case none
        case unavailableLocation
        case create
        case read
        case write
    }

    private let base = FoundationNavigationHistoryFileSystem()
    let failure: Failure

    init(failure: Failure) {
        self.failure = failure
    }

    func applicationSupportDirectoryURL() -> URL? {
        failure == .unavailableLocation ? nil : base.applicationSupportDirectoryURL()
    }

    func createDirectory(at url: URL) throws {
        if failure == .create {
            throw CocoaError(.fileWriteNoPermission)
        }
        try base.createDirectory(at: url)
    }

    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        if failure == .read {
            throw CocoaError(.fileReadNoPermission)
        }
        return try base.readData(at: url, options: options)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if failure == .write {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try base.writeData(data, to: url, options: options)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }
}

@main
struct NavigationHistoryTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reynard-navigation-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let tabID = UUID()
        let store = NavigationHistoryStore(
            storageURL: root,
            configuration: NavigationHistoryConfiguration(
                maximumEntryCount: 3,
                maximumCachedTabCount: 4
            )
        )
        for url in ["https://a.example", "https://b.example", "https://c.example", "https://d.example", "https://e.example"] {
            _ = store.recordNavigation(to: url, for: tabID)
        }

        var snapshot = store.currentSnapshot(for: tabID)
        precondition(snapshot.currentURL == "https://e.example")
        precondition(snapshot.backHistory == ["https://b.example", "https://c.example", "https://d.example"])
        precondition(snapshot.forwardHistory.isEmpty)

        _ = store.recordNavigation(to: "https://e.example", for: tabID)
        precondition(store.currentSnapshot(for: tabID).backHistory == snapshot.backHistory)

        let thumbnailData = Data(repeating: 0x2A, count: 64 * 1024)
        let thumbnail = NavigationPreviewImage(data: thumbnailData)
        store.updateCurrentHistoryThumbnail(
            thumbnail,
            for: tabID,
            matching: "https://e.example"
        )
        store.flushPendingWritesForTesting()
        _ = store.recordNavigation(to: "https://f.example", for: tabID)
        precondition(store.currentSnapshot(for: tabID).backPreviewImage != nil)

        precondition(store.goBack(for: tabID) == "https://e.example")
        precondition(store.goBack(for: tabID) == "https://d.example")
        precondition(store.goForward(for: tabID) == "https://e.example")
        snapshot = store.currentSnapshot(for: tabID)
        precondition(snapshot.currentURL == "https://e.example")
        precondition(snapshot.canGoBack)
        precondition(snapshot.canGoForward)

        store.flushPendingWritesForTesting()
        let restoredStore = NavigationHistoryStore(
            storageURL: root,
            configuration: NavigationHistoryConfiguration(
                maximumEntryCount: 3,
                maximumCachedTabCount: 4
            )
        )
        let restored = restoredStore.currentSnapshot(for: tabID)
        precondition(restored.currentURL == snapshot.currentURL)
        precondition(restored.backHistory == snapshot.backHistory)
        precondition(restored.forwardHistory == snapshot.forwardHistory)

        let serializedHistory = try Data(contentsOf: root.appendingPathComponent(tabID.uuidString))
        precondition(serializedHistory.count < thumbnailData.count)
        precondition(!serializedHistory.base64EncodedString().contains(thumbnailData.base64EncodedString()))
        precondition(String(decoding: serializedHistory, as: UTF8.self).contains("\"version\":1"))

        for index in 0..<20 {
            let stressTabID = UUID()
            for page in 0..<50 {
                _ = restoredStore.recordNavigation(
                    to: "https://stress-\(index).example/\(page)",
                    for: stressTabID
                )
            }
            restoredStore.updateCurrentHistoryThumbnail(
                thumbnail,
                for: stressTabID,
                matching: "https://stress-\(index).example/49"
            )
        }
        restoredStore.flushPendingWrites()
        let metrics = restoredStore.cacheMetricsForTesting()
        precondition(metrics.cachedTabCount <= 4)
        precondition(metrics.previewByteCount <= 4 * thumbnailData.count)
        precondition(metrics.pendingWriteCount == 0)

        let history = NavigationHistory(store: restoredStore)
        let liveAvailability = history.availability(
            for: UUID(),
            sessionState: .available(back: true, forward: false)
        )
        precondition(liveAvailability.canGoBack)
        precondition(!liveAvailability.canGoForward)

        restoredStore.removeNavigationHistory(for: tabID)
        restoredStore.flushPendingWritesForTesting()
        precondition(restoredStore.currentSnapshot(for: tabID).currentURL == nil)

        let removedTabID = UUID()
        _ = restoredStore.recordNavigation(to: "https://removed.example", for: removedTabID)
        restoredStore.updateCurrentHistoryThumbnail(
            thumbnail,
            for: removedTabID,
            matching: "https://removed.example"
        )
        restoredStore.removeNavigationHistory(for: removedTabID)
        restoredStore.flushPendingWrites()
        precondition(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(removedTabID.uuidString).path
        ))

        let corruptTabID = UUID()
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent(corruptTabID.uuidString),
            options: .atomic
        )
        precondition(restoredStore.currentSnapshot(for: corruptTabID).currentURL == nil)
        precondition(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(corruptTabID.uuidString).path
        ))
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(quarantinedFiles.contains {
            $0.lastPathComponent.hasPrefix("\(corruptTabID.uuidString).corrupt-")
        })

        let rejectedTabID = UUID()
        for rejectedURL in [
            "about:blank",
            "javascript:alert(1)",
            "data:text/plain,private",
            "blob:https://example.com/value",
            String(repeating: "x", count: 64 * 1024) + "https://oversized.example"
        ] {
            _ = restoredStore.recordNavigation(to: rejectedURL, for: rejectedTabID)
        }
        restoredStore.flushPendingWritesForTesting()
        precondition(restoredStore.currentSnapshot(for: rejectedTabID).currentURL == nil)
        precondition(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(rejectedTabID.uuidString).path
        ))

        let boundaryConfiguration = NavigationHistoryConfiguration(maximumEncodedURLBytes: 32)
        let boundaryPolicy = NavigationPersistencePolicy(configuration: boundaryConfiguration)
        let acceptedBoundaryURL = "https://example.com/" + String(repeating: "a", count: 12)
        precondition(acceptedBoundaryURL.utf8.count == 32)
        precondition(boundaryPolicy.persistableURL(from: acceptedBoundaryURL) == acceptedBoundaryURL)
        precondition(boundaryPolicy.persistableURL(from: acceptedBoundaryURL + "a") == nil)

        let privateRoot = root.appendingPathComponent("private")
        let privateStore = NavigationHistoryStore(storageURL: privateRoot)
        let privateHistory = NavigationHistory(store: privateStore)
        let privateTabID = UUID()
        let privateAvailability = privateHistory.record(
            to: "https://private.example",
            for: privateTabID,
            sessionState: .available(back: true, forward: false),
            storageMode: .memoryOnly
        )
        privateStore.flushPendingWritesForTesting()
        precondition(privateAvailability.canGoBack)
        precondition(privateStore.currentSnapshot(for: privateTabID).currentURL == nil)
        precondition(!FileManager.default.fileExists(
            atPath: privateRoot.appendingPathComponent(privateTabID.uuidString).path
        ))

        let rapidRoot = root.appendingPathComponent("rapid")
        let rapidTabID = UUID()
        let rapidStore = NavigationHistoryStore(storageURL: rapidRoot)
        for index in 0..<500 {
            _ = rapidStore.recordNavigation(to: "https://rapid.example/\(index)", for: rapidTabID)
        }
        rapidStore.flushPendingWritesForTesting()
        let rapidRestoredStore = NavigationHistoryStore(storageURL: rapidRoot)
        precondition(rapidRestoredStore.currentSnapshot(for: rapidTabID).currentURL == "https://rapid.example/499")

        let reopenedRoot = root.appendingPathComponent("reopened")
        let reopenedTabID = UUID()
        let reopenedStore = NavigationHistoryStore(storageURL: reopenedRoot)
        _ = reopenedStore.recordNavigation(to: "https://old.example", for: reopenedTabID)
        reopenedStore.flushPendingWritesForTesting()
        reopenedStore.removeNavigationHistory(for: reopenedTabID)
        _ = reopenedStore.recordNavigation(to: "https://new.example", for: reopenedTabID)
        reopenedStore.flushPendingWritesForTesting()
        let reopenedRestoredStore = NavigationHistoryStore(storageURL: reopenedRoot)
        precondition(reopenedRestoredStore.currentSnapshot(for: reopenedTabID).currentURL == "https://new.example")

        let writeFailureRoot = root.appendingPathComponent("write-failure")
        let writeFailureStore = NavigationHistoryStore(
            fileSystem: FaultInjectingNavigationHistoryFileSystem(failure: .write),
            storageURL: writeFailureRoot
        )
        let writeFailureTabID = UUID()
        _ = writeFailureStore.recordNavigation(to: "https://memory.example", for: writeFailureTabID)
        writeFailureStore.flushPendingWritesForTesting()
        let writeFailureMetrics = writeFailureStore.cacheMetricsForTesting()
        precondition(writeFailureStore.currentSnapshot(for: writeFailureTabID).currentURL == "https://memory.example")
        precondition(!writeFailureMetrics.isPersistenceAvailable)
        precondition(writeFailureMetrics.persistenceFailureCount == 1)

        let readFailureRoot = root.appendingPathComponent("read-failure")
        let readableStore = NavigationHistoryStore(storageURL: readFailureRoot)
        let readFailureTabID = UUID()
        _ = readableStore.recordNavigation(to: "https://unreadable.example", for: readFailureTabID)
        readableStore.flushPendingWritesForTesting()
        let readFailureStore = NavigationHistoryStore(
            fileSystem: FaultInjectingNavigationHistoryFileSystem(failure: .read),
            storageURL: readFailureRoot
        )
        precondition(readFailureStore.currentSnapshot(for: readFailureTabID).currentURL == nil)
        precondition(!readFailureStore.cacheMetricsForTesting().isPersistenceAvailable)

        let unavailableStore = NavigationHistoryStore(
            fileSystem: FaultInjectingNavigationHistoryFileSystem(failure: .unavailableLocation)
        )
        let unavailableTabID = UUID()
        _ = unavailableStore.recordNavigation(to: "https://in-memory.example", for: unavailableTabID)
        unavailableStore.flushPendingWritesForTesting()
        precondition(unavailableStore.currentSnapshot(for: unavailableTabID).currentURL == "https://in-memory.example")
        precondition(!unavailableStore.cacheMetricsForTesting().isPersistenceAvailable)

        let boundedStore = NavigationHistoryStore(
            storageURL: root.appendingPathComponent("bounded"),
            configuration: NavigationHistoryConfiguration(maximumPendingWriteCount: 2)
        )
        for _ in 0..<3 {
            _ = boundedStore.recordNavigation(to: "https://bounded.example", for: UUID())
        }
        let boundedMetrics = boundedStore.cacheMetricsForTesting()
        precondition(boundedMetrics.pendingWriteCount == 2)
        precondition(boundedMetrics.droppedWriteCount == 1)
        boundedStore.flushPendingWritesForTesting()

        print("NavigationHistoryTests passed")
    }
}
