//
//  ButtonPromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

public struct ButtonPromptRequest {
    public let id: String
    public let title: String
    public let message: String
    public let buttonTitles: [String]
    public let customButtonTitles: [String]
}
