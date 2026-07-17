import Foundation

@main
enum BottomToolbarLayoutPolicyTests {
    static func main() {
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: -1) == 0)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 0) == 0)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 6) == 6)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 10) == 10)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 12) == 10)

        let duplicatedActions: [BottomToolbarAction] = [
            .back, .back, .forward, .settings, .settings,
        ]
        precondition(BottomToolbarAction.defaultActions.last == .settings)
        precondition(!BottomToolbarAction.optionalActions.contains(.settings))
        precondition(!BottomToolbarAction.settings.isRemovableFromToolbar)
        precondition(BottomToolbarAction.back.isRemovableFromToolbar)
        precondition(
            BottomToolbarAction.normalized(duplicatedActions) == [.back, .forward, .settings]
        )
        precondition(BottomToolbarAction.normalized([]) == [.settings])
        precondition(BottomToolbarAction.displayedActions(from: []) == [.settings])
        precondition(
            BottomToolbarAction.displayedActions(from: [.back, .settings, .forward]) ==
                [.back, .settings, .forward]
        )
        precondition(
            BottomToolbarAction.normalized(Array(repeating: .back, count: 12)) ==
                [.back, .settings]
        )
        let reversedActions = Array(BottomToolbarAction.allCases.reversed())
        let displayedActions = BottomToolbarAction.displayedActions(from: reversedActions)
        precondition(displayedActions.count == BottomToolbarLayoutPolicy.maximumConfiguredActions)
        precondition(displayedActions.filter { $0 == .settings }.count == 1)
        precondition(displayedActions[3] == .settings)
        let legacyActions = Array(BottomToolbarAction.optionalActions.prefix(10))
        let migratedActions = BottomToolbarAction.normalized(legacyActions)
        precondition(migratedActions.count == BottomToolbarLayoutPolicy.maximumConfiguredActions)
        precondition(migratedActions.last == .settings)
        precondition(BottomToolbarShortcutPolicy.longPressAction(
            for: .closeTab,
            closeTabOpensNewTab: true,
            newTabClosesTab: false
        ) == .newTab)
        precondition(BottomToolbarShortcutPolicy.longPressAction(
            for: .newTab,
            closeTabOpensNewTab: true,
            newTabClosesTab: true
        ) == .closeTab)
        precondition(BottomToolbarShortcutPolicy.longPressAction(
            for: .closeTab,
            closeTabOpensNewTab: false,
            newTabClosesTab: true
        ) == nil)

        let phoneWidths: [CGFloat] = [320, 375, 390, 428]
        for width in phoneWidths {
            for actionCount in 0...10 {
                let layout = BottomToolbarLayoutPolicy.layout(
                    containerWidth: width,
                    configuredCount: actionCount
                )
                precondition(layout.actionCount == actionCount)
                precondition(layout.rowCount <= 2)
                if actionCount > 0 {
                    precondition(layout.targetWidth >= BottomToolbarLayoutPolicy.minimumTargetSize)
                }
            }
        }

        let tenActionsOnPhone = BottomToolbarLayoutPolicy.layout(
            containerWidth: 428,
            configuredCount: 10
        )
        precondition(tenActionsOnPhone.rowActionCounts == [5, 5])
        precondition(tenActionsOnPhone.requiredHeight == 88)

        let tenActionsOnPad = BottomToolbarLayoutPolicy.layout(
            containerWidth: 768,
            configuredCount: 10
        )
        precondition(tenActionsOnPad.rowActionCounts == [10])
        precondition(tenActionsOnPad.targetWidth >= 44)

        let landscapeWithSafeArea = BottomToolbarLayoutPolicy.layout(
            containerWidth: 844,
            safeAreaLeft: 47,
            safeAreaRight: 47,
            configuredCount: 10
        )
        precondition(landscapeWithSafeArea.rowActionCounts == [10])
        precondition(landscapeWithSafeArea.targetWidth >= 44)
        print("BottomToolbarLayoutPolicyTests passed")
    }
}
