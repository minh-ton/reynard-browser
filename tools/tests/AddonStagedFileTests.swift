import Foundation

struct GeckoHandlerError: Error {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

@main
struct AddonStagedFileTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let validURL = temporaryDirectory.appendingPathComponent(
            "reynard-webextension-tests-\(UUID().uuidString).png"
        )
        let invalidNameURL = temporaryDirectory.appendingPathComponent(
            "untrusted-addon-output-\(UUID().uuidString).png"
        )
        let outsideURL = URL(fileURLWithPath: "/private/var/tmp/reynard-webextension-outside.png")

        defer {
            try? fileManager.removeItem(at: validURL)
            try? fileManager.removeItem(at: invalidNameURL)
            try? fileManager.removeItem(at: outsideURL)
        }

        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        try onePixelPNG.write(to: validURL, options: .atomic)
        try onePixelPNG.write(to: invalidNameURL, options: .atomic)
        try onePixelPNG.write(to: outsideURL, options: .atomic)

        let validatedURL = try AddonStagedFile.validatedURL(path: validURL.path)
        precondition(validatedURL == validURL)
        let loadedPNG = try await AddonStagedFile.loadValidatedPNG(at: validURL)
        precondition(loadedPNG == onePixelPNG)

        expectFailure { _ = try AddonStagedFile.validatedURL(path: invalidNameURL.path) }
        expectFailure { _ = try AddonStagedFile.validatedURL(path: outsideURL.path) }
        expectFailure { try AddonStagedFile.validatePNG(Data("not a png".utf8)) }

        print("AddonStagedFileTests passed")
    }

    private static func expectFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected operation to fail")
        } catch {}
    }
}
