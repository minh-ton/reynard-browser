//
//  GeckoSessionHandler.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

final class GeckoSessionHandler: GeckoSessionHandlerCommon {
    typealias MessageHandler = @MainActor (GeckoSession, Any?, String, [String: Any?]?) async throws -> Any?
    
    let moduleName: String
    let events: [String]
    let handle: MessageHandler
    
    private(set) weak var session: GeckoSession?
    private var delegateReference: Any?
    
    func delegate<Delegate>(as type: Delegate.Type = Delegate.self) -> Delegate? {
        delegateReference as? Delegate
    }
    
    var enabled: Bool {
        delegateReference != nil
    }
    
    func setDelegate<Delegate>(_ delegate: Delegate?) {
        delegateReference = delegate
        
        guard let session, session.isOpen() else {
            return
        }
        
        session.dispatcher.dispatch(
            type: "GeckoView:UpdateModuleState",
            message: [
                "module": moduleName,
                "enabled": delegate != nil,
            ])
    }
    
    init(
        moduleName: String,
        events: [String],
        session: GeckoSession,
        handle: @escaping MessageHandler
    ) {
        self.moduleName = moduleName
        self.events = events
        self.session = session
        self.handle = handle
    }
    
    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        guard events.contains(type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        guard let session else {
            throw GeckoHandlerError("session has been destroyed")
        }
        return try await handle(session, delegateReference, type, message)
    }
}
