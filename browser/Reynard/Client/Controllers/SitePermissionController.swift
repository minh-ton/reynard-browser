//
//  SitePermissionController.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import GeckoView
import UIKit

final class SitePermissionController: NSObject, PermissionEmbedderDelegate {
    static let shared = SitePermissionController()
    
    private weak var controller: BrowserViewController?
    private let store: SitePermissionStore
    
    init(controller: BrowserViewController? = nil, store: SitePermissionStore = .shared) {
        self.controller = controller
        self.store = store
    }
    
    func attach(controller: BrowserViewController) {
        self.controller = controller
    }
    
    func start() {
        PermissionDelegate.shared.delegate = self
    }
    
    func applyPermissions(to session: GeckoSession, urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              let origin = originString(for: url) else {
            return
        }
        
        for permission in SitePermission.allCases {
            guard permission != .crossOriginStorageAccess else {
                continue
            }
            
            let action = store.action(for: permission, host: host, session: session)
            guard action != .askToAllow else {
                continue
            }
            
            let key = permission == .location ? "geo" : permission.rawValue
            if permission == .autoplay {
                PermissionDelegate.shared.setPermission(
                    uri: origin,
                    permissionKey: key,
                    rawValue: action.autoplayValue,
                    privateMode: session.isPrivateMode
                )
            } else {
                PermissionDelegate.shared.setPermission(
                    uri: origin,
                    permissionKey: key,
                    rawValue: action.contentPermissionValue.rawValue,
                    privateMode: session.isPrivateMode
                )
            }
        }
    }
    
    @MainActor
    func permissionDelegate(_ delegate: PermissionDelegate, decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
        guard let sitePermission = SitePermission(contentPermission: permission),
              let host = host(from: permission.uri) else {
            return .prompt
        }
        
        let storedAction = store.action(for: sitePermission, host: host, session: session)
        if sitePermission == .autoplay {
            setGeckoPermission(storedAction, for: sitePermission, contentPermission: permission)
            return ContentPermission.Value(rawValue: storedAction.autoplayValue) ?? .deny
        }
        
        guard let title = permission.alertTitle else {
            return .prompt
        }
        
        switch storedAction {
        case .blocked,
                .allowed:
            setGeckoPermission(storedAction, for: sitePermission, contentPermission: permission)
            return storedAction.contentPermissionValue
        case .askToAllow:
            let allowed = await presentPermissionAlert(
                title: title,
                message: permission.alertMessage,
                isMedia: false
            )
            let action: SitePermissionAction = allowed ? .allowed : .blocked
            store.setAction(action, for: sitePermission, host: host, session: session)
            setGeckoPermission(action, for: sitePermission, contentPermission: permission)
            return action.contentPermissionValue
        }
    }
    
    @MainActor
    func permissionDelegate(_ delegate: PermissionDelegate, decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
        let requestedPermissions = mediaPermissions(for: request)
        guard !requestedPermissions.isEmpty else {
            return false
        }
        
        if requestedPermissions.contains(where: { store.action(for: $0, host: request.host, session: session) == .blocked }) {
            return false
        }
        
        if requestedPermissions.allSatisfy({ store.action(for: $0, host: request.host, session: session) == .allowed }) {
            return true
        }
        
        let allowed = await presentPermissionAlert(
            title: request.title,
            message: nil,
            isMedia: true
        )
        let action: SitePermissionAction = allowed ? .allowed : .blocked
        for permission in requestedPermissions {
            store.setAction(action, for: permission, host: request.host, session: session)
            setGeckoPermission(action, for: permission, uri: request.uri, privateMode: session.isPrivateMode)
        }
        
        return allowed
    }
    
    @MainActor
    private func presentPermissionAlert(title: String, message: String?, isMedia: Bool) async -> Bool {
        guard let presenter = topPresentedViewController() ?? controller else {
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
            
            let cancelTitle = isMedia ? L("Cancel") : L("Don't Allow")
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: L("Allow"), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    private func mediaPermissions(for request: MediaPermissionRequest) -> [SitePermission] {
        var permissions: [SitePermission] = []
        if request.videoRequested {
            permissions.append(.camera)
        }
        if request.audioRequested {
            permissions.append(.microphone)
        }
        return permissions
    }
    
    private func setGeckoPermission(_ action: SitePermissionAction, for permission: SitePermission, uri: String, privateMode: Bool) {
        guard let url = URL(string: uri),
              let origin = originString(for: url) else {
            return
        }
        
        let key = permission == .location ? "geo" : permission.rawValue
        if action == .askToAllow {
            PermissionDelegate.shared.removePermission(
                uri: origin,
                permissionKey: key,
                privateMode: privateMode
            )
            return
        }
        
        PermissionDelegate.shared.setPermission(
            uri: origin,
            permissionKey: key,
            rawValue: action.contentPermissionValue.rawValue,
            privateMode: privateMode
        )
    }
    
    private func setGeckoPermission(_ action: SitePermissionAction, for sitePermission: SitePermission, contentPermission: ContentPermission) {
        if sitePermission == .autoplay {
            PermissionDelegate.shared.setPermission(
                contentPermission,
                value: ContentPermission.Value(rawValue: action.autoplayValue) ?? .deny
            )
            return
        }
        
        PermissionDelegate.shared.setPermission(
            contentPermission,
            value: action.contentPermissionValue
        )
        
        guard sitePermission == .location else {
            return
        }
        
        setGeckoPermission(
            action,
            for: sitePermission,
            uri: contentPermission.uri,
            privateMode: contentPermission.privateMode
        )
    }
    
    private func host(from rawURI: String?) -> String? {
        guard let rawURI,
              let url = URL(string: rawURI),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        
        return host
    }
    
    private func originString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
    
    private func topPresentedViewController() -> UIViewController? {
        guard let controller else {
            return nil
        }
        
        var current: UIViewController = controller
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
