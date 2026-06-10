//
//  AddressBarTextField.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class AddressBarTextField: UITextField {
    // MARK: - State

    var isAutocompleteActive = false
    private var suppressTextActions = false

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isAutocompleteActive {
            // The overlay owns taps while a completion is visible; suppress the delayed edit menu too.
            suppressTextActions = true
            DispatchQueue.main.async { [weak self] in
                self?.suppressTextActions = false
            }
            return
        }

        super.touchesBegan(touches, with: event)
    }

    // MARK: - Edit Menu

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isAutocompleteActive || suppressTextActions {
            return false
        }

        return super.canPerformAction(action, withSender: sender)
    }
}
