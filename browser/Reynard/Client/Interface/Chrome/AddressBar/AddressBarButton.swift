//
//  AddressBarButton.swift
//  Reynard
//
//  Created by Minh Ton on 29/4/26.
//

import UIKit

final class AddressBarButton: UIButton {
    private enum UX {
        static let addressBarButtonTouchTargetScale: CGFloat = 2
        static let addressBarButtonSymbolPointSize: CGFloat = 14
    }
    
    private var isMenuVisible = false
    
    private var pendingMenuAfterDismissal: UIMenu?
    private var pendingMenuDismissalHandlers: [() -> Void] = []
    private var legacyMenuDelegate: LegacyContextMenuDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        imageView?.contentMode = .scaleAspectFit
        contentHorizontalAlignment = .fill
        contentVerticalAlignment = .fill
        contentEdgeInsets = .zero
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.addressBarButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
        if #unavailable(iOS 14.0) {
            let delegate = LegacyContextMenuDelegate(owner: self)
            addInteraction(UIContextMenuInteraction(delegate: delegate))
            legacyMenuDelegate = delegate
            addTarget(self, action: #selector(handleLegacyPrimaryTap), for: .touchUpInside)
        }
    }
    
    @objc private func handleLegacyPrimaryTap() {
        guard let interaction = interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }
        let center = NSValue(cgPoint: CGPoint(x: bounds.midX, y: bounds.midY))
        _ = interaction.perform(selector, with: center)
    }
    
    // MARK: - Menu Updates
    
    func setMenuPreservingPresentation(_ menu: UIMenu?) {
        legacyMenuDelegate?.menu = menu
        if #available(iOS 14.0, *) {
            if isMenuVisible,
               let menu,
               let contextMenuInteraction = self.contextMenuInteraction {
                pendingMenuAfterDismissal = menu
                contextMenuInteraction.updateVisibleMenu { visibleMenu in
                    if let replacementMenu = self.replacementMenu(for: visibleMenu, in: menu) {
                        return replacementMenu
                    }
                    return menu
                }
                return
            }
            pendingMenuAfterDismissal = nil
            self.menu = menu
        } else {
            pendingMenuAfterDismissal = nil
        }
    }
    
    func performAfterMenuDismissal(_ action: @escaping () -> Void) {
        guard isMenuVisible else {
            action()
            return
        }
        
        pendingMenuDismissalHandlers.append(action)
    }
    
    private func replacementMenu(for visibleMenu: UIMenu, in rootMenu: UIMenu) -> UIMenu? {
        if visibleMenu.identifier == rootMenu.identifier {
            return rootMenu
        }
        
        for child in rootMenu.children {
            guard let childMenu = child as? UIMenu else {
                continue
            }
            
            if childMenu.identifier == visibleMenu.identifier {
                return childMenu
            }
            
            if let nestedReplacement = replacementMenu(for: visibleMenu, in: childMenu) {
                return nestedReplacement
            }
        }
        
        return nil
    }
    
    // MARK: - Context Menu Lifecycle
    
    @available(iOS 14.0, *)
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        isMenuVisible = true
    }
    
    @available(iOS 14.0, *)
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        isMenuVisible = false
        let finalizeDismissal = { [weak self] in
            guard let self else {
                return
            }
            
            if #available(iOS 14.0, *),
               let pendingMenuAfterDismissal {
                self.menu = pendingMenuAfterDismissal
                self.pendingMenuAfterDismissal = nil
            }
            
            let handlers = self.pendingMenuDismissalHandlers
            self.pendingMenuDismissalHandlers.removeAll()
            handlers.forEach { $0() }
        }
        
        if let animator {
            animator.addCompletion(finalizeDismissal)
            return
        }
        
        finalizeDismissal()
    }
    
    fileprivate func legacyContextMenuWillDisplay() {
        isMenuVisible = true
    }
    
    fileprivate func legacyContextMenuWillEnd(animator: UIContextMenuInteractionAnimating?) {
        isMenuVisible = false
        let finalizeDismissal = { [weak self] in
            guard let self else {
                return
            }
            
            let handlers = self.pendingMenuDismissalHandlers
            self.pendingMenuDismissalHandlers.removeAll()
            handlers.forEach { $0() }
        }
        
        if let animator {
            animator.addCompletion(finalizeDismissal)
            return
        }
        
        finalizeDismissal()
    }
    
    // MARK: - Hit Testing
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0 else {
            return false
        }
        
        let bounds = self.bounds
        let widthIncrease = bounds.width * (UX.addressBarButtonTouchTargetScale - 1) / 2
        let heightIncrease = bounds.height * (UX.addressBarButtonTouchTargetScale - 1) / 2
        let hitFrame = bounds.insetBy(dx: -widthIncrease, dy: -heightIncrease)
        
        return hitFrame.contains(point)
    }
}

// MARK: - iOS 13 Context Menu Support

private final class LegacyContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var owner: AddressBarButton?
    var menu: UIMenu?
    
    init(owner: AddressBarButton) {
        self.owner = owner
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            menu
        }
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        owner?.legacyContextMenuWillDisplay()
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        owner?.legacyContextMenuWillEnd(animator: animator)
    }
}
