//
//  AuthPromptRequest.swift
//  Reynard
//
//  Created by Minh Ton on 19/7/26.
//

import Foundation

public struct AuthPromptRequest {
    public let id: String
    public let title: String
    public let message: String
    public let mode: String
    public let uri: String
    public let level: Int
    public let username: String
    public let password: String
}
