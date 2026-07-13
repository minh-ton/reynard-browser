import Foundation

@main
enum WebsiteModeHostTests {
    static func main() {
        expect(WebsiteModeHost.normalized("Example.COM") == "example.com")
        expect(WebsiteModeHost.normalized("m.example.com") == "example.com")
        expect(WebsiteModeHost.normalized("mobile.example.com") == "example.com")
        expect(WebsiteModeHost.areRelated("m.example.com", "example.com"))
        expect(WebsiteModeHost.areRelated("mobile.example.com", "example.com"))
        expect(!WebsiteModeHost.areRelated("news.example.com", "example.com"))
        expect(!WebsiteModeHost.areRelated("one.example.com", "two.example.com"))
        expect(WebsiteModeHost.relatedAliases(for: "m.Example.com") == [
            "example.com",
            "m.example.com",
            "mobile.example.com",
        ])
        print("WebsiteModeHostTests passed")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Expectation failed", file: file, line: line)
        }
    }
}
