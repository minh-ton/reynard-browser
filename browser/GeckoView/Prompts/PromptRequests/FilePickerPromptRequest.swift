//
//  FilePickerPromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

public struct FilePickerPromptRequest {
    public let id: String
    public let mode: String
    public let mimeTypes: [String]
    public let capture: Int
    public let anchor: PromptAnchor
}
