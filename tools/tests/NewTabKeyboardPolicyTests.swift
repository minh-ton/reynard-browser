@main
struct NewTabKeyboardPolicyTests {
    static func main() {
        precondition(NewTabDisplayOption.homepage.supportsAutomaticKeyboardFocus)
        precondition(NewTabDisplayOption.blankPage.supportsAutomaticKeyboardFocus)
        precondition(!NewTabDisplayOption.customURL.supportsAutomaticKeyboardFocus)
        print("NewTabKeyboardPolicyTests passed")
    }
}
