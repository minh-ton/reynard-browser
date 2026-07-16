import Foundation

@main
enum BookmarkCustomIconStoreTests {
    static func main() throws {
        let existingColor = BookmarkIconColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let existingSymbol = BookmarkCustomIcon.symbol(name: "heart.fill", color: existingColor)
        precondition(
            BookmarkCustomIconMutation.unchanged.resolved(over: existingSymbol) == existingSymbol
        )
        precondition(
            BookmarkCustomIconMutation.set(existingSymbol).resolved(over: nil) == existingSymbol
        )
        precondition(
            BookmarkCustomIconMutation.remove.resolved(over: existingSymbol) == nil
        )
        let normalizedColor = BookmarkIconColor.normalizedSRGB(
            red: 1.04,
            green: -0.02,
            blue: 0.5,
            alpha: 1
        )
        precondition(
            normalizedColor == BookmarkIconColor(red: 1, green: 0, blue: 0.5, alpha: 1)
        )
        precondition(
            BookmarkIconColor.normalizedSRGB(
                red: .nan,
                green: 0,
                blue: 0,
                alpha: 1
            ) == nil
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("reynard-bookmark-icon-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let directories = ReynardDirectories.make(
            applicationSupport: root.appendingPathComponent("Library", isDirectory: true),
            caches: root.appendingPathComponent("Caches", isDirectory: true),
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            temporary: root.appendingPathComponent("Temporary", isDirectory: true)
        )
        let store = BookmarkStore(fileManager: fileManager, directories: directories)
        let url = URL(string: "https://example.com/custom-icon")!
        let raster = BookmarkCustomIcon.raster(Data([0x89, 0x50, 0x4E, 0x47]))

        guard let bookmark = store.addBookmark(
            title: "Custom Icon",
            url: url,
            customIcon: .set(raster)
        ) else {
            preconditionFailure("Failed to add bookmark with a custom icon")
        }
        precondition(store.customIcon(for: bookmark.guid) == raster)

        let color = BookmarkIconColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let symbol = BookmarkCustomIcon.symbol(name: "star.fill", color: color)
        precondition(store.updateBookmark(
            guid: bookmark.guid,
            title: "Symbol Icon",
            url: url,
            customIcon: .set(symbol)
        ) != nil)
        precondition(store.customIcon(for: bookmark.guid) == symbol)

        precondition(store.updateBookmark(
            guid: bookmark.guid,
            title: "Website Icon",
            url: url,
            customIcon: .remove
        ) != nil)
        precondition(store.customIcon(for: bookmark.guid) == nil)

        precondition(store.updateBookmark(
            guid: bookmark.guid,
            title: "Preserved",
            url: url,
            customIcon: .set(raster)
        ) != nil)
        precondition(store.updateBookmark(
            guid: bookmark.guid,
            title: "Must Roll Back",
            url: url,
            customIcon: .set(.raster(Data()))
        ) == nil)
        precondition(store.bookmark(savedFor: url)?.title == "Preserved")
        precondition(store.customIcon(for: bookmark.guid) == raster)

        precondition(store.removeBookmark(guid: bookmark.guid))
        precondition(store.customIcon(for: bookmark.guid) == nil)
        print("BookmarkCustomIconStoreTests passed")
    }
}
