import Foundation

@main
enum BookmarkIconImagePolicyTests {
    static func main() {
        precondition(BookmarkIconImagePolicy.acceptsInputByteCount(1))
        precondition(BookmarkIconImagePolicy.acceptsInputByteCount(BookmarkIconImagePolicy.maximumInputBytes))
        precondition(!BookmarkIconImagePolicy.acceptsInputByteCount(0))
        precondition(!BookmarkIconImagePolicy.acceptsInputByteCount(BookmarkIconImagePolicy.maximumInputBytes + 1))

        precondition(BookmarkIconImagePolicy.acceptsPixelDimensions(width: 4_000, height: 3_000))
        precondition(!BookmarkIconImagePolicy.acceptsPixelDimensions(width: 0, height: 100))
        precondition(!BookmarkIconImagePolicy.acceptsPixelDimensions(width: 20_000, height: 20_000))

        let crop = BookmarkIconImagePolicy.clampedSquareCrop(
            x: -0.2,
            y: 0.25,
            side: 1.4
        )
        precondition(crop != nil)
        precondition(crop?.x == 0)
        precondition(crop?.y == 0)
        precondition(crop?.side == 1)

        precondition(BookmarkIconImagePolicy.clampedSquareCrop(x: 0.2, y: 0.3, side: 0) == nil)
        precondition(BookmarkIconImagePolicy.outputPixelSize == 256)
        print("BookmarkIconImagePolicyTests passed")
    }
}
