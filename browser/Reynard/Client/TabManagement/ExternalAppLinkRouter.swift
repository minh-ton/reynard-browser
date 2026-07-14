//
//  ExternalAppLinkRouter.swift
//  Reynard
//

import Foundation

enum ExternalAppLinkDisposition: Equatable {
    case opened
    case notOpened
    case automaticRoutingDisabled
    case rejected(ExternalAppLinkRejection)
}

@MainActor
final class ExternalAppLinkRouter {
    typealias OpenHandler = @MainActor (ExternalAppLinkAttempt) async -> Bool

    private let isAutomaticRoutingEnabled: () -> Bool
    private let open: OpenHandler

    init(
        isAutomaticRoutingEnabled: @escaping () -> Bool,
        open: @escaping OpenHandler
    ) {
        self.isAutomaticRoutingEnabled = isAutomaticRoutingEnabled
        self.open = open
    }

    func handle(_ request: ExternalAppLinkRequest) async -> ExternalAppLinkDisposition {
        if request.source != .externalProtocol && !isAutomaticRoutingEnabled() {
            return .automaticRoutingDisabled
        }

        switch ExternalAppLinkPolicy.decision(for: request) {
        case let .reject(rejection):
            return .rejected(rejection)
        case let .route(route):
            if await open(route.primary) {
                return .opened
            }
            if let fallback = route.fallback, await open(fallback) {
                return .opened
            }
            return .notOpened
        }
    }
}
