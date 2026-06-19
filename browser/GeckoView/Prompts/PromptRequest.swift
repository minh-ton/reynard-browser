//
//  PromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import CoreGraphics
import Foundation

public struct PromptAnchor {
    public let rect: CGRect?
}

public struct PromptChoice {
    public let id: String
    public let label: String
    public let disabled: Bool
    public let selected: Bool
    public let items: [PromptChoice]?
    public let separator: Bool
}

public enum PromptRequest {
    case alert(AlertPromptRequest)
    case button(ButtonPromptRequest)
    case text(TextPromptRequest)
    case folderUpload(FolderUploadPromptRequest)
    case color(ColorPromptRequest)
    case dateTime(DateTimePromptRequest)
    case file(FilePickerPromptRequest)
    case choice(SelectPromptRequest)
    
    public var id: String {
        switch self {
        case .alert(let request):
            return request.id
        case .button(let request):
            return request.id
        case .text(let request):
            return request.id
        case .folderUpload(let request):
            return request.id
        case .color(let request):
            return request.id
        case .dateTime(let request):
            return request.id
        case .file(let request):
            return request.id
        case .choice(let request):
            return request.id
        }
    }
}
