//
//  GeckoSessionHandler.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

final class GeckoSessionHandler<Delegate, Event>: GeckoSessionHandlerCommon
where Event: CaseIterable, Event: RawRepresentable, Event.RawValue == String {
    let moduleName: String
    let handle: @MainActor (GeckoSession, Delegate?, Event, [String: Any?]?) async throws -> Any?

    private(set) weak var session: GeckoSession?

    var delegate: Delegate? {
        didSet {
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
    }

    var events: [String] {
        Event.allCases.map(\.rawValue)
    }

    var enabled: Bool {
        delegate != nil
    }

    init(
        moduleName: String,
        session: GeckoSession,
        handle: @escaping @MainActor (GeckoSession, Delegate?, Event, [String: Any?]?) async throws
            -> Any?
    ) {
        self.moduleName = moduleName
        self.session = session
        self.handle = handle
    }

    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        guard let event = Event(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        guard let session else {
            throw GeckoHandlerError("session has been destroyed")
        }
        return try await handle(session, delegate, event, message)
    }
}
