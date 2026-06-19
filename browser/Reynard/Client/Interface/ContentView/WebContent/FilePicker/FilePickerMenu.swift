//
//  FilePickerMenu.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
import UIKit

extension FilePicker {
    func showMenu() {
        guard let geckoView else {
            finish(with: nil)
            return
        }
        
        guard #available(iOS 14.0, *), !anchorRect.isEmpty else {
            showActionSheet(in: geckoView)
            return
        }
        
        let button = FilePickerMenuAnchorButton(frame: anchorRect)
        button.backgroundColor = .clear
        button.menu = buildMenu()
        button.showsMenuAsPrimaryAction = true
        button.onMenuDismissed = { [weak self] in
            self?.handleMenuDismissed()
        }
        
        geckoView.addSubview(button)
        anchorButton = button
        presentMenuFromAnchorButton()
    }
    
    @available(iOS 14.0, *)
    private func buildMenu() -> UIMenu {
        UIMenu(children: [
            menuAction(.photoLibrary, symbol: "reynard.photo.on.rectangle"),
            menuAction(.camera, symbol: "reynard.camera"),
            menuAction(.chooseFile, symbol: "reynard.document"),
        ])
    }
    
    private func presentMenuFromAnchorButton() {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.anchorButton else { return }
            let interaction = button.interactions.compactMap { $0 as? UIContextMenuInteraction }.first
            guard let interaction else {
                self?.handleMenuDismissed()
                return
            }
            
            let selector = NSSelectorFromString("_presentMenuAtLocation:")
            if interaction.responds(to: selector) {
                let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                let implementation = interaction.method(for: selector)
                typealias PresentMenu = @convention(c) (AnyObject, Selector, CGPoint) -> Void
                let presentMenu = unsafeBitCast(implementation, to: PresentMenu.self)
                presentMenu(interaction, selector, center)
            } else {
                self?.handleMenuDismissed()
            }
        }
    }
    
    func showActionSheet(in geckoView: UIView) {
        guard let presenter = UIApplication.shared.topViewController() else {
            finish(with: nil)
            return
        }
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for action in availableActions {
            alert.addAction(UIAlertAction(title: title(for: action), style: .default) { [weak self] _ in
                self?.launchFollowupPicker {
                    self?.performAction(action)
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(with: nil)
        })
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = CGRect(x: geckoView.bounds.midX, y: geckoView.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presenter.present(alert, animated: true)
        presentedController = alert
    }
    
    @available(iOS 14.0, *)
    private func menuAction(_ action: PickerAction, symbol: String) -> UIAction {
        UIAction(
            title: title(for: action),
            image: UIImage(named: symbol),
            attributes: canPerform(action) ? [] : .disabled
        ) { [weak self] _ in
            self?.launchFollowupPicker {
                self?.performAction(action)
            }
        }
    }
    
    var preferredInitialAction: PickerAction? {
        guard capture != .none,
              acceptedTypes.captureMediaKind != nil,
              canUseCamera else {
            return nil
        }
        return .camera
    }
    
    var availableActions: [PickerAction] {
        var actions: [PickerAction] = []
        if canUsePhotoLibrary {
            actions.append(.photoLibrary)
        }
        if canUseCamera {
            actions.append(.camera)
        }
        actions.append(.chooseFile)
        return actions
    }
    
    private func title(for action: PickerAction) -> String {
        switch action {
        case .photoLibrary:
            return "Photo Library"
        case .camera:
            return cameraActionTitle
        case .chooseFile:
            return mode == .folder ? "Choose Folder" : "Choose File"
        }
    }
    
    private func canPerform(_ action: PickerAction) -> Bool {
        switch action {
        case .photoLibrary:
            return canUsePhotoLibrary
        case .camera:
            return canUseCamera
        case .chooseFile:
            return true
        }
    }
    
    private var cameraActionTitle: String {
        let mediaTypes = Set(acceptedTypes.mediaTypes)
        let supportsImages = mediaTypes.contains(kUTTypeImage as String)
        let supportsVideos = mediaTypes.contains(kUTTypeMovie as String)
        
        switch (supportsImages, supportsVideos) {
        case (true, true):
            return "Take Photo or Video"
        case (true, false):
            return "Take Photo"
        case (false, true):
            return "Take Video"
        case (false, false):
            return "Take Photo"
        }
    }
    
    func launchFollowupPicker(_ action: @escaping @MainActor () -> Void) {
        launchedFollowupPicker = true
        DispatchQueue.main.async(execute: action)
    }
    
    func handleMenuDismissed() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        if launchedFollowupPicker {
            return
        }
        finish(with: nil)
    }
}
