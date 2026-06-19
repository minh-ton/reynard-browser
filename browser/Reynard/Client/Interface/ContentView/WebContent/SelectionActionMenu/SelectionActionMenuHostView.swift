//
//  SelectionActionMenuHostView.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

@MainActor
final class SelectionActionMenuHostView: UIView {
    private weak var session: GeckoSession?
    private var actionId: String?
    private var availableActions = Set<String>()
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        guard actionId != nil else {
            return nil
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionCommand.copy) ? self : nil
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionCommand.selectAll) ? self : nil
        }
        
        return nil
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard actionId != nil else {
            return false
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionCommand.copy)
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionCommand.selectAll)
        }
        
        return false
    }
    
    override func copy(_ sender: Any?) {
        executeAction(SelectionActionCommand.copy)
    }
    
    override func selectAll(_ sender: Any?) {
        executeAction(SelectionActionCommand.selectAll)
    }
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }
    
    // MARK: - Setup
    
    private func configureAppearance() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    // MARK: - Presentation
    
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
    
    // MARK: - Actions
    
    private func executeAction(_ commandId: String) {
        guard let session, let actionId else {
            return
        }
        
        session.executeSelectionAction(actionId: actionId, commandId: commandId)
        hideMenu()
    }
}
