//
//  PermissionCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import Foundation
import GeckoView

protocol PermissionPromptPresenting {
    @MainActor
    func request(
        title: String,
        message: String?,
        cancelTitle: String,
        for session: GeckoSession
    ) async -> Bool
}

final class PermissionCoordinator: NSObject, PermissionEmbedderDelegate {
    private let permissionStore: SitePermissionStore
    private let promptPresenter: PermissionPromptPresenting
    
    init(
        permissionStore: SitePermissionStore = .shared,
        promptPresenter: PermissionPromptPresenting
    ) {
        self.permissionStore = permissionStore
        self.promptPresenter = promptPresenter
    }
    
    // MARK: - Permission Restoration
    
    func restorePermissions(for session: GeckoSession, at urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString),
              let host = URLUtils.normalizedHost(url.host),
              let origin = URLUtils.httpOriginString(for: url) else {
            return
        }
        
        for permission in SitePermission.allCases {
            guard permission != .crossOriginStorageAccess else {
                continue
            }
            
            let action = permissionStore.resolvedAction(for: permission, host: host, session: session)
            guard action != .askToAllow else {
                continue
            }
            
            let key = SiteSettingsUtils.geckoKey(for: permission)
            if permission == .autoplay {
                PermissionDelegate.setPermission(
                    uri: origin,
                    permissionKey: key,
                    rawValue: action.autoplayValue,
                    privateMode: session.isPrivateMode
                )
            } else {
                PermissionDelegate.setPermission(
                    uri: origin,
                    permissionKey: key,
                    rawValue: action.contentPermissionValue.rawValue,
                    privateMode: session.isPrivateMode
                )
            }
        }
    }
    
    // MARK: - PermissionEmbedderDelegate
    
    @MainActor
    func permissionDelegate(decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
        if permission.permission == .deviceSensors,
           let title = permission.alertTitle {
            let allowed = await promptPresenter.request(
                title: title,
                message: permission.alertMessage,
                cancelTitle: "Don't Allow",
                for: session
            )
            return allowed ? .allow : .deny
        }
        
        guard let sitePermission = SitePermission(contentPermission: permission),
              let host = URLUtils.normalizedHost(fromRawURI: permission.uri) else {
            return .prompt
        }
        
        let action = permissionStore.resolvedAction(for: sitePermission, host: host, session: session)
        if sitePermission == .autoplay {
            applyPermission(action, to: sitePermission, permission: permission)
            return ContentPermission.Value(rawValue: action.autoplayValue) ?? .deny
        }
        
        guard let title = permission.alertTitle else {
            return .prompt
        }
        
        switch action {
        case .blocked,
                .allowed:
            applyPermission(action, to: sitePermission, permission: permission)
            return action.contentPermissionValue
        case .askToAllow:
            let allowed = await promptPresenter.request(
                title: title,
                message: permission.alertMessage,
                cancelTitle: "Don't Allow",
                for: session
            )
            let action: SitePermissionAction = allowed ? .allowed : .blocked
            permissionStore.scheduleActionUpdate(action, for: sitePermission, host: host, session: session)
            applyPermission(action, to: sitePermission, permission: permission)
            return action.contentPermissionValue
        }
    }
    
    @MainActor
    func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
        let requestedPermissions = requestedPermissions(for: request)
        guard !requestedPermissions.isEmpty else {
            return false
        }
        
        if requestedPermissions.contains(where: { permissionStore.resolvedAction(for: $0, host: request.host, session: session) == .blocked }) {
            return false
        }
        
        if requestedPermissions.allSatisfy({ permissionStore.resolvedAction(for: $0, host: request.host, session: session) == .allowed }) {
            return true
        }
        
        let allowed = await promptPresenter.request(
            title: ContentPermission.mediaAlertTitle(
                uri: request.uri,
                videoRequested: request.videoRequested,
                audioRequested: request.audioRequested
            ),
            message: nil,
            cancelTitle: "Cancel",
            for: session
        )
        let action: SitePermissionAction = allowed ? .allowed : .blocked
        for permission in requestedPermissions {
            permissionStore.scheduleActionUpdate(action, for: permission, host: request.host, session: session)
            applyPermission(action, to: permission, uri: request.uri, privateMode: session.isPrivateMode)
        }
        
        return allowed
    }
    
    // MARK: - Permission Resolution
    
    private func requestedPermissions(for request: MediaPermissionRequest) -> [SitePermission] {
        var permissions: [SitePermission] = []
        if request.videoRequested {
            permissions.append(.camera)
        }
        if request.audioRequested {
            permissions.append(.microphone)
        }
        return permissions
    }
    
    private func applyPermission(_ action: SitePermissionAction, to permission: SitePermission, uri: String, privateMode: Bool) {
        guard let url = URL(string: uri),
              let origin = URLUtils.httpOriginString(for: url) else {
            return
        }
        
        let key = SiteSettingsUtils.geckoKey(for: permission)
        if action == .askToAllow {
            PermissionDelegate.removePermission(
                uri: origin,
                permissionKey: key,
                privateMode: privateMode
            )
            return
        }
        
        PermissionDelegate.setPermission(
            uri: origin,
            permissionKey: key,
            rawValue: action.contentPermissionValue.rawValue,
            privateMode: privateMode
        )
    }
    
    private func applyPermission(_ action: SitePermissionAction, to sitePermission: SitePermission, permission: ContentPermission) {
        if sitePermission == .autoplay {
            PermissionDelegate.setPermission(
                permission,
                value: ContentPermission.Value(rawValue: action.autoplayValue) ?? .deny
            )
            return
        }
        
        PermissionDelegate.setPermission(
            permission,
            value: action.contentPermissionValue
        )
        
        guard sitePermission == .location else {
            return
        }
        
        applyPermission(
            action,
            to: sitePermission,
            uri: permission.uri,
            privateMode: permission.privateMode
        )
    }
}
