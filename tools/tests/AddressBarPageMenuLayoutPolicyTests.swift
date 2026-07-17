import Foundation
import CoreGraphics

@main
enum AddressBarPageMenuLayoutPolicyTests {
    static func main() {
        let portraitBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let portraitInsets = AddressBarPageMenuSafeAreaInsets(
            top: 47,
            left: 0,
            bottom: 34,
            right: 0
        )
        let topAnchor = CGRect(x: 16, y: 55, width: 44, height: 44)
        let frameBelow = AddressBarPageMenuLayoutPolicy.panelFrame(
            containerBounds: portraitBounds,
            safeAreaInsets: portraitInsets,
            anchorRect: topAnchor,
            contentHeight: 500
        )
        precondition(frameBelow.width == 300)
        precondition(AddressBarPageMenuLayoutPolicy.zoomHeight == 49)
        precondition(AddressBarPageMenuLayoutPolicy.minimumRowHeight == 50)
        precondition(frameBelow.minX >= 16)
        precondition(frameBelow.maxX <= 374)
        precondition(frameBelow.minY == topAnchor.maxY + AddressBarPageMenuLayoutPolicy.anchorSpacing)

        let bottomAnchor = CGRect(x: 16, y: 740, width: 44, height: 44)
        let frameAbove = AddressBarPageMenuLayoutPolicy.panelFrame(
            containerBounds: portraitBounds,
            safeAreaInsets: portraitInsets,
            anchorRect: bottomAnchor,
            contentHeight: 400
        )
        precondition(frameAbove.maxY == bottomAnchor.minY - AddressBarPageMenuLayoutPolicy.anchorSpacing)
        precondition(frameAbove.minY >= 63)

        let clampedFrame = AddressBarPageMenuLayoutPolicy.panelFrame(
            containerBounds: portraitBounds,
            safeAreaInsets: portraitInsets,
            anchorRect: topAnchor,
            contentHeight: 2_000
        )
        precondition(clampedFrame.height == 731)
        precondition(clampedFrame.minY == 63)
        precondition(clampedFrame.maxY == 794)

        let landscapeBounds = CGRect(x: 0, y: 0, width: 844, height: 390)
        let landscapeInsets = AddressBarPageMenuSafeAreaInsets(
            top: 0,
            left: 47,
            bottom: 21,
            right: 47
        )
        let landscapeFrame = AddressBarPageMenuLayoutPolicy.panelFrame(
            containerBounds: landscapeBounds,
            safeAreaInsets: landscapeInsets,
            anchorRect: CGRect(x: 55, y: 8, width: 44, height: 44),
            contentHeight: 220
        )
        precondition(landscapeFrame.width == AddressBarPageMenuLayoutPolicy.maximumWidth)
        precondition(landscapeFrame.minX >= 63)
        precondition(landscapeFrame.maxX <= 781)
        precondition(landscapeFrame.maxY <= 353)

        print("AddressBarPageMenuLayoutPolicyTests passed")
    }
}
