//
//  ColorPicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit

@MainActor
final class ColorPicker: NSObject, UIPopoverPresentationControllerDelegate {
    private let anchorRect: CGRect
    private weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<String?, Never>?
    private weak var presentedController: UIViewController?
    
    init(anchorRect: CGRect, geckoView: UIView) {
        self.anchorRect = anchorRect
        self.geckoView = geckoView
    }
    
    // MARK: - Presentation
    
    func present(initialColor: UIColor) async -> String? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showColorPicker(initialColor: initialColor)
        }
    }
    
    private func showColorPicker(initialColor: UIColor) {
        guard let geckoView = geckoView,
              let presenter = UIApplication.shared.topViewController(in: geckoView.window) else {
            finish(nil)
            return
        }
        
        guard #available(iOS 14.0, *) else {
            // iOS 13 has no system color picker; keep the existing color.
            finish(initialColor.toHexString())
            return
        }
        
        let colorPicker = UIColorPickerViewController()
        colorPicker.selectedColor = initialColor
        colorPicker.supportsAlpha = false
        colorPicker.delegate = self
        colorPicker.modalPresentationStyle = .popover
        
        if let popover = colorPicker.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = anchorRect
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        
        presenter.present(colorPicker, animated: true)
        presentedController = colorPicker
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
    nonisolated func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard #available(iOS 14.0, *),
              let controller = presentationController.presentedViewController as? UIColorPickerViewController else { return }
        finish(controller.selectedColor.toHexString())
    }
    
    // MARK: - Completion
    
    private func finish(_ result: String?) {
        guard let continuation else { return }
        presentedController = nil
        self.continuation = nil
        continuation.resume(returning: result)
    }
    
    func cancelAndDismiss() {
        presentedController?.dismiss(animated: false)
        finish(nil)
    }
}

@available(iOS 14.0, *)
extension ColorPicker: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        finish(viewController.selectedColor.toHexString())
    }
    
}
