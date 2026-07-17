import Foundation

@main
enum PageZoomViewportPolicyTests {
    static func main() {
        precondition(
            PageZoomViewportPolicy.maximumLevel(viewportWidth: 428) == 300,
            "Unrestricted pages must retain every zoom level."
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 175,
                viewportWidth: 428
            ) == 175
        )
        precondition(
            PageZoomViewportPolicy.maximumLevel(
                viewportWidth: 428,
                minimumLayoutWidth: 256
            ) == 150,
            "Restricted pages must stop before the unsafe 175% level."
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 175,
                viewportWidth: 428,
                minimumLayoutWidth: 256
            ) == 150
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 125,
                viewportWidth: 428,
                minimumLayoutWidth: 256
            ) == 125
        )
        precondition(
            PageZoomViewportPolicy.maximumLevel(
                viewportWidth: 768,
                minimumLayoutWidth: 256
            ) == 300,
            "A viewport that remains 256 points wide at 300% may use every level."
        )
        precondition(
            PageZoomViewportPolicy.maximumLevel(
                viewportWidth: 375,
                minimumLayoutWidth: 256
            ) == 125
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 300,
                viewportWidth: nil,
                minimumLayoutWidth: 256
            ) == PageZoomViewportPolicy.defaultLevel,
            "Restricted sessions without a measured viewport must open safely."
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 300,
                viewportWidth: nil
            ) == 300,
            "Unrestricted sessions must not wait for a viewport measurement."
        )
        precondition(
            PageZoomViewportPolicy.effectiveLevel(
                requestedLevel: 173,
                viewportWidth: 428
            ) == PageZoomViewportPolicy.defaultLevel,
            "Unsupported requested levels must fall back to the default."
        )

        print("PageZoomViewportPolicyTests passed")
    }
}
