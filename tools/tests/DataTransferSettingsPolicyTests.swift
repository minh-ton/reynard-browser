import Foundation

@main
struct DataTransferSettingsPolicyTests {
    static func main() {
        testOffersExportAndImport()
        testPendingOperationDisablesEveryAction()
        print("DataTransferSettingsPolicyTests passed")
    }

    private static func testOffersExportAndImport() {
        let policy = DataTransferSettingsPolicy()
        precondition(policy.actions == [.export, .importBackup])
        precondition(policy.canStartOperation(hasPendingOperation: false))
    }

    private static func testPendingOperationDisablesEveryAction() {
        let policy = DataTransferSettingsPolicy()
        precondition(!policy.canStartOperation(hasPendingOperation: true))
        for action in policy.actions {
            precondition(!policy.isEnabled(action, hasPendingOperation: true))
        }
    }
}
