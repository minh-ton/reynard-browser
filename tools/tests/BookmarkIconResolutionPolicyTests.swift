import Foundation

@main
enum BookmarkIconResolutionPolicyTests {
    static func main() {
        precondition(BookmarkIconResolutionPolicy.source(hasCustomIcon: true, hasFavicon: true) == .custom)
        precondition(BookmarkIconResolutionPolicy.source(hasCustomIcon: true, hasFavicon: false) == .custom)
        precondition(BookmarkIconResolutionPolicy.source(hasCustomIcon: false, hasFavicon: true) == .favicon)
        precondition(BookmarkIconResolutionPolicy.source(hasCustomIcon: false, hasFavicon: false) == .fallback)
        print("BookmarkIconResolutionPolicyTests passed")
    }
}
