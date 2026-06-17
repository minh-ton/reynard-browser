//
//  EnginePermissionCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import GeckoView
import UIKit

final class EnginePermissionCoordinator: NSObject, PermissionEmbedderDelegate {
    func applyStoredPermissions(to session: GeckoSession, urlString: String?) {
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
            
            let action = SitePermissionStore.shared.action(for: permission, host: host, session: session)
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
    
    @MainActor
    func permissionDelegate(decideContentPermission contentPermission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
        if contentPermission.permission == .deviceSensors,
           let title = contentPermission.alertTitle {
            let allowed = await presentPermissionPrompt(
                title: title,
                message: contentPermission.alertMessage,
                isMedia: false,
                session: session
            )
            return allowed ? .allow : .deny
        }
        
        guard let sitePermission = SitePermission(contentPermission: contentPermission),
              let host = URLUtils.normalizedHost(fromRawURI: contentPermission.uri) else {
            return .prompt
        }
        
        let savedAction = SitePermissionStore.shared.action(for: sitePermission, host: host, session: session)
        if sitePermission == .autoplay {
            applyGeckoPermission(savedAction, for: sitePermission, contentPermission: contentPermission)
            return ContentPermission.Value(rawValue: savedAction.autoplayValue) ?? .deny
        }
        
        guard let title = contentPermission.alertTitle else {
            return .prompt
        }
        
        switch savedAction {
        case .blocked,
                .allowed:
            applyGeckoPermission(savedAction, for: sitePermission, contentPermission: contentPermission)
            return savedAction.contentPermissionValue
        case .askToAllow:
            let allowed = await presentPermissionPrompt(
                title: title,
                message: contentPermission.alertMessage,
                isMedia: false,
                session: session
            )
            let action: SitePermissionAction = allowed ? .allowed : .blocked
            SitePermissionStore.shared.setAction(action, for: sitePermission, host: host, session: session)
            applyGeckoPermission(action, for: sitePermission, contentPermission: contentPermission)
            return action.contentPermissionValue
        }
    }
    
    @MainActor
    func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
        let permissions = sitePermissions(for: request)
        guard !permissions.isEmpty else {
            return false
        }
        
        if permissions.contains(where: { SitePermissionStore.shared.action(for: $0, host: request.host, session: session) == .blocked }) {
            return false
        }
        
        if permissions.allSatisfy({ SitePermissionStore.shared.action(for: $0, host: request.host, session: session) == .allowed }) {
            return true
        }
        
        let allowed = await presentPermissionPrompt(
            title: ContentPermission.mediaAlertTitle(
                uri: request.uri,
                videoRequested: request.videoRequested,
                audioRequested: request.audioRequested
            ),
            message: nil,
            isMedia: true,
            session: session
        )
        let action: SitePermissionAction = allowed ? .allowed : .blocked
        for permission in permissions {
            SitePermissionStore.shared.setAction(action, for: permission, host: request.host, session: session)
            applyGeckoPermission(action, for: permission, uri: request.uri, privateMode: session.isPrivateMode)
        }
        
        return allowed
    }
    
    @MainActor
    private func presentPermissionPrompt(title: String, message: String?, isMedia: Bool, session: GeckoSession) async -> Bool {
        guard let presenter = session.engineView?.nearestViewController()?.topPresentedController() else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            let attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.boldSystemFont(ofSize: 17)
                ]
            )
            alert.setValue(attributedTitle, forKey: "attributedTitle")
            
            let cancelTitle = isMedia ? "Cancel" : "Don't Allow"
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    private func sitePermissions(for request: MediaPermissionRequest) -> [SitePermission] {
        var permissions: [SitePermission] = []
        if request.videoRequested {
            permissions.append(.camera)
        }
        if request.audioRequested {
            permissions.append(.microphone)
        }
        return permissions
    }
    
    private func applyGeckoPermission(_ action: SitePermissionAction, for permission: SitePermission, uri: String, privateMode: Bool) {
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
    
    private func applyGeckoPermission(_ action: SitePermissionAction, for sitePermission: SitePermission, contentPermission: ContentPermission) {
        if sitePermission == .autoplay {
            PermissionDelegate.setPermission(
                contentPermission,
                value: ContentPermission.Value(rawValue: action.autoplayValue) ?? .deny
            )
            return
        }
        
        PermissionDelegate.setPermission(
            contentPermission,
            value: action.contentPermissionValue
        )
        
        guard sitePermission == .location else {
            return
        }
        
        applyGeckoPermission(
            action,
            for: sitePermission,
            uri: contentPermission.uri,
            privateMode: contentPermission.privateMode
        )
    }
}
