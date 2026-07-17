//
//  DataTransferSettingsPolicy.swift
//  Reynard
//

import Foundation

struct DataTransferSettingsPolicy {
    enum Action: Equatable {
        case export
        case importBackup
    }

    let actions: [Action] = [.export, .importBackup]

    func canStartOperation(hasPendingOperation: Bool) -> Bool {
        !hasPendingOperation
    }

    func isEnabled(_ action: Action, hasPendingOperation: Bool) -> Bool {
        actions.contains(action) && canStartOperation(hasPendingOperation: hasPendingOperation)
    }
}
