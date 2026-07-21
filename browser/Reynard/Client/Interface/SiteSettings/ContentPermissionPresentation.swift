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
            return String(format: NSLocalizedString("Allow %@ to use your location?", comment: "Website host"), host)
        case .desktopNotification:
            return String(format: NSLocalizedString("Allow %@ to send notifications?", comment: "Website host"), host)
        case .persistentStorage:
            return String(format: NSLocalizedString("Allow %@ to store data in persistent storage?", comment: "Website host"), host)
        case .mediaKeySystemAccess:
            return String(format: NSLocalizedString("Allow %@ to play DRM-controlled content?", comment: "Website host"), host)
        case .storageAccess:
            return String(format: NSLocalizedString("Allow %@ to use its cookies on %@?", comment: "Third-party and site hosts"), Self.permissionHost(from: thirdPartyOrigin), host)
        case .localDeviceAccess:
            return String(format: NSLocalizedString("Allow %@ to access other apps and services on this device?", comment: "Website host"), host)
        case .localNetworkAccess:
            return String(format: NSLocalizedString("Allow %@ to access apps and services on devices connected to your local network?", comment: "Website host"), host)
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
            return String(format: NSLocalizedString("You may want to block access if it’s not clear why %@ needs this data.", comment: "Third-party host"), Self.permissionHost(from: thirdPartyOrigin))
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
            nil:
            return nil
        }
    }
    
    static func mediaAlertTitle(uri: String, videoRequested: Bool, audioRequested: Bool) -> String {
        let host = permissionHost(from: uri)
        switch (videoRequested, audioRequested) {
        case (true, true):
            return String(format: NSLocalizedString("Allow %@ to use your camera and microphone?", comment: "Website host"), host)
        case (true, false):
            return String(format: NSLocalizedString("Allow %@ to use your camera?", comment: "Website host"), host)
        case (false, true):
            return String(format: NSLocalizedString("Allow %@ to use your microphone?", comment: "Website host"), host)
        case (false, false):
            return String(format: NSLocalizedString("Allow %@ to use your camera and microphone?", comment: "Website host"), host)
        }
    }
}
