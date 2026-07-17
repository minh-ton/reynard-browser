import Foundation

@main
enum PageZoomCompatibilityPolicyTests {
    static func main() {
        precondition(
            PageZoomCompatibilityPolicy.minimumLayoutWidth(
                for: "https://github.com/"
            ) == 256
        )
        precondition(
            PageZoomCompatibilityPolicy.minimumLayoutWidth(
                for: "https://gist.github.com/example"
            ) == 256
        )
        precondition(
            PageZoomCompatibilityPolicy.minimumLayoutWidth(
                for: "https://example.com/"
            ) == nil
        )
        precondition(
            PageZoomCompatibilityPolicy.minimumLayoutWidth(
                for: "https://notgithub.com/"
            ) == nil
        )
        precondition(
            PageZoomCompatibilityPolicy.minimumLayoutWidth(
                for: "not a URL"
            ) == nil
        )

        print("PageZoomCompatibilityPolicyTests passed")
    }
}
