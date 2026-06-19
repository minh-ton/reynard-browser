//
//  PromptResponse.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import Foundation

public struct PromptResponse {
    let geckoMessage: [String: Any]
    
    public static func button(_ index: Int) -> PromptResponse {
        return PromptResponse(geckoMessage: ["button": index])
    }
    
    public static func text(_ value: String) -> PromptResponse {
        return PromptResponse(geckoMessage: ["text": value])
    }
    
    public static func folderUpload(allowed: Bool) -> PromptResponse {
        return PromptResponse(geckoMessage: ["allow": allowed])
    }
    
    public static func color(_ value: String) -> PromptResponse {
        return PromptResponse(geckoMessage: ["color": value])
    }
    
    public static func dateTime(_ value: String) -> PromptResponse {
        return PromptResponse(geckoMessage: ["datetime": value])
    }
    
    public static func files(_ message: [String: Any]) -> PromptResponse {
        return PromptResponse(geckoMessage: message)
    }
    
    public static func choices(_ ids: [String]) -> PromptResponse {
        return PromptResponse(geckoMessage: ["choices": ids])
    }
}
