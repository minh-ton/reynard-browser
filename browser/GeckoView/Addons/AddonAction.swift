//
//  AddonAction.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

public enum AddonInstallMethod: String {
    case manager
}

public enum AddonEnableSource: String {
    case user
    case app
}

public enum AddonActionKind {
    case browser
    case page
}

public struct AddonAction {
    public let kind: AddonActionKind
    public let title: String?
    public let enabled: Bool?
    public let badgeText: String?
    public let popup: String?
    public let patternMatching: Bool
    
    init(kind: AddonActionKind, dictionary: [String: Any?]) {
        self.kind = kind
        title = dictionary["title"] as? String
        badgeText = dictionary["badgeText"] as? String
        popup = dictionary["popup"] as? String
        patternMatching = dictionary["patternMatching"] as? Bool ?? false
        
        if patternMatching {
            enabled = true
        } else {
            enabled = PayloadValue.bool(dictionary["enabled"] ?? nil)
        }
    }
    
    public func merged(with defaultAction: AddonAction) -> AddonAction {
        return AddonAction(
            kind: kind,
            title: title ?? defaultAction.title,
            enabled: enabled ?? defaultAction.enabled,
            badgeText: badgeText ?? defaultAction.badgeText,
            popup: popup ?? defaultAction.popup,
            patternMatching: patternMatching || defaultAction.patternMatching
        )
    }
    
    private init(
        kind: AddonActionKind,
        title: String?,
        enabled: Bool?,
        badgeText: String?,
        popup: String?,
        patternMatching: Bool
    ) {
        self.kind = kind
        self.title = title
        self.enabled = enabled
        self.badgeText = badgeText
        self.popup = popup
        self.patternMatching = patternMatching
    }
}
