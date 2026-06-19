//
//  PromptDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 8/4/26.
//

import Foundation

// MARK: - Prompt Delegate

public protocol PromptDelegate: AnyObject {
    @MainActor
    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse?
    @MainActor
    func onPromptUpdate(session: GeckoSession, request: PromptRequest)
    @MainActor
    func onPromptDismiss(session: GeckoSession, promptId: String)
}

public extension PromptDelegate {
    @MainActor
    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? { nil }
    
    @MainActor
    func onPromptUpdate(session: GeckoSession, request: PromptRequest) {}
    
    @MainActor
    func onPromptDismiss(session: GeckoSession, promptId: String) {}
}

// MARK: - Prompt Events

private enum PromptEvents: String, CaseIterable {
    case prompt = "GeckoView:Prompt"
    case promptUpdate = "GeckoView:Prompt:Update"
    case promptDismiss = "GeckoView:Prompt:Dismiss"
}

// MARK: - Prompt Handler

func newPromptHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewPrompter",
        events: PromptEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = PromptEvents(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        let delegate = delegate as? PromptDelegate
        switch event {
        case .prompt:
            guard let promptData = message?["prompt"] as? [String: Any],
                  let request = parsePromptRequest(promptData) else {
                return nil
            }
            return await delegate?.onPrompt(session: session, request: request)?.geckoMessage
            
        case .promptUpdate:
            guard let promptData = message?["prompt"] as? [String: Any],
                  let request = parsePromptRequest(promptData) else {
                return nil
            }
            delegate?.onPromptUpdate(session: session, request: request)
            return nil
            
        case .promptDismiss:
            let prompt = message?["prompt"] as? [String: Any]
            let promptID = prompt?["id"] as? String ?? message?["id"] as? String ?? ""
            delegate?.onPromptDismiss(session: session, promptId: promptID)
            return nil
        }
    }
}
