import Foundation

@main
enum DownloadImageDecodePolicyTests {
    static func main() {
        let normal = DownloadImageDecodePolicy.boundedDimensions(
            width: 1_170,
            height: 2_532
        )
        precondition(normal?.width == 1_170)
        precondition(normal?.height == 2_532)

        let tall = DownloadImageDecodePolicy.boundedDimensions(
            width: 4_000,
            height: 40_000
        )
        precondition(tall != nil)
        precondition(tall!.width * tall!.height <= DownloadImageDecodePolicy.maximumPixelCount)
        precondition(tall!.height <= DownloadImageDecodePolicy.maximumDimension)
        precondition(DownloadImageDecodePolicy.boundedDimensions(width: 0, height: 10) == nil)
        print("DownloadImageDecodePolicyTests passed")
    }
}
