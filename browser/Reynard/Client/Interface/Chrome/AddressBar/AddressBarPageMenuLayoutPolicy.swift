import Foundation
import CoreGraphics

struct AddressBarPageMenuSafeAreaInsets: Equatable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat
}

enum AddressBarPageMenuLayoutPolicy {
    static let maximumWidth: CGFloat = 300
    static let relativeWidth: CGFloat = 0.9
    static let screenInset: CGFloat = 16
    static let anchorSpacing: CGFloat = 8
    static let zoomHeight: CGFloat = 49
    static let minimumRowHeight: CGFloat = 50
    static let sectionSpacing: CGFloat = 8

    static func panelFrame(
        containerBounds: CGRect,
        safeAreaInsets: AddressBarPageMenuSafeAreaInsets,
        anchorRect: CGRect,
        contentHeight: CGFloat
    ) -> CGRect {
        let safeFrame = CGRect(
            x: containerBounds.minX + safeAreaInsets.left + screenInset,
            y: containerBounds.minY + safeAreaInsets.top + screenInset,
            width: max(
                0,
                containerBounds.width - safeAreaInsets.left - safeAreaInsets.right
                    - 2 * screenInset
            ),
            height: max(
                0,
                containerBounds.height - safeAreaInsets.top - safeAreaInsets.bottom
                    - 2 * screenInset
            )
        )
        let panelWidth = min(maximumWidth, safeFrame.width * relativeWidth)
        let panelHeight = min(max(0, contentHeight), safeFrame.height)
        let panelX = min(
            max(safeFrame.minX, anchorRect.minX),
            safeFrame.maxX - panelWidth
        )
        let spaceBelow = safeFrame.maxY - anchorRect.maxY - anchorSpacing
        let panelY: CGFloat
        if spaceBelow >= panelHeight {
            panelY = anchorRect.maxY + anchorSpacing
        } else {
            panelY = max(
                safeFrame.minY,
                anchorRect.minY - anchorSpacing - panelHeight
            )
        }
        return CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
    }
}
