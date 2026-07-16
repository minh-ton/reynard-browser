//
//  ReynardStartupMode.swift
//  Reynard
//

import Foundation

enum ReynardStartupMode: Equatable {
    case normal
    case dataTransfer(operation: ReynardDataTransferOperation)
    case recoveryFailure

    static var current: ReynardStartupMode = .normal

    static func resolve(
        store: ReynardDataTransferLaunchStore = .shared,
        recoveryFailed: Bool = false
    ) -> ReynardStartupMode {
        guard !recoveryFailed else {
            return .recoveryFailure
        }
        guard let operation = store.pendingOperation() else {
            return .normal
        }
        return .dataTransfer(operation: operation)
    }

    var usesUIKitOnlyStartup: Bool {
        switch self {
        case .dataTransfer, .recoveryFailure:
            return true
        case .normal:
            return false
        }
    }
}
