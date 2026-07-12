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
            maximumEntryCount: 3
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

        precondition(store.goBack(for: tabID) == "https://d.example")
        precondition(store.goBack(for: tabID) == "https://c.example")
        precondition(store.goForward(for: tabID) == "https://d.example")
        snapshot = store.currentSnapshot(for: tabID)
        precondition(snapshot.currentURL == "https://d.example")
        precondition(snapshot.canGoBack)
        precondition(snapshot.canGoForward)

        store.flushPendingWritesForTesting()
        let restoredStore = NavigationHistoryStore(
            storageURL: root,
            maximumEntryCount: 3
        )
        let restored = restoredStore.currentSnapshot(for: tabID)
        precondition(restored.currentURL == snapshot.currentURL)
        precondition(restored.backHistory == snapshot.backHistory)
        precondition(restored.forwardHistory == snapshot.forwardHistory)

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

        print("NavigationHistoryTests passed")
    }
}
