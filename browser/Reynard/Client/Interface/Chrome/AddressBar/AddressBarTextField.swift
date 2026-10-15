//
//  AddressBarTextField.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class AddressBarTextField: UITextField {
    enum CursorBoundary {
        case start
        case end
    }
    
    var isAutocompleteActive = false
    var isFocusPreviewActive = false
    var isSuggestionNavigationEnabled: (() -> Bool)?
    var onMoveSuggestionSelection: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveCursor: ((CursorBoundary) -> Void)?
    var onDismissEditing: (() -> Void)?
    private var suppressTextActions = false
    
    private lazy var cursorToStartCommand = makeKeyCommand(
        input: UIKeyCommand.inputLeftArrow,
        action: #selector(moveCursorToStart(_:))
    )
    private lazy var cursorToEndCommand = makeKeyCommand(
        input: UIKeyCommand.inputRightArrow,
        action: #selector(moveCursorToEnd(_:))
    )
    private lazy var dismissEditingCommand: UIKeyCommand = {
        let command = UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(dismissEditing(_:))
        )
        if #available(iOS 15.0, *) {
            command.wantsPriorityOverSystemBehavior = true
        }
        return command
    }()
    
    override var keyCommands: [UIKeyCommand]? {
        var commands = (super.keyCommands ?? []) + [dismissEditingCommand]
        if isAutocompleteActive {
            commands += [cursorToStartCommand, cursorToEndCommand]
        }
        return commands
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isSuggestionNavigationEnabled?() == true else {
            super.pressesBegan(presses, with: event)
            return
        }
        
        var handledPress = false
        for press in presses {
            let offset: Int?
            var shouldSubmit = false
            if #available(iOS 13.4, *), let key = press.key {
                guard key.modifierFlags.isEmpty else {
                    continue
                }
                switch key.keyCode {
                case .keyboardUpArrow:
                    offset = -1
                case .keyboardDownArrow:
                    offset = 1
                case .keyboardReturnOrEnter, .keyboardReturn, .keypadEnter:
                    offset = nil
                    shouldSubmit = true
                default:
                    offset = nil
                }
            } else {
                switch press.type {
                case .upArrow:
                    offset = -1
                case .downArrow:
                    offset = 1
                case .select:
                    offset = nil
                    shouldSubmit = true
                default:
                    offset = nil
                }
            }
            
            if let offset {
                dismissPendingTextInput()
                onMoveSuggestionSelection?(offset)
                handledPress = true
            } else if shouldSubmit {
                dismissPendingTextInput()
                onSubmit?()
                handledPress = true
            }
        }
        
        if !handledPress {
            super.pressesBegan(presses, with: event)
        }
    }
    
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
        if action == #selector(dismissEditing(_:)) {
            return true
        }
        if action == #selector(moveCursorToStart(_:)) ||
            action == #selector(moveCursorToEnd(_:)) {
            return isAutocompleteActive
        }
        if isFocusPreviewActive,
           action == #selector(copy(_:)) ||
            action == #selector(cut(_:)) {
            return !(text ?? "").isEmpty
        }
        if action == #selector(paste(_:)) {
            return super.canPerformAction(action, withSender: sender)
        }
        if isAutocompleteActive || suppressTextActions {
            return false
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func copy(_ sender: Any?) {
        guard isFocusPreviewActive else {
            super.copy(sender)
            return
        }
        
        UIPasteboard.general.string = text
    }
    
    override func cut(_ sender: Any?) {
        guard isFocusPreviewActive else {
            super.cut(sender)
            return
        }
        
        copy(sender)
        let range = NSRange(location: 0, length: (text ?? "").utf16.count)
        _ = delegate?.textField?(self, shouldChangeCharactersIn: range, replacementString: "")
    }
    
    private func makeKeyCommand(input: String, action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: [],
            action: action
        )
        if #available(iOS 15.0, *) {
            command.wantsPriorityOverSystemBehavior = true
        }
        return command
    }
    
    private func dismissPendingTextInput() {
        let clearInputSelector = NSSelectorFromString("clearInputWithCandidatesCleared:")
        guard let keyboardClass = NSClassFromString("UIKeyboardImpl") as AnyObject?,
              keyboardClass.responds(to: NSSelectorFromString("sharedInstance")),
              let keyboard = keyboardClass
            .perform(NSSelectorFromString("sharedInstance"))?
            .takeUnretainedValue() as? NSObject,
              keyboard.responds(to: clearInputSelector) else {
            return
        }
        
        keyboard.perform(clearInputSelector, with: NSNumber(value: true))
        
        /*
         let autocorrectionControllerSelector = NSSelectorFromString("autocorrectionController")
         let clearSuggestionsSelector = NSSelectorFromString("clearAutofillAndTextSuggestions")
         guard keyboard.responds(to: autocorrectionControllerSelector),
         let autocorrectionController = keyboard
         .perform(autocorrectionControllerSelector)?
         .takeUnretainedValue() as? NSObject,
         autocorrectionController.responds(to: clearSuggestionsSelector) else {
         return
         }
         
         autocorrectionController.perform(clearSuggestionsSelector)
         */
    }
    
    @objc private func moveCursorToStart(_ sender: UIKeyCommand) {
        onMoveCursor?(.start)
    }
    
    @objc private func moveCursorToEnd(_ sender: UIKeyCommand) {
        onMoveCursor?(.end)
    }
    
    @objc private func dismissEditing(_ sender: UIKeyCommand) {
        onDismissEditing?()
    }
}
