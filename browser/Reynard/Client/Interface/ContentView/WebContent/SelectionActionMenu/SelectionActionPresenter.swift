//
//  SelectionActionPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class SelectionActionPresenter: SelectionActionPresenting {
    private enum UX {
        static let modernMenuVerticalOffset: CGFloat = 40
    }
    
    private var menuHosts: [ObjectIdentifier: SelectionActionMenuHostView] = [:]
    
    // MARK: - Lifecycle
    
    init() {}
    
    func show(_ request: SelectionActionRequest, for session: GeckoSession) {
        guard request.editable == false,
              request.actions.contains(SelectionActionCommand.copy) ||
                request.actions.contains(SelectionActionCommand.selectAll),
              !request.selection.isEmpty,
              let targetView = session.engineView,
              let selectionRect = localRect(for: request.screenRect, in: targetView) else {
            existingMenuHost(for: session)?.hideMenu()
            return
        }
        
        let host = menuHost(for: session)
        let anchorRect = anchorRect(for: selectionRect, in: targetView.bounds)
        host.present(
            on: targetView,
            session: session,
            actionId: request.actionId,
            anchorRect: anchorRect,
            actions: request.actions
        )
    }
    
    func hide(for session: GeckoSession) {
        existingMenuHost(for: session)?.hideMenu()
    }
    
    // MARK: - Hosts
    
    private func existingMenuHost(for session: GeckoSession) -> SelectionActionMenuHostView? {
        menuHosts[ObjectIdentifier(session)]
    }
    
    private func menuHost(for session: GeckoSession) -> SelectionActionMenuHostView {
        let key = ObjectIdentifier(session)
        if let host = menuHosts[key] {
            return host
        }
        
        let host = SelectionActionMenuHostView()
        menuHosts[key] = host
        return host
    }
    
    // MARK: - Geometry
    
    private func localRect(for screenRect: CGRect, in view: UIView) -> CGRect? {
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
    
    private func anchorRect(for selectionRect: CGRect, in bounds: CGRect) -> CGRect {
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
