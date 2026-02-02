//
//  GeckoEventDispatcher.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation

struct GeckoHandlerError: Error {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

protocol GeckoEventListenerInternal {
    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any?
}

extension GeckoEventListenerInternal {
    func handleMessage(type: String, message: [String: Any?]?, callback: EventCallback?) {
        Task { @MainActor in
            do {
                let result = try await self.handleMessage(type: type, message: message)
                callback?.sendSuccess(result)
            } catch let error as GeckoHandlerError {
                callback?.sendError(error.value)
            } catch {
                callback?.sendError("\(error)")
            }
        }
    }
}

/// Swift wrapper for the event dispatcher that bridges Swift and Gecko engine
public class GeckoEventDispatcherWrapper: NSObject, SwiftEventDispatcher {
    static var runtimeInstance = GeckoEventDispatcherWrapper()
    static var dispatchers: [String: GeckoEventDispatcherWrapper] = [:]

    struct QueuedMessage {
        let type: String
        let message: [String: Any?]?
        let callback: EventCallback?
    }

    var gecko: (any GeckoEventDispatcher)?
    var queue: [QueuedMessage]? = []
    var listeners: [String: [GeckoEventListenerInternal]] = [:]
    var name: String?

    override init() {}

    init(name: String) {
        self.name = name
    }

    public static func lookup(byName: String) -> GeckoEventDispatcherWrapper {
        if let dispatcher = dispatchers[byName] {
            return dispatcher
        }
        let newDispatcher = GeckoEventDispatcherWrapper(name: byName)
        dispatchers[byName] = newDispatcher
        return newDispatcher
    }

    func addListener(type: String, listener: GeckoEventListenerInternal) {
        listeners[type, default: []] += [listener]
    }

    public func dispatch(
        type: String, message: [String: Any?]? = nil, callback: EventCallback? = nil
    ) {
        if let eventListeners = listeners[type] {
            for listener in eventListeners {
                listener.handleMessage(type: type, message: message, callback: callback)
            }
        } else if queue != nil {
            queue!.append(QueuedMessage(type: type, message: message, callback: callback))
        } else {
            gecko?.dispatch(toGecko: type, message: message, callback: callback)
        }
    }

    public func query(type: String, message: [String: Any?]? = nil) async throws -> Any? {
        class AsyncCallback: NSObject, EventCallback {
            var continuation: CheckedContinuation<Any?, Error>?
            init(_ continuation: CheckedContinuation<Any?, Error>) {
                self.continuation = continuation
            }
            func sendSuccess(_ response: Any?) {
                continuation?.resume(returning: response)
                continuation = nil
            }
            func sendError(_ response: Any?) {
                continuation?.resume(throwing: GeckoHandlerError(response))
                continuation = nil
            }
            deinit {
                continuation?.resume(throwing: GeckoHandlerError("callback never invoked"))
                continuation = nil
            }
        }

        return try await withCheckedThrowingContinuation({
            dispatch(type: type, message: message, callback: AsyncCallback($0))
        })
    }

    // MARK: - SwiftEventDispatcher protocol implementation

    public func attach(_ dispatcher: (any GeckoEventDispatcher)?) {
        gecko = dispatcher
    }

    public func dispatch(toSwift type: String!, message: Any!, callback: EventCallback?) {
        let message = message as! [String: Any?]?
        if let eventListeners = listeners[type] {
            for listener in eventListeners {
                listener.handleMessage(type: type, message: message, callback: callback)
            }
        }
    }

    public func activate() {
        if let queue = self.queue {
            self.queue = nil
            for event in queue {
                gecko?.dispatch(toGecko: event.type, message: event.message, callback: event.callback)
            }
        }
    }

    public func hasListener(_ type: String!) -> Bool {
        listeners.keys.contains(type)
    }
}
