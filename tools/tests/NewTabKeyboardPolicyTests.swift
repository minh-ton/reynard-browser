import Foundation

@main
struct NewTabKeyboardPolicyTests {
    static func main() {
        precondition(NewTabDisplayOption.homepage.supportsAutomaticKeyboardFocus)
        precondition(NewTabDisplayOption.blankPage.supportsAutomaticKeyboardFocus)
        precondition(!NewTabDisplayOption.customURL.supportsAutomaticKeyboardFocus)
        precondition(NewTabCreationIntent.userInitiated.automaticallyFocusesAddressBar)
        precondition(!NewTabCreationIntent.lastTabReplacement.automaticallyFocusesAddressBar)

        let requestedTabID = UUID()
        let ready = NewTabKeyboardFocusPolicy.Context(
            requestedTabID: requestedTabID,
            selectedTabID: requestedTabID,
            isEnabled: true,
            displayOptionSupportsFocus: true,
            isViewVisible: true,
            isTabOverviewPresented: false,
            isTransitionRunning: false,
            isEventDispatchComplete: true,
            isContentReady: true
        )
        precondition(NewTabKeyboardFocusPolicy.shouldFulfill(ready))
        precondition(!NewTabKeyboardFocusPolicy.shouldCancel(ready))

        let transitionRunning = NewTabKeyboardFocusPolicy.Context(
            requestedTabID: requestedTabID,
            selectedTabID: requestedTabID,
            isEnabled: true,
            displayOptionSupportsFocus: true,
            isViewVisible: true,
            isTabOverviewPresented: false,
            isTransitionRunning: true,
            isEventDispatchComplete: true,
            isContentReady: true
        )
        precondition(!NewTabKeyboardFocusPolicy.shouldFulfill(transitionRunning))
        precondition(!NewTabKeyboardFocusPolicy.shouldCancel(transitionRunning))

        let eventDispatchPending = NewTabKeyboardFocusPolicy.Context(
            requestedTabID: requestedTabID,
            selectedTabID: requestedTabID,
            isEnabled: true,
            displayOptionSupportsFocus: true,
            isViewVisible: true,
            isTabOverviewPresented: false,
            isTransitionRunning: false,
            isEventDispatchComplete: false,
            isContentReady: true
        )
        precondition(!NewTabKeyboardFocusPolicy.shouldFulfill(eventDispatchPending))
        precondition(!NewTabKeyboardFocusPolicy.shouldCancel(eventDispatchPending))

        let contentFocusPending = NewTabKeyboardFocusPolicy.Context(
            requestedTabID: requestedTabID,
            selectedTabID: requestedTabID,
            isEnabled: true,
            displayOptionSupportsFocus: true,
            isViewVisible: true,
            isTabOverviewPresented: false,
            isTransitionRunning: false,
            isEventDispatchComplete: true,
            isContentReady: false
        )
        precondition(!NewTabKeyboardFocusPolicy.shouldFulfill(contentFocusPending))
        precondition(!NewTabKeyboardFocusPolicy.shouldCancel(contentFocusPending))

        for cancelledContext in [
            NewTabKeyboardFocusPolicy.Context(
                requestedTabID: requestedTabID,
                selectedTabID: UUID(),
                isEnabled: true,
                displayOptionSupportsFocus: true,
                isViewVisible: true,
                isTabOverviewPresented: false,
                isTransitionRunning: false,
                isEventDispatchComplete: true,
                isContentReady: true
            ),
            NewTabKeyboardFocusPolicy.Context(
                requestedTabID: requestedTabID,
                selectedTabID: requestedTabID,
                isEnabled: false,
                displayOptionSupportsFocus: true,
                isViewVisible: true,
                isTabOverviewPresented: false,
                isTransitionRunning: false,
                isEventDispatchComplete: true,
                isContentReady: true
            ),
            NewTabKeyboardFocusPolicy.Context(
                requestedTabID: requestedTabID,
                selectedTabID: requestedTabID,
                isEnabled: true,
                displayOptionSupportsFocus: false,
                isViewVisible: true,
                isTabOverviewPresented: false,
                isTransitionRunning: false,
                isEventDispatchComplete: true,
                isContentReady: true
            ),
        ] {
            precondition(NewTabKeyboardFocusPolicy.shouldCancel(cancelledContext))
            precondition(!NewTabKeyboardFocusPolicy.shouldFulfill(cancelledContext))
        }
        print("NewTabKeyboardPolicyTests passed")
    }
}
