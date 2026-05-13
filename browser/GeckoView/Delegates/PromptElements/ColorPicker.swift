//
//  ColorPicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit

@MainActor
final class ColorPicker: NSObject, UIPopoverPresentationControllerDelegate {
    let promptId: String
    let anchorRect: CGRect
    weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<String?, Never>?
    private var currentColor: UIColor = .black
    
    init(promptId: String, anchorRect: CGRect, geckoView: UIView) {
        self.promptId = promptId
        self.anchorRect = anchorRect
        self.geckoView = geckoView
    }
    
    func present(initialColor: UIColor) async -> String? {
        currentColor = initialColor
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showColorPicker(initialColor: initialColor)
        }
    }
    
    private func showColorPicker(initialColor: UIColor) {
        guard let geckoView = geckoView,
              let presentingVC = geckoView.nearestViewController() else {
            finishWithResult(nil)
            return
        }

        guard #available(iOS 14.0, *) else {
            // iOS 13 has no system color picker; keep the existing color.
            finishWithResult(initialColor.toHexString())
            return
        }
        
        let vc = UIColorPickerViewController()
        vc.selectedColor = initialColor
        vc.supportsAlpha = false
        vc.delegate = self
        vc.modalPresentationStyle = .popover
        
        if let popover = vc.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = anchorRect
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        
        presentingVC.present(vc, animated: true)
    }
    
    // don't full screen
    nonisolated func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    // dismissal
    nonisolated func popoverPresentationControllerShouldDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController
    ) -> Bool {
        let vc = popoverPresentationController.presentedViewController
        let color: UIColor?
        if #available(iOS 14.0, *) {
            color = (vc as? UIColorPickerViewController)?.selectedColor
        } else {
            color = nil
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishWithResult(color?.toHexString() ?? self.currentColor.toHexString())
        }
        return true
    }
    
    private func finishWithResult(_ result: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: result)
    }
}

@available(iOS 14.0, *)
extension ColorPicker: UIColorPickerViewControllerDelegate {
    nonisolated func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        let color = viewController.selectedColor
        Task { @MainActor [weak self] in
            self?.currentColor = color
        }
    }

    nonisolated func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let hex = viewController.selectedColor.toHexString()
        Task { @MainActor [weak self] in
            self?.finishWithResult(hex)
        }
    }
}
