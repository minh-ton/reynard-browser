//
//  SelectionActionDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 26/5/26.
//

import Foundation

// MARK: - Selection Action Delegate

public protocol SelectionActionDelegate: AnyObject {
    @MainActor
    func onShowSelectionAction(session: GeckoSession, request: SelectionActionRequest)
    @MainActor
    func onHideSelectionAction(session: GeckoSession)
}

public extension SelectionActionDelegate {
    @MainActor
    func onShowSelectionAction(session: GeckoSession, request: SelectionActionRequest) {}
    
    @MainActor
    func onHideSelectionAction(session: GeckoSession) {}
}

// MARK: - Selection Action Events

private enum SelectionActionEvent: String, CaseIterable {
    case show = "GeckoView:ShowSelectionAction"
    case hide = "GeckoView:HideSelectionAction"
}

// MARK: - Selection Action Handler

func newSelectionActionHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewSelectionAction",
        events: SelectionActionEvent.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = SelectionActionEvent(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        let delegate = delegate as? SelectionActionDelegate
        switch event {
        case .show:
            guard let request = parseSelectionActionRequest(message) else {
                delegate?.onHideSelectionAction(session: session)
                return nil
            }
            delegate?.onShowSelectionAction(session: session, request: request)
            
        case .hide:
            delegate?.onHideSelectionAction(session: session)
        }
        
        return nil
    }
}
