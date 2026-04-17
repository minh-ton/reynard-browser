//
//  PromptDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 8/4/26.
//

import UIKit

struct ChoiceItem {
    let id: String
    let label: String
    let disabled: Bool
    let selected: Bool
    let items: [ChoiceItem]?
    let separator: Bool
}

private func parseChoices(_ raw: Any?) -> [ChoiceItem] {
    guard let array = raw as? [[String: Any]] else { return [] }
    return array.map { dict in
        ChoiceItem(
            id: dict["id"] as? String ?? "",
            label: dict["label"] as? String ?? "",
            disabled: dict["disabled"] as? Bool ?? false,
            selected: dict["selected"] as? Bool ?? false,
            items: (dict["items"] != nil) ? parseChoices(dict["items"]) : nil,
            separator: dict["separator"] as? Bool ?? false
        )
    }
}

enum PromptEvents: String, CaseIterable {
    case prompt = "GeckoView:Prompt"
    case promptUpdate = "GeckoView:Prompt:Update"
    case promptDismiss = "GeckoView:Prompt:Dismiss"
}

@MainActor
private var activePickers: [String: SelectPicker] = [:]
@MainActor
private var activeColorPickers: [String: ColorPicker] = [:]
@MainActor
private var activeDateTimePickers: [String: DateTimePicker] = [:]
@MainActor
private var activeFilePickers: [String: FilePicker] = [:]

private func resolvePromptAnchor(
    from promptData: [String: Any],
    session: GeckoSession
) -> (geckoView: UIView, rect: CGRect)? {
    guard let rectDict = promptData["rect"] as? [String: Any],
          let childView = session.window?.view(),
          let geckoView = childView.superview,
          let window = geckoView.window else {
        return nil
    }
    
    var rect = CGRect(
        x: (rectDict["left"] as? Double) ?? 0,
        y: (rectDict["top"] as? Double) ?? 0,
        width: (rectDict["width"] as? Double) ?? 0,
        height: (rectDict["height"] as? Double) ?? 0
    )
    let windowPoint = window.convert(rect.origin, from: nil)
    rect.origin = geckoView.convert(windowPoint, from: nil)
    return (geckoView, rect)
}

func newPromptHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewPrompter",
        events: PromptEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let message else { return nil }
        guard let promptEvent = PromptEvents(rawValue: type) else { return nil }
        
        switch promptEvent {
        case .prompt:
            guard let promptData = message["prompt"] as? [String: Any] else {
                return nil
            }
            
            let promptType = promptData["type"] as? String ?? ""
            let promptId = promptData["id"] as? String ?? ""
            
            if promptType == "color" {
                let colorValue = promptData["value"] as? String ?? "#000000"
                let initialColor = UIColor(hexString: colorValue) ?? .black
                
                guard let anchor = resolvePromptAnchor(from: promptData, session: session) else {
                    return nil
                }
                
                let picker = ColorPicker(promptId: promptId, anchorRect: anchor.rect, geckoView: anchor.geckoView)
                activeColorPickers[promptId] = picker
                
                let result = await picker.present(initialColor: initialColor)
                activeColorPickers.removeValue(forKey: promptId)
                
                return result.map { ["color": $0] }
            }
            
            if promptType == "datetime" {
                let inputMode = promptData["mode"] as? String ?? "date"
                let value = promptData["value"] as? String ?? ""
                let min = promptData["min"] as? String ?? ""
                let max = promptData["max"] as? String ?? ""
                let step = promptData["step"] as? String ?? ""
                
                guard let anchor = resolvePromptAnchor(from: promptData, session: session) else {
                    return nil
                }
                
                let picker = DateTimePicker(promptId: promptId, inputMode: inputMode, anchorRect: anchor.rect, geckoView: anchor.geckoView)
                activeDateTimePickers[promptId] = picker
                
                let result = await picker.present(value: value, min: min, max: max, step: step)
                activeDateTimePickers.removeValue(forKey: promptId)
                
                return result.map { ["datetime": $0] }
            }
            
            if promptType == "file" {
                let mode = promptData["mode"] as? String ?? "single"
                let mimeTypes = promptData["mimeTypes"] as? [String] ?? []
                let capture = promptData["capture"] as? Int ?? 0
                
                guard let anchor = resolvePromptAnchor(from: promptData, session: session) else {
                    return nil
                }
                
                let picker = FilePicker(
                    promptId: promptId,
                    mode: mode,
                    mimeTypes: mimeTypes,
                    capture: capture,
                    anchorRect: anchor.rect,
                    geckoView: anchor.geckoView
                )
                activeFilePickers[promptId] = picker
                
                let result = await picker.present()
                activeFilePickers.removeValue(forKey: promptId)
                return result
            }
            
            if promptType == "choice" {
                let mode = promptData["mode"] as? String ?? "single"
                let rawChoices = promptData["choices"]
                let choices = parseChoices(rawChoices)
                
                guard let anchor = resolvePromptAnchor(from: promptData, session: session) else {
                    return nil
                }
                
                let picker = SelectPicker(
                    promptId: promptId,
                    mode: mode,
                    choices: choices,
                    sourceRect: anchor.rect,
                    geckoView: anchor.geckoView
                )
                activePickers[promptId] = picker
                
                let result = await picker.present()
                activePickers.removeValue(forKey: promptId)
                
                if let selectedIds = result {
                    return ["choices": selectedIds]
                }
                return nil
            }
            
            return nil
            
        case .promptUpdate:
            guard let promptData = message["prompt"] as? [String: Any] else {
                return nil
            }
            let promptId = promptData["id"] as? String ?? ""
            if let picker = activePickers[promptId] {
                let newChoices = parseChoices(promptData["choices"])
                let newMode = promptData["mode"] as? String ?? picker.mode
                picker.updateChoices(newChoices, mode: newMode)
            }
            return nil
            
        case .promptDismiss:
            // Gecko fires dismiss when the <select> element blurs, which happens when
            // we present native UI (the modal steals focus). Our picker manages its own
            // lifecycle through user interaction, so we intentionally ignore dismiss
            // while a picker is actively presented.
            return nil
        }
    }
}


extension UIView {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }
}

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
    
    func toHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#000000" }
        return String(
            format: "#%02x%02x%02x",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
