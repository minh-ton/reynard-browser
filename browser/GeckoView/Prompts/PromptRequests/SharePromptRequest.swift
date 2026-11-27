//
//  SharePromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 15/8/26.
//

import Foundation

public enum SharePromptResult: Int {
    case success = 0
    case failure = 1
    case aborted = 2
}

public struct SharePromptRequest {
    public let id: String
    public let title: String
    public let text: String
    public let url: String?
    public let anchor: PromptAnchor
}
