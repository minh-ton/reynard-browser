//
//  SelectPicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import GeckoView
import UIKit

@MainActor
final class SelectPicker {
    private var mode: String
    private var choices: [PromptChoice]
    private let sourceRect: CGRect
    private weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<[String]?, Never>?
    private var anchorButton: SelectPickerMenuAnchorButton?
    private var presentedController: UIViewController?
    
    init(mode: String, choices: [PromptChoice], sourceRect: CGRect, geckoView: UIView) {
        self.mode = mode
        self.choices = choices
        self.sourceRect = sourceRect
        self.geckoView = geckoView
    }
    
    // MARK: - Presentation
    
    func present() async -> [String]? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if mode == "multiple" {
                showMultiSelect()
            } else {
                showSingleSelect()
            }
        }
    }
    
    func updateChoices(_ updatedChoices: [PromptChoice], mode updatedMode: String) {
        choices = updatedChoices
        mode = updatedMode
        if let nav = presentedController as? UINavigationController,
           let multiSelectController = nav.viewControllers.first as? MultiSelectViewController {
            multiSelectController.updateChoices(updatedChoices)
        }
    }
    
    func cancelAndDismiss() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        presentedController?.dismiss(animated: false)
        presentedController = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: nil)
        }
    }
    
    // MARK: - Single Select
    
    private func showSingleSelect() {
        guard let geckoView = geckoView else {
            finish(nil)
            return
        }
        
        guard #available(iOS 14.0, *) else {
            showSingleSelectFallback(in: geckoView)
            return
        }
        
        let button = SelectPickerMenuAnchorButton(frame: sourceRect)
        button.backgroundColor = .clear
        
        let menuElements = buildMenuElements(from: choices)
        button.menu = UIMenu(children: menuElements)
        button.showsMenuAsPrimaryAction = true
        
        button.onMenuDismissed = { [weak self] in
            self?.handleMenuDismissed()
        }
        
        geckoView.addSubview(button)
        anchorButton = button
        
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.anchorButton else { return }
            let interaction = button.interactions.compactMap { $0 as? UIContextMenuInteraction }.first
            guard let interaction = interaction else {
                self?.handleMenuDismissed()
                return
            }
            
            // Ugh we have to use private API here
            let presentMenuSelector = NSSelectorFromString("_presentMenuAtLocation:")
            if interaction.responds(to: presentMenuSelector) {
                let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                let implementation = interaction.method(for: presentMenuSelector)
                typealias PresentMenu = @convention(c) (AnyObject, Selector, CGPoint) -> Void
                let presentMenu = unsafeBitCast(implementation, to: PresentMenu.self)
                presentMenu(interaction, presentMenuSelector, center)
            } else {
                self?.handleMenuDismissed()
            }
        }
    }
    
    private func showSingleSelectFallback(in geckoView: UIView) {
        guard let presenter = UIApplication.shared.topViewController() else {
            finish(nil)
            return
        }
        
        let alert = UIAlertController(title: "Select Option", message: nil, preferredStyle: .actionSheet)
        for item in selectableChoices(from: choices) {
            let title = item.label.isEmpty ? "Option" : item.label
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.finish([item.id])
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(nil)
        })
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = sourceRect
            popover.permittedArrowDirections = []
        }
        
        presenter.present(alert, animated: true)
        presentedController = alert
    }
    
    private func selectableChoices(from items: [PromptChoice]) -> [PromptChoice] {
        var result: [PromptChoice] = []
        for item in items where !item.separator {
            if let subItems = item.items {
                result.append(contentsOf: selectableChoices(from: subItems))
            } else {
                result.append(item)
            }
        }
        return result
    }
    
    private func buildMenuElements(from items: [PromptChoice]) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        var pendingItems: [UIMenuElement] = []
        
        for item in items {
            if item.separator {
                if !pendingItems.isEmpty {
                    let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
                    elements.append(group)
                    pendingItems = []
                }
                continue
            }
            
            if let subItems = item.items {
                if !pendingItems.isEmpty {
                    let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
                    elements.append(group)
                    pendingItems = []
                }
                let subActions = buildMenuElements(from: subItems)
                let submenu = UIMenu(title: item.label, options: .displayInline, children: subActions)
                elements.append(submenu)
            } else {
                let choiceId = item.id
                let action = UIAction(
                    title: item.label,
                    attributes: item.disabled ? .disabled : [],
                    state: item.selected ? .on : .off
                ) { [weak self] _ in
                    self?.finish([choiceId])
                }
                pendingItems.append(action)
            }
        }
        
        if !pendingItems.isEmpty {
            if elements.isEmpty {
                return pendingItems
            }
            let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
            elements.append(group)
        }
        
        return elements
    }
    
    // MARK: - Menu Dismissal
    
    private func handleMenuDismissed() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        // If no selection was made yet, resume with nil (cancel)
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: nil)
        }
    }
    
    // MARK: - Multi Select
    
    private func showMultiSelect() {
        guard let geckoView = geckoView,
              let presenter = UIApplication.shared.topViewController() else {
            finish(nil)
            return
        }
        
        let multiSelectController = MultiSelectViewController(choices: choices) { [weak self] selectedIds in
            self?.presentedController = nil
            self?.finish(selectedIds)
        }
        let navigationController = UINavigationController(rootViewController: multiSelectController)
        navigationController.modalPresentationStyle = .pageSheet
        
        if let popover = navigationController.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = sourceRect
        }
        
        presenter.present(navigationController, animated: true)
        presentedController = navigationController
    }
    
    // MARK: - Completion
    
    private func finish(_ result: [String]?) {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}
