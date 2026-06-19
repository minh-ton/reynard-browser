//
//  PromptParser.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

func parsePromptRequest(_ data: [String: Any]) -> PromptRequest? {
    let promptID = data["id"] as? String ?? ""
    let promptType = data["type"] as? String ?? ""
    
    switch promptType {
    case "alert":
        return .alert(AlertPromptRequest(
            id: promptID,
            title: data["title"] as? String ?? "",
            message: data["msg"] as? String ?? ""
        ))
        
    case "button":
        return .button(ButtonPromptRequest(
            id: promptID,
            title: data["title"] as? String ?? "",
            message: data["msg"] as? String ?? "",
            buttonTitles: PayloadValue.strings(data["btnTitle"]),
            customButtonTitles: PayloadValue.strings(data["btnCustomTitle"])
        ))
        
    case "text":
        return .text(TextPromptRequest(
            id: promptID,
            title: data["title"] as? String ?? "",
            message: data["msg"] as? String ?? "",
            value: data["value"] as? String ?? ""
        ))
        
    case "folderUpload":
        return .folderUpload(FolderUploadPromptRequest(
            id: promptID,
            directoryName: data["directoryName"] as? String ?? ""
        ))
        
    case "color":
        return .color(ColorPromptRequest(
            id: promptID,
            value: data["value"] as? String ?? "#000000",
            anchor: parseAnchor(data["rect"])
        ))
        
    case "datetime":
        return .dateTime(DateTimePromptRequest(
            id: promptID,
            mode: data["mode"] as? String ?? "date",
            value: data["value"] as? String ?? "",
            min: data["min"] as? String ?? "",
            max: data["max"] as? String ?? "",
            step: data["step"] as? String ?? "",
            anchor: parseAnchor(data["rect"])
        ))
        
    case "file":
        return .file(FilePickerPromptRequest(
            id: promptID,
            mode: data["mode"] as? String ?? "single",
            mimeTypes: data["mimeTypes"] as? [String] ?? [],
            capture: data["capture"] as? Int ?? 0,
            anchor: parseAnchor(data["rect"])
        ))
        
    case "choice":
        return .choice(SelectPromptRequest(
            id: promptID,
            mode: data["mode"] as? String ?? "single",
            choices: parseChoices(data["choices"]),
            anchor: parseAnchor(data["rect"])
        ))
        
    default:
        return nil
    }
}

private func parseChoices(_ value: Any?) -> [PromptChoice] {
    guard let choices = value as? [[String: Any]] else { return [] }
    return choices.map { payload in
        PromptChoice(
            id: payload["id"] as? String ?? "",
            label: payload["label"] as? String ?? "",
            disabled: payload["disabled"] as? Bool ?? false,
            selected: payload["selected"] as? Bool ?? false,
            items: payload["items"] != nil ? parseChoices(payload["items"]) : nil,
            separator: payload["separator"] as? Bool ?? false
        )
    }
}

private func parseAnchor(_ value: Any?) -> PromptAnchor {
    guard let rect = value as? [String: Any] else {
        return PromptAnchor(rect: nil)
    }
    
    return PromptAnchor(rect: CGRect(
        x: PayloadValue.double(rect["left"]) ?? 0,
        y: PayloadValue.double(rect["top"]) ?? 0,
        width: PayloadValue.double(rect["width"]) ?? 0,
        height: PayloadValue.double(rect["height"]) ?? 0
    ))
}
