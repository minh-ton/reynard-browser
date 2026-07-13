import Foundation

@main
enum BottomToolbarLayoutPolicyTests {
    static func main() {
        expect(width: 320, slots: 6)
        expect(width: 375, slots: 7)
        expect(width: 390, slots: 7)
        expect(width: 414, slots: 8)
        expect(width: 812, slots: 10)
        precondition(BottomToolbarLayoutPolicy.directActionCount(
            configuredCount: 10,
            availableSlots: 6
        ) == 5)
        precondition(BottomToolbarLayoutPolicy.directActionCount(
            configuredCount: 6,
            availableSlots: 6
        ) == 6)
        print("BottomToolbarLayoutPolicyTests passed")
    }

    private static func expect(width: CGFloat, slots: Int) {
        precondition(BottomToolbarLayoutPolicy.availableSlotCount(width: width) == slots)
    }
}
