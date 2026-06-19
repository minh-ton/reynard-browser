//
//  ContentPermissionPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import Foundation

extension ContentPermission {
    var alertTitle: String? {
        let host = Self.permissionHost(from: uri)
        switch permission {
        case .geolocation:
            return "Allow \(host) to use your location?"
        case .desktopNotification:
            return "Allow \(host) to send notifications?"
        case .persistentStorage:
            return "Allow \(host) to store data in persistent storage?"
        case .mediaKeySystemAccess:
            return "Allow \(host) to play DRM-controlled content?"
        case .storageAccess:
            return "Allow \(Self.permissionHost(from: thirdPartyOrigin)) to use its cookies on \(host)?"
        case .localDeviceAccess:
            return "Allow \(host) to access other apps and services on this device?"
        case .localNetworkAccess:
            return "Allow \(host) to access apps and services on devices connected to your local network?"
        case .deviceSensors:
            return "Allow \(host) to use motion & orientation sensors?"
        case .camera,
                .microphone,
                .webxr,
                .autoplay,
                .tracking,
            nil:
            return nil
        }
    }
    
    var alertMessage: String? {
        switch permission {
        case .storageAccess:
            return "You may want to block access if it’s not clear why \(Self.permissionHost(from: thirdPartyOrigin)) needs this data."
        case .camera,
                .microphone,
                .geolocation,
                .desktopNotification,
                .persistentStorage,
                .webxr,
                .autoplay,
                .mediaKeySystemAccess,
                .tracking,
                .localDeviceAccess,
                .localNetworkAccess,
                .deviceSensors,
            nil:
            return nil
        }
    }
    
    static func mediaAlertTitle(uri: String, videoRequested: Bool, audioRequested: Bool) -> String {
        let host = permissionHost(from: uri)
        switch (videoRequested, audioRequested) {
        case (true, true):
            return "Allow \(host) to use your camera and microphone?"
        case (true, false):
            return "Allow \(host) to use your camera?"
        case (false, true):
            return "Allow \(host) to use your microphone?"
        case (false, false):
            return "Allow \(host) to use your camera and microphone?"
        }
    }
}
