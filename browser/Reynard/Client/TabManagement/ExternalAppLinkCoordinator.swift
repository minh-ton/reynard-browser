//
//  ExternalAppLinkCoordinator.swift
//  Reynard
//

import Foundation

@MainActor
final class ExternalAppLinkCoordinator {
    typealias OpenHandler = @MainActor (ExternalAppLinkRoute) async -> Bool

    private struct RequestKey: Hashable {
        let sessionID: ObjectIdentifier
        let destination: String
        let kind: ExternalAppLinkKind
    }

    private struct CompletedRequest {
        let result: Bool
        let completedAt: TimeInterval
    }

    private let duplicateWindow: TimeInterval
    private let uptime: () -> TimeInterval
    private var inFlight: [RequestKey: Task<Bool, Never>] = [:]
    private var completed: [RequestKey: CompletedRequest] = [:]

    init(
        duplicateWindow: TimeInterval = 1,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.duplicateWindow = duplicateWindow
        self.uptime = uptime
    }

    func open(
        _ route: ExternalAppLinkRoute,
        for session: AnyObject,
        using handler: @escaping OpenHandler
    ) async -> Bool {
        let key = RequestKey(
            sessionID: ObjectIdentifier(session),
            destination: route.url.absoluteString,
            kind: route.kind
        )

        discardExpiredResults()
        if let request = completed[key] {
            return request.result
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task { @MainActor in
            await handler(route)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        completed[key] = CompletedRequest(result: result, completedAt: uptime())
        return result
    }

    func cancelRequests(for session: AnyObject) {
        let sessionID = ObjectIdentifier(session)
        let keys = inFlight.keys.filter { $0.sessionID == sessionID }
        for key in keys {
            inFlight.removeValue(forKey: key)?.cancel()
        }
        completed = completed.filter { $0.key.sessionID != sessionID }
    }

    private func discardExpiredResults() {
        let now = uptime()
        completed = completed.filter {
            now - $0.value.completedAt < duplicateWindow
        }
    }
}
