//
//  PermissionDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import Foundation

// MARK: - Permission Models

public struct MediaPermissionRequest {
    public let uri: String
    public let host: String
    public let videoRequested: Bool
    public let audioRequested: Bool
}

// MARK: - Permission Delegate

public protocol PermissionEmbedderDelegate: AnyObject {
    @MainActor
    func permissionDelegate(decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value
    @MainActor
    func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool
}

public extension PermissionEmbedderDelegate {
    @MainActor
    func permissionDelegate(decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
        .prompt
    }
    
    @MainActor
    func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
        false
    }
}

// MARK: - Permission Events

private enum PermissionEvents: String, CaseIterable {
    case contentPermission = "GeckoView:ContentPermission"
    case mediaPermission = "GeckoView:MediaPermission"
}

// MARK: - Permission Commands

public enum PermissionDelegate {
    public static func permissions(for uri: String, privateMode: Bool = false, contextId: String? = nil) async throws -> [ContentPermission] {
        let response = try await GeckoEventDispatcherWrapper.runtimeInstance.query(
            type: "GeckoView:GetPermissionsByURI",
            message: [
                "uri": uri,
                "contextId": contextId,
                "privateBrowsingId": privateMode ? 1 : 0,
            ]
        )
        
        guard let dictionary = response as? [String: Any],
              let permissions = dictionary["permissions"] as? [[String: Any]] else {
            return []
        }
        
        return permissions.map { permission in
            ContentPermission.fromDictionary(permission.mapValues { Optional($0) })
        }
    }
    
    public static func setPermission(_ permission: ContentPermission, value: ContentPermission.Value, allowPermanentPrivateBrowsing: Bool = false) {
        var message = permission.geckoDictionary
        message["newValue"] = value.rawValue
        message["allowPermanentPrivateBrowsing"] = allowPermanentPrivateBrowsing
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(type: "GeckoView:SetPermission", message: message)
    }
    
    public static func setPermission(uri: String, permissionKey: String, rawValue: Int32, privateMode: Bool = false, contextId: String? = nil) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:SetPermissionByURI",
            message: [
                "uri": uri,
                "perm": permissionKey,
                "newValue": rawValue,
                "privateId": privateMode ? 1 : 0,
                "contextId": contextId,
            ]
        )
    }
    
    public static func removePermission(uri: String, permissionKey: String, privateMode: Bool = false, contextId: String? = nil) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:RemovePermissionByURI",
            message: [
                "uri": uri,
                "perm": permissionKey,
                "privateId": privateMode ? 1 : 0,
                "contextId": contextId,
            ]
        )
    }
    
    public static func removePermission(_ permission: ContentPermission) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:RemovePermission",
            message: permission.geckoDictionary
        )
    }
    
    @MainActor
    static func handleMediaPermission(message: [String: Any?]?, session: GeckoSession, delegate: PermissionEmbedderDelegate?) async -> Any {
        let videoSources = message?["video"] as? [[String: Any?]]
        let audioSources = message?["audio"] as? [[String: Any?]]
        let videoRequested = videoSources != nil
        let audioRequested = audioSources != nil
        
        guard videoSources != nil || audioSources != nil,
              videoSources?.first != nil || videoSources == nil,
              audioSources?.first != nil || audioSources == nil else {
            return false
        }
        
        let uri = message?["uri"] as? String ?? ""
        let request = MediaPermissionRequest(
            uri: uri,
            host: ContentPermission.permissionHost(from: uri),
            videoRequested: videoRequested,
            audioRequested: audioRequested
        )
        
        guard await delegate?.permissionDelegate(decideMediaPermission: request, session: session) == true else {
            return false
        }
        
        let selectedVideoID = (videoSources?.first?["rawId"] as? String) ?? (videoSources?.first?["id"] as? String)
        let selectedAudioID = (audioSources?.first?["rawId"] as? String) ?? (audioSources?.first?["id"] as? String)
        return [
            "video": selectedVideoID as Any? ?? NSNull(),
            "audio": selectedAudioID as Any? ?? NSNull(),
        ]
    }
}

// MARK: - Permission Handler

func newPermissionHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewPermission",
        events: PermissionEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = PermissionEvents(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        switch event {
        case .contentPermission:
            let permission = ContentPermission.fromDictionary(message ?? [:])
            let delegate = delegate as? PermissionEmbedderDelegate
            return await delegate?.permissionDelegate(decideContentPermission: permission, session: session).rawValue ?? ContentPermission.Value.prompt.rawValue
            
        case .mediaPermission:
            return await PermissionDelegate.handleMediaPermission(
                message: message,
                session: session,
                delegate: delegate as? PermissionEmbedderDelegate
            )
        }
    }
}
