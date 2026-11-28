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
        static let addressBarButtonPointerHighlightDiameter: CGFloat = 34
    }
    
    var horizontalTouchTargetExpansion: CGFloat?
    var presentsMenuOnTouchUp = false {
        didSet {
            if #available(iOS 14.0, *) {
                showsMenuAsPrimaryAction = !presentsMenuOnTouchUp
                addTarget(self, action: #selector(handleTouchUpMenuTap), for: .touchUpInside)
            }
        }
    }
    
    private var isMenuVisible = false
    private var isMenuRequestedByTap = false
    
    private var pendingMenuAfterDismissal: UIMenu?
    private var pendingMenuDismissalHandlers: [() -> Void] = []
    private var legacyMenuDelegate: LegacyContextMenuDelegate?
    private var menuProvider: (() -> UIMenu?)?
    
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
        if #available(iOS 13.4, *) {
            pointerStyleProvider = { button, _, _ in
                let diameter = UX.addressBarButtonPointerHighlightDiameter
                let frame = CGRect(
                    x: button.center.x - diameter / 2,
                    y: button.center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                return UIPointerStyle(
                    effect: .highlight(UITargetedPreview(view: button)),
                    shape: .roundedRect(frame, radius: diameter / 2)
                )
            }
        }
        if #unavailable(iOS 14.0) {
            let delegate = LegacyContextMenuDelegate(owner: self)
            addInteraction(UIContextMenuInteraction(delegate: delegate))
            legacyMenuDelegate = delegate
            addTarget(self, action: #selector(handleTouchUpMenuTap), for: .touchUpInside)
        }
    }
    
    @objc private func handleTouchUpMenuTap() {
        guard let interaction = interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }
        let center = NSValue(cgPoint: CGPoint(x: bounds.midX, y: bounds.midY))
        isMenuRequestedByTap = true
        _ = interaction.perform(selector, with: center)
    }
    
    // MARK: - Menu Updates
    
    func setMenuPreservingPresentation(_ menu: UIMenu?) {
        legacyMenuDelegate?.menu = menu
        if #available(iOS 14.0, *) {
            if isMenuVisible {
                pendingMenuAfterDismissal = menu
                return
            }
            pendingMenuAfterDismissal = nil
            self.menu = menu
        } else {
            pendingMenuAfterDismissal = nil
        }
    }
    
    func setMenuProvider(_ provider: @escaping () -> UIMenu?) {
        menuProvider = provider
        legacyMenuDelegate?.menuProvider = provider
        if #available(iOS 14.0, *) {
            menu = makeDeferredMenu()
        }
    }
    
    func performAfterMenuDismissal(_ action: @escaping () -> Void) {
        guard isMenuVisible else {
            action()
            return
        }
        
        pendingMenuDismissalHandlers.append(action)
    }
    
    // MARK: - Context Menu Lifecycle
    
    @available(iOS 14.0, *)
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard shouldProvideMenu() else {
            return nil
        }
        
        return super.contextMenuInteraction(interaction, configurationForMenuAtLocation: location)
    }
    
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
            } else if #available(iOS 14.0, *), self.menuProvider != nil {
                self.menu = self.makeDeferredMenu()
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
    
    @available(iOS 14.0, *)
    private func makeDeferredMenu() -> UIMenu {
        let deferredElement = UIDeferredMenuElement { [weak self] completion in
            completion(self?.menuProvider?()?.children ?? [])
        }
        return UIMenu(children: [deferredElement])
    }
    
    fileprivate func shouldProvideMenu() -> Bool {
        defer { isMenuRequestedByTap = false }
        return !presentsMenuOnTouchUp || isMenuRequestedByTap
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
        let widthIncrease = horizontalTouchTargetExpansion ?? bounds.width * (UX.addressBarButtonTouchTargetScale - 1) / 2
        let heightIncrease = bounds.height * (UX.addressBarButtonTouchTargetScale - 1) / 2
        let hitFrame = bounds.insetBy(dx: -widthIncrease, dy: -heightIncrease)
        
        return hitFrame.contains(point)
    }
}

// MARK: - iOS 13 Context Menu Support

private final class LegacyContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var owner: AddressBarButton?
    var menu: UIMenu?
    var menuProvider: (() -> UIMenu?)?
    
    init(owner: AddressBarButton) {
        self.owner = owner
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard owner?.shouldProvideMenu() == true,
              let menu = menuProvider?() ?? menu else {
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
