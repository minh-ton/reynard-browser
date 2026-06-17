//
//  EngineSelectionActionCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class EngineSelectionActionCoordinator: SelectionActionDelegate {
    // MARK: - UX

    private enum UX {
        static let modernMenuVerticalOffset: CGFloat = 40
    }

    // MARK: - State

    private var activeHosts: [ObjectIdentifier: SelectionActionMenuHostView] = [:]

    // MARK: - Lifecycle

    init() {}

    // MARK: - SelectionActionDelegate

    func onShowSelectionAction(session: GeckoSession, request: SelectionActionRequest) {
        guard request.editable == false,
              request.actions.contains(SelectionActionCommand.copy) ||
                request.actions.contains(SelectionActionCommand.selectAll),
              !request.selection.isEmpty,
              let targetView = session.engineView,
              let selectionRect = convertScreenRect(request.screenRect, into: targetView) else {
            activeHost(for: session)?.hideMenu()
            return
        }

        let host = host(for: session)
        let anchorRect = menuAnchorRect(from: selectionRect, in: targetView.bounds)
        host.present(
            on: targetView,
            session: session,
            actionId: request.actionId,
            anchorRect: anchorRect,
            actions: request.actions
        )
    }

    func onHideSelectionAction(session: GeckoSession) {
        activeHost(for: session)?.hideMenu()
    }

    // MARK: - Hosts

    private func activeHost(for session: GeckoSession) -> SelectionActionMenuHostView? {
        activeHosts[ObjectIdentifier(session)]
    }

    private func host(for session: GeckoSession) -> SelectionActionMenuHostView {
        let key = ObjectIdentifier(session)
        if let host = activeHosts[key] {
            return host
        }

        let host = SelectionActionMenuHostView()
        activeHosts[key] = host
        return host
    }

    // MARK: - Geometry

    private func convertScreenRect(_ screenRect: CGRect, into view: UIView) -> CGRect? {
        let window = (view as? UIWindow) ?? view.window
        guard let window else { return nil }

        let scale = window.screen.scale
        let normalizedScreenRect = CGRect(
            x: screenRect.origin.x / scale,
            y: screenRect.origin.y / scale,
            width: screenRect.size.width / scale,
            height: screenRect.size.height / scale
        )

        let windowRect = window.convert(normalizedScreenRect, from: window.screen.coordinateSpace)
        let localRect = view.convert(windowRect, from: window)
        let clippedRect = localRect.intersection(view.bounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else {
            return nil
        }

        return clippedRect
    }

    private func menuAnchorRect(from selectionRect: CGRect, in bounds: CGRect) -> CGRect {
        let verticalOffset: CGFloat
        if #available(iOS 26.0, *) {
            verticalOffset = UX.modernMenuVerticalOffset
        } else {
            verticalOffset = 0
        }

        let anchorY: CGFloat
        if selectionRect.minY >= verticalOffset {
            anchorY = selectionRect.minY - verticalOffset
        } else {
            anchorY = min(bounds.maxY - 1, selectionRect.maxY + verticalOffset)
        }

        return CGRect(
            x: min(max(bounds.minX, selectionRect.midX - 0.5), bounds.maxX - 1),
            y: anchorY,
            width: 1,
            height: 1
        )
    }
}
