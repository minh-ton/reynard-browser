//
//  DateTimePromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

public struct DateTimePromptRequest {
    public let id: String
    public let mode: String
    public let value: String
    public let min: String
    public let max: String
    public let step: String
    public let anchor: PromptAnchor
}
