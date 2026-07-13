import Foundation

@main
struct NavigationHistoryTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reynard-navigation-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let tabID = UUID()
        let store = NavigationHistoryStore(
            storageURL: root,
            maximumEntryCount: 3,
            maximumCachedTabCount: 4
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
            maximumEntryCount: 3,
            maximumCachedTabCount: 4
        )
        let restored = restoredStore.currentSnapshot(for: tabID)
        precondition(restored.currentURL == snapshot.currentURL)
        precondition(restored.backHistory == snapshot.backHistory)
        precondition(restored.forwardHistory == snapshot.forwardHistory)

        let serializedHistory = try Data(contentsOf: root.appendingPathComponent(tabID.uuidString))
        precondition(serializedHistory.count < thumbnailData.count)
        precondition(!serializedHistory.base64EncodedString().contains(thumbnailData.base64EncodedString()))

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

        print("NavigationHistoryTests passed")
    }
}
