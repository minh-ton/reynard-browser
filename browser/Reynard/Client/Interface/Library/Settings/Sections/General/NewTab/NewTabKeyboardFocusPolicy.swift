//
//  NewTabKeyboardFocusPolicy.swift
//  Reynard
//

import Foundation

enum NewTabCreationIntent {
    case userInitiated
    case lastTabReplacement

    var automaticallyFocusesAddressBar: Bool {
        self == .userInitiated
    }
}

enum NewTabKeyboardFocusPolicy {
    struct Context {
        let requestedTabID: UUID
        let selectedTabID: UUID?
        let isEnabled: Bool
        let displayOptionSupportsFocus: Bool
        let isViewVisible: Bool
        let isTabOverviewPresented: Bool
        let isTransitionRunning: Bool
        let isEventDispatchComplete: Bool
        let isContentReady: Bool
    }

    static func shouldFulfill(_ context: Context) -> Bool {
        context.isEnabled &&
            context.displayOptionSupportsFocus &&
            context.selectedTabID == context.requestedTabID &&
            context.isViewVisible &&
            !context.isTabOverviewPresented &&
            !context.isTransitionRunning &&
            context.isEventDispatchComplete &&
            context.isContentReady
    }

    static func shouldCancel(_ context: Context) -> Bool {
        !context.isEnabled ||
            !context.displayOptionSupportsFocus ||
            context.selectedTabID != context.requestedTabID
    }
}
