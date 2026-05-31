//
//  SelectionActionDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 26/5/26.
//

import UIKit

private enum SelectionActionEvent: String, CaseIterable {
    case show = "GeckoView:ShowSelectionAction"
    case hide = "GeckoView:HideSelectionAction"
}

private enum SelectionActionID {
    static let copy = "org.mozilla.geckoview.COPY"
    static let selectAll = "org.mozilla.geckoview.SELECT_ALL"
}

@MainActor
private var activeSelectionMenuHosts: [ObjectIdentifier: SelectionActionMenuHostView] = [:]

@MainActor
private func activeSelectionMenuHost(for session: GeckoSession) -> SelectionActionMenuHostView? {
    activeSelectionMenuHosts[ObjectIdentifier(session)]
}

@MainActor
private func selectionMenuHost(for session: GeckoSession) -> SelectionActionMenuHostView? {
    guard let containerView = session.window?.view() else {
        return nil
    }
    
    let key = ObjectIdentifier(session)
    let host = activeSelectionMenuHosts[key] ?? {
        let host = SelectionActionMenuHostView()
        activeSelectionMenuHosts[key] = host
        return host
    }()
    
    if host.superview !== containerView {
        host.removeFromSuperview()
        containerView.addSubview(host)
    }
    
    return host
}

@MainActor
func dismissSelectionActionMenu(for session: GeckoSession) {
    let key = ObjectIdentifier(session)
    activeSelectionMenuHosts.removeValue(forKey: key)?.dismissAndRemove()
}

private func parseCGFloat(_ value: Any?) -> CGFloat? {
    if let number = value as? NSNumber {
        return CGFloat(number.doubleValue)
    }
    if let value = value as? Double {
        return CGFloat(value)
    }
    if let value = value as? Int {
        return CGFloat(value)
    }
    return nil
}

private func parseScreenRect(_ raw: Any?) -> CGRect? {
    guard let rect = raw as? [String: Any] else {
        return nil
    }
    guard let left = parseCGFloat(rect["left"]),
          let top = parseCGFloat(rect["top"]),
          let right = parseCGFloat(rect["right"]),
          let bottom = parseCGFloat(rect["bottom"]) else {
        return nil
    }
    
    let width = max(0, right - left)
    let height = max(0, bottom - top)
    guard width > 0, height > 0 else {
        return nil
    }
    
    return CGRect(x: left, y: top, width: width, height: height)
}

@MainActor
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
    let localRect: CGRect
    if let targetWindow = view as? UIWindow, targetWindow === window {
        localRect = windowRect
    } else {
        localRect = view.convert(windowRect, from: window)
    }
    let clippedRect = localRect.intersection(view.bounds)
    guard !clippedRect.isNull, !clippedRect.isEmpty else {
        return nil
    }
    
    return clippedRect
}

private func menuAnchorRect(from selectionRect: CGRect, in bounds: CGRect) -> CGRect {
    let anchorY: CGFloat
    
    // Okay so for some reasons that idk, the selection action menu on iOS 26
    // overlap the selection badly, so shift it up by 40 points. On older
    // iOS versions, the menu is wayyy above the selection but they don't
    // seem to be consistent on different devices so... no shift ¯\_(ツ)_/¯
    var verticalOffset: CGFloat = 40
    
    if #unavailable(iOS 26.0) {
        verticalOffset = 0
    }
    
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

@MainActor
private final class SelectionActionMenuHostView: UIView {
    weak var session: GeckoSession?
    
    private var actionId: String?
    private var availableActions = Set<String>()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        guard actionId != nil else {
            return nil
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionID.copy) ? self : nil
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionID.selectAll) ? self : nil
        }
        
        return nil
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard actionId != nil else {
            return false
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionID.copy)
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionID.selectAll)
        }
        
        return false
    }
    
    private func executeAction(_ id: String) {
        guard let session, let actionId else {
            return
        }
        
        session.dispatcher.dispatch(
            type: "GeckoView:ExecuteSelectionAction",
            message: [
                "actionId": actionId,
                "id": id,
            ]
        )
        
        hideMenu()
    }
    
    override func copy(_ sender: Any?) {
        executeAction(SelectionActionID.copy)
    }
    
    override func selectAll(_ sender: Any?) {
        executeAction(SelectionActionID.selectAll)
    }
    
    func present(
        on view: UIView,
        session: GeckoSession,
        actionId: String,
        anchorRect: CGRect,
        actions: [String]
    ) {
        self.session = session
        self.actionId = actionId
        availableActions = Set(actions)
        
        if superview !== view {
            removeFromSuperview()
            view.addSubview(self)
        }
        
        if frame != anchorRect {
            frame = anchorRect
        }
        
        if !isFirstResponder {
            becomeFirstResponder()
        }
        
        let menuController = UIMenuController.shared
        menuController.hideMenu(from: self)
        menuController.showMenu(from: self, rect: bounds)
    }
    
    func hideMenu() {
        if superview != nil {
            UIMenuController.shared.hideMenu(from: self)
        } else {
            UIMenuController.shared.hideMenu()
        }
        
        if isFirstResponder {
            resignFirstResponder()
        }
        
        actionId = nil
        availableActions.removeAll()
    }
    
    func dismissAndRemove() {
        hideMenu()
        removeFromSuperview()
        session = nil
    }
}

func newSelectionActionHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewSelectionAction",
        events: SelectionActionEvent.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, _, type, message in
        guard let event = SelectionActionEvent(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        switch event {
        case .show:
            let rawScreenRect: Any? = message?["screenRect"] ?? nil
            
            guard message?["editable"] as? Bool == false,
                  let actionId = message?["actionId"] as? String,
                  let actions = message?["actions"] as? [String],
                  actions.contains(SelectionActionID.copy) || actions.contains(SelectionActionID.selectAll),
                  let selection = message?["selection"] as? String,
                  !selection.isEmpty,
                  let screenRect = parseScreenRect(rawScreenRect),
                  let host = selectionMenuHost(for: session),
                  let targetView = host.superview,
                  let selectionRect = convertScreenRect(screenRect, into: targetView) else {
                activeSelectionMenuHost(for: session)?.hideMenu()
                return nil
            }
            
            let anchorRect = menuAnchorRect(from: selectionRect, in: targetView.bounds)
            host.present(
                on: targetView,
                session: session,
                actionId: actionId,
                anchorRect: anchorRect,
                actions: actions
            )
            
        case .hide:
            activeSelectionMenuHost(for: session)?.hideMenu()
        }
        
        return nil
    }
}
