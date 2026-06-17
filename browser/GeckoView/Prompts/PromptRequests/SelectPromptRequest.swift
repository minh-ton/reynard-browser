//
//  SelectPromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

public struct SelectPromptRequest {
    public let id: String
    public let mode: String
    public let choices: [PromptChoice]
    public let anchor: PromptAnchor
}
