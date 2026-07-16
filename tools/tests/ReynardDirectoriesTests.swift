import Foundation

@main
struct ReynardDirectoriesTests {
    static func main() {
        testDirectoriesRemainInsideTheContainer()
        testObjectiveCDirectoryBridgeUsesTheSharedPolicy()
        print("ReynardDirectoriesTests passed")
    }

    private static func testDirectoriesRemainInsideTheContainer() {
        let directories = ReynardDirectories.make(
            applicationSupport: URL(fileURLWithPath: "/container/Library/Application Support"),
            caches: URL(fileURLWithPath: "/container/Library/Caches"),
            documents: URL(fileURLWithPath: "/container/Documents"),
            temporary: URL(fileURLWithPath: "/container/tmp")
        )

        precondition(directories.applicationSupport.path == "/container/Library/Application Support")
        precondition(directories.caches.path == "/container/Library/Caches")
        precondition(directories.documents.path == "/container/Documents")
        precondition(directories.downloads.path == "/container/Documents/Downloads")
        precondition(directories.temporary.path == "/container/tmp")
        precondition(directories.appData.path == "/container/Library/Application Support/AppData")
        precondition(directories.ddi.path == "/container/Library/Application Support/DDI")
        precondition(directories.geckoApplicationData.path == "/container/Library/Application Support/.mozilla/firefox")
        precondition(directories.geckoLocalData.path == "/container/Library/Caches/mozilla/firefox")
        precondition(directories.pairingFile.path == "/container/Documents/pairingFile.plist")
        precondition(directories.jitTemporary.path == "/container/tmp/ptrace_jit")
        precondition(directories.migrationRecovery.path == "/container/Library/ReynardMigration")
    }

    private static func testObjectiveCDirectoryBridgeUsesTheSharedPolicy() {
        precondition(ReynardDirectoriesBridge.ddiPath == ReynardDirectories.shared.ddi.path)
        precondition(ReynardDirectoriesBridge.pairingFilePath == ReynardDirectories.shared.pairingFile.path)
        precondition(ReynardDirectoriesBridge.jitTemporaryPath == ReynardDirectories.shared.jitTemporary.path)
    }
}
