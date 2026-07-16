import Foundation

@main
struct ReynardBackupContentPolicyTests {
    static func main() {
        let policy = ReynardBackupContentPolicy()

        precondition(policy.includes(relativePath: "ApplicationSupport/.mozilla/profiles.ini"))
        precondition(policy.includes(relativePath: "ApplicationSupport/AppData/History/items.json"))
        precondition(policy.includes(relativePath: "Downloads/example.pdf"))

        precondition(!policy.includes(relativePath: "Caches/mozilla/cache2/entry"))
        precondition(!policy.includes(relativePath: "ApplicationSupport/DDI/DeveloperDiskImage.dmg"))
        precondition(!policy.includes(relativePath: "ApplicationSupport/.mozilla/profile/cache2/entry"))
        precondition(!policy.includes(relativePath: "ApplicationSupport/.mozilla/profile/startupCache/scriptCache.bin"))
        precondition(!policy.includes(relativePath: "tmp/debug.log"))
        precondition(!policy.includes(relativePath: ".com.apple.mobile_container_manager.metadata.plist"))
        precondition(!policy.includes(relativePath: "ApplicationSupport/AppData/../DDI/Image.dmg"))
        precondition(!policy.includes(relativePath: "/var/mobile/Library/data"))
        precondition(!policy.includes(relativePath: ""))

        print("ReynardBackupContentPolicyTests passed")
    }
}
