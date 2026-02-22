//
//  ContentPermission.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

public struct ContentPermission {
    public enum Permission: String {
        case geolocation = "geolocation"
        case desktopNotification = "desktop-notification"
        case persistentStorage = "persistent-storage"
        case webxr = "xr"
        case autoplayInaudible = "autoplay-media-inaudible"
        case autoplayAudible = "autoplay-media-audible"
        case mediaKeySystemAccess = "media-key-system-access"
        case tracking = "trackingprotection"
        case storageAccess = "storage-access"
    }

    public enum Value: Int32 {
        case prompt = 3
        case deny = 2
        case allow = 1
    }

    public let uri: String
    public let thirdPartyOrigin: String?
    public let privateMode: Bool
    public let permission: Permission?
    public let value: Value
    public let contextId: String?

    static func fromDictionary(_ dict: [String: Any?]) -> ContentPermission {
        guard let rawPerm = dict["perm"] as? String else {
            return ContentPermission(
                uri: dict["uri"] as? String ?? "",
                thirdPartyOrigin: nil,
                privateMode: dict["privateMode"] as? Bool ?? false,
                permission: nil,
                value: .prompt,
                contextId: nil
            )
        }

        var parsedPermission = Permission(rawValue: rawPerm)
        var parsedThirdPartyOrigin = dict["thirdPartyOrigin"] as? String

        if rawPerm.starts(with: "3rdPartyStorage^") {
            parsedThirdPartyOrigin = String(rawPerm.dropFirst(16))
            parsedPermission = .storageAccess
        } else if rawPerm.starts(with: "3rdPartyFrameStorage^") {
            parsedThirdPartyOrigin = String(rawPerm.dropFirst(21))
            parsedPermission = .storageAccess
        } else if rawPerm == "trackingprotection-pb" {
            parsedPermission = .tracking
        }

        let parsedValue: Value
        if let number = dict["value"] as? NSNumber, let value = Value(rawValue: number.int32Value) {
            parsedValue = value
        } else if let int32Value = dict["value"] as? Int32, let value = Value(rawValue: int32Value) {
            parsedValue = value
        } else {
            parsedValue = .prompt
        }

        return ContentPermission(
            uri: dict["uri"] as? String ?? "",
            thirdPartyOrigin: parsedThirdPartyOrigin,
            privateMode: dict["privateMode"] as? Bool ?? false,
            permission: parsedPermission,
            value: parsedValue,
            contextId: nil
        )
    }
}
