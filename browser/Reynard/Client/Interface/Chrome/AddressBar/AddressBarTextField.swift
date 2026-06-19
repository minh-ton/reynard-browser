//
//  AddressBarTextField.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class AddressBarTextField: UITextField {
    var isAutocompleteActive = false
    private var suppressTextActions = false
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isAutocompleteActive {
            suppressTextActions = true
            DispatchQueue.main.async { [weak self] in
                self?.suppressTextActions = false
            }
            return
        }
        
        super.touchesBegan(touches, with: event)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isAutocompleteActive || suppressTextActions {
            return false
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
}
