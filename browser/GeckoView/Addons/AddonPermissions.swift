//
//  AddonPermissions.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

public struct AddonPermissionChangeRequest {
    public let permissions: [String]
    public let origins: [String]
    public let dataCollectionPermissions: [String]
    
    public init(
        permissions: [String] = [],
        origins: [String] = [],
        dataCollectionPermissions: [String] = []
    ) {
        self.permissions = permissions
        self.origins = origins
        self.dataCollectionPermissions = dataCollectionPermissions
    }
}

public enum AddonPermissionPromptKind {
    case install
    case optional
    case update
}

public struct AddonPermissionPrompt {
    public let kind: AddonPermissionPromptKind
    public let addon: Addon
    public let permissions: [String]
    public let origins: [String]
    public let dataCollectionPermissions: [String]
    
    public init(
        kind: AddonPermissionPromptKind,
        addon: Addon,
        permissions: [String],
        origins: [String],
        dataCollectionPermissions: [String]
    ) {
        self.kind = kind
        self.addon = addon
        self.permissions = permissions
        self.origins = origins
        self.dataCollectionPermissions = dataCollectionPermissions
    }
}

public struct AddonPermissionPromptResponse {
    public let allow: Bool
    public let privateBrowsingAllowed: Bool
    public let technicalAndInteractionDataGranted: Bool
    
    public init(
        allow: Bool,
        privateBrowsingAllowed: Bool = false,
        technicalAndInteractionDataGranted: Bool = false
    ) {
        self.allow = allow
        self.privateBrowsingAllowed = privateBrowsingAllowed
        self.technicalAndInteractionDataGranted = technicalAndInteractionDataGranted
    }
    
    public static let deny = AddonPermissionPromptResponse(allow: false)
}
