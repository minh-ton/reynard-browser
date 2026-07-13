import Foundation

@main
enum BottomToolbarLayoutPolicyTests {
    static func main() {
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: -1) == 0)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 0) == 0)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 6) == 6)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 10) == 10)
        precondition(BottomToolbarLayoutPolicy.visibleActionCount(configuredCount: 12) == 10)
        print("BottomToolbarLayoutPolicyTests passed")
    }
}
