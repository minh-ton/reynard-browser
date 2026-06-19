//
//  ContentPermission.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

public struct ContentPermission {
    public enum Permission: String {
        case camera = "camera"
        case microphone = "microphone"
        case geolocation = "geolocation"
        case desktopNotification = "desktop-notification"
        case persistentStorage = "persistent-storage"
        case webxr = "xr"
        case autoplay = "autoplay-media"
        case mediaKeySystemAccess = "media-key-system-access"
        case tracking = "trackingprotection"
        case storageAccess = "storage-access"
        case localDeviceAccess = "loopback-network"
        case localNetworkAccess = "local-network"
        case deviceSensors = "device-sensors"
    }
    
    public enum Value: Int32 {
        case prompt = 3
        case deny = 2
        case allow = 1
        case blockAll = 5
    }
    
    public let uri: String
    public let thirdPartyOrigin: String?
    public let privateMode: Bool
    public let permission: Permission?
    public let value: Value
    public let rawValue: Int32
    public let contextId: String?
    let principal: String
    let rawPermission: String
    
    static func fromDictionary(_ payload: [String: Any?]) -> ContentPermission {
        let rawValue = PayloadValue.int32(payload["value"] ?? nil) ?? ContentPermission.Value.prompt.rawValue
        guard let permissionKey = payload["perm"] as? String else {
            return ContentPermission(
                uri: payload["uri"] as? String ?? "",
                thirdPartyOrigin: nil,
                privateMode: payload["privateMode"] as? Bool ?? false,
                permission: nil,
                value: .prompt,
                rawValue: rawValue,
                contextId: payload["contextId"] as? String,
                principal: payload["principal"] as? String ?? "",
                rawPermission: ""
            )
        }
        
        var permission = Permission(rawValue: permissionKey)
        var thirdPartyOrigin = payload["thirdPartyOrigin"] as? String
        
        if permissionKey.starts(with: "3rdPartyStorage^") {
            thirdPartyOrigin = String(permissionKey.dropFirst(16))
            permission = .storageAccess
        } else if permissionKey.starts(with: "3rdPartyFrameStorage^") {
            thirdPartyOrigin = String(permissionKey.dropFirst(21))
            permission = .storageAccess
        } else if permissionKey == "trackingprotection-pb" {
            permission = .tracking
        } else if permissionKey == "geo" {
            permission = .geolocation
        }
        
        return ContentPermission(
            uri: payload["uri"] as? String ?? "",
            thirdPartyOrigin: thirdPartyOrigin,
            privateMode: payload["privateMode"] as? Bool ?? false,
            permission: permission,
            value: Value(rawValue: rawValue) ?? .prompt,
            rawValue: rawValue,
            contextId: payload["contextId"] as? String,
            principal: payload["principal"] as? String ?? "",
            rawPermission: permissionKey
        )
    }
    
    var geckoDictionary: [String: Any?] {
        return [
            "uri": uri,
            "thirdPartyOrigin": thirdPartyOrigin,
            "privateMode": privateMode,
            "perm": rawPermission,
            "value": rawValue,
            "contextId": contextId,
            "principal": principal,
        ]
    }
    
    public static func permissionHost(from uri: String?) -> String {
        guard let uri,
              let url = URL(string: uri),
              let host = url.host,
              !host.isEmpty else {
            return "This site"
        }
        
        return host
    }
}
