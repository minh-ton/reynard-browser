import Foundation

@main
struct ReynardStartupModeTests {
    static func main() {
        testNoPendingOperationUsesNormalStartup()
        testPendingExportUsesDataTransferStartup()
        testPendingImportPreservesBookmarkData()
        testMalformedPendingStateIsCleared()
        testRecoveryFailureUsesSafeStartup()
        print("ReynardStartupModeTests passed")
    }

    private static func testNoPendingOperationUsesNormalStartup() {
        withStore { store, _ in
            precondition(ReynardStartupMode.resolve(store: store) == .normal)
        }
    }

    private static func testPendingExportUsesDataTransferStartup() {
        withStore { store, _ in
            precondition(store.schedule(.export))
            precondition(
                ReynardStartupMode.resolve(store: store) == .dataTransfer(operation: .export)
            )
        }
    }

    private static func testPendingImportPreservesBookmarkData() {
        withStore { store, _ in
            let bookmarkData = Data([0x01, 0x02, 0x03])
            precondition(store.schedule(.importBackup(bookmarkData: bookmarkData)))
            precondition(
                ReynardStartupMode.resolve(store: store) == .dataTransfer(
                    operation: .importBackup(bookmarkData: bookmarkData)
                )
            )
            precondition(!store.schedule(.export))
        }
    }

    private static func testMalformedPendingStateIsCleared() {
        withStore { store, defaults in
            defaults.set(Data("invalid".utf8), forKey: store.storageKey)
            precondition(ReynardStartupMode.resolve(store: store) == .normal)
            precondition(defaults.object(forKey: store.storageKey) == nil)
        }
    }

    private static func testRecoveryFailureUsesSafeStartup() {
        withStore { store, _ in
            precondition(
                ReynardStartupMode.resolve(
                    store: store,
                    recoveryFailed: true
                ) == .recoveryFailure
            )
            precondition(ReynardStartupMode.recoveryFailure.usesUIKitOnlyStartup)
        }
    }

    private static func withStore(
        _ body: (ReynardDataTransferLaunchStore, UserDefaults) -> Void
    ) {
        let suiteName = "ReynardStartupModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(ReynardDataTransferLaunchStore(defaults: defaults), defaults)
    }
}
