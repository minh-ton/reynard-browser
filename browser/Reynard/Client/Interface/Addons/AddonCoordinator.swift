//
//  AddonCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import GeckoView
import UIKit

protocol AddonCoordinatorDelegate: AnyObject {
    var shouldPresentAddonPopupAsPopover: Bool { get }
    
    func refreshAddonChrome(_ coordinator: AddonCoordinator)
    func performAfterAddonMenuDismissal(_ coordinator: AddonCoordinator, work: @escaping () -> Void)
    func presentAddonViewController(_ coordinator: AddonCoordinator, _ viewController: UIViewController)
    func presentAddonAlert(_ coordinator: AddonCoordinator, title: String?, message: String)
    func dismissAddonModal(_ coordinator: AddonCoordinator, completion: (() -> Void)?) -> Bool
    @MainActor
    func confirmAddonDownload(_ coordinator: AddonCoordinator, options: [String: Any?]) async -> DownloadStore.WebExtensionDownloadItem?
    func restoreAddonTabInteraction(_ coordinator: AddonCoordinator)
}

final class AddonCoordinator: NSObject, AddonEmbedderDelegate {
    private enum UX {
        static let menuIconSize: CGFloat = 18
    }
    
    private weak var delegate: AddonCoordinatorDelegate?
    private let sessionManager: SessionManager
    private unowned let tabManager: TabManager
    private var browserActionsBySession: [ObjectIdentifier: [String: AddonAction]] = [:]
    private var pageActionsBySession: [ObjectIdentifier: [String: AddonAction]] = [:]
    private let iconCache = NSCache<NSString, UIImage>()
    private let iconLoadingQueue = DispatchQueue(label: "com.minh-ton.Reynard.AddonCoordinator.IconLoadingQueue", qos: .utility)
    private var loadingIconIDs = Set<String>()
    private var pendingAddonDownloadPaths = Set<String>()
    private var pendingWebExtensionDownloadsByPath: [String: DownloadStore.WebExtensionDownloadItem] = [:]
    private let updateCoordinator = AddonUpdateCoordinator.shared
    
    init(
        delegate: AddonCoordinatorDelegate,
        sessionManager: SessionManager,
        tabManager: TabManager
    ) {
        self.delegate = delegate
        self.sessionManager = sessionManager
        self.tabManager = tabManager
        super.init()
        iconCache.countLimit = 64
    }
    
    // MARK: - Runtime Lifecycle
    
    func start() async {
        AddonEventRouter.shared.start()
        _ = try? await AddonRuntime.shared.list()
        updateCoordinator.start()
        delegate?.refreshAddonChrome(self)
    }
    
    func handleExternalResponse(_ response: ExternalResponseInfo) -> Bool {
        guard shouldInterceptAMOInstall(response) else {
            return false
        }
        
        pendingAddonDownloadPaths.insert(response.localFilePath)
        return true
    }
    
    func shouldContinueExternalResponse(localFilePath: String) -> Bool {
        return pendingAddonDownloadPaths.contains(localFilePath)
    }
    
    func completeExternalResponse(localFilePath: String, succeeded: Bool) -> Bool {
        guard pendingAddonDownloadPaths.remove(localFilePath) != nil else {
            return false
        }
        
        let packageFileURL = URL(fileURLWithPath: localFilePath)
        guard succeeded else {
            try? FileManager.default.removeItem(at: packageFileURL)
            return true
        }
        
        Task { @MainActor [weak self] in
            defer {
                try? FileManager.default.removeItem(at: packageFileURL)
            }
            
            do {
                _ = try await AddonRuntime.shared.install(
                    url: packageFileURL.absoluteString,
                    installMethod: .manager
                )
            } catch {
                guard let self else {
                    return
                }
                let presentation = AddonErrorPresenter.installErrorPresentation(
                    for: error,
                    addonName: nil
                )
                if !presentation.isUserCancelled {
                    self.delegate?.presentAddonAlert(self, title: nil, message: presentation.alertMessage)
                }
            }
        }
        return true
    }
    
    // MARK: - Tab State
    
    func handleTabSelectionChange(from previousTab: Tab?, to tab: Tab) {
        previousTab?.session.setAddonTabActive(false)
        tab.session.setAddonTabActive(true)
    }
    
    func handleSelectedTabSessionReplacement(from previousSession: GeckoSession, to replacementSession: GeckoSession) {
        previousSession.setAddonTabActive(false)
        replacementSession.setAddonTabActive(true)
    }
    
    private var menuAddons: [Addon] {
        let installedAddons = AddonRuntime.shared.installedAddons.filter { !$0.isBuiltIn }
        guard tabManager.selectedTab?.isPrivate == true else {
            return installedAddons
        }
        
        return installedAddons.filter { $0.metaData.allowedInPrivateBrowsing }
    }
    
    // MARK: - Menu Actions
    
    func currentSiteMenuItems() -> [AddonMenuItem] {
        guard let session = tabManager.selectedTab?.session else {
            return []
        }
        
        return menuAddons.flatMap { addon in
            visibleActions(for: addon, session: session).map { action in
                AddonMenuItem(
                    addon: addon,
                    action: action,
                    title: action.title ?? addon.metaData.name ?? addon.id
                )
            }
        }
    }
    
    func visibleActions(for addon: Addon, session: GeckoSession) -> [AddonAction] {
        guard addon.metaData.enabled else {
            return []
        }
        
        var actions: [AddonAction] = []
        
        if let action = mergedBrowserAction(for: addon, session: session),
           action.enabled != false {
            actions.append(action)
        }
        
        if let action = mergedPageAction(for: addon, session: session),
           action.enabled == true {
            actions.append(action)
        }
        
        return actions
    }
    
    func activateMenuItem(_ item: AddonMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            do {
                if let url = try await AddonRuntime.shared.clickAction(kind: item.action.kind, addon: item.addon),
                   !url.isEmpty {
                    self.presentPopupAfterMenuDismissal(url: url)
                }
            } catch {
                self.delegate?.presentAddonAlert(self, title: nil, message: "\(error)")
            }
        }
    }
    
    // MARK: - AddonEmbedderDelegate
    
    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon) {
        _ = addon
        if addon.metaData.enabled == false || AddonRuntime.shared.installedAddons.contains(where: { $0.id == addon.id }) == false {
            clearCachedActions(for: addon.id)
        }
        delegate?.refreshAddonChrome(self)
    }
    
    func addonController(_ controller: AddonRuntime, didFailInstall failure: AddonInstallFailure) {
        _ = controller
        _ = failure
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, promptFor prompt: AddonPermissionPrompt) async -> AddonPermissionPromptResponse {
        if let response = AddonImporter.installationResponse(for: prompt) {
            return response
        }
        
        let presentPrompt: @MainActor (AddonPermissionPrompt) async -> AddonPermissionPromptResponse = { prompt in
            await withCheckedContinuation { continuation in
                guard let delegate = self.delegate else {
                    continuation.resume(returning: .deny)
                    return
                }
                
                let promptViewController = AddonPermissionPromptViewController(prompt: prompt) { response in
                    continuation.resume(returning: response)
                }
                
                let navigationController = UINavigationController(rootViewController: promptViewController)
                navigationController.modalPresentationStyle = .pageSheet
                delegate.presentAddonViewController(self, navigationController)
            }
        }
        
        if prompt.kind == .update {
            return await updateCoordinator.responseForUpdatePrompt(prompt, presentPrompt: presentPrompt)
        }
        
        return await presentPrompt(prompt)
    }
    
    func addonController(_ controller: AddonRuntime, didUpdate action: AddonAction, for addon: Addon, session: GeckoSession?) {
        guard let session else {
            return
        }
        
        let key = ObjectIdentifier(session)
        switch action.kind {
        case .browser:
            var actions = browserActionsBySession[key] ?? [:]
            actions[addon.id] = action
            browserActionsBySession[key] = actions
        case .page:
            var actions = pageActionsBySession[key] ?? [:]
            actions[addon.id] = action
            pageActionsBySession[key] = actions
        }
        
        if session === tabManager.selectedTab?.session {
            delegate?.refreshAddonChrome(self)
        }
    }
    
    func addonController(_ controller: AddonRuntime, didRequestOpenPopup url: String, for addon: Addon, action: AddonAction, session: GeckoSession?) {
        Task { @MainActor [weak self] in
            self?.presentPopupAfterMenuDismissal(
                url: url
            )
        }
    }
    
    func addonController(_ controller: AddonRuntime, didRequestOpenOptionsPageFor addon: Addon) {
        _ = controller
        guard let value = addon.metaData.optionsPageURL,
              URL(string: value) != nil else {
            return
        }
        
        let isImportingAddon = AddonImporter.importingAddonIDs.contains(addon.id)
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(
                selecting: true,
                url: value,
                loadImmediately: true
            )
        }
        
        if !isImportingAddon, delegate?.dismissAddonModal(self, completion: createTab) == true {
            return
        }
        
        createTab()
    }
    
    // MARK: - WebExtension Downloads
    
    @MainActor
    func addonController(_ controller: AddonRuntime, didRequestDownload options: [String: Any?], for addon: Addon) async -> [String: Any]? {
        _ = controller
        _ = addon
        guard let downloadItem = await delegate?.confirmAddonDownload(
            self,
            options: options
        ) else {
            return nil
        }
        
        pendingWebExtensionDownloadsByPath[downloadItem.localFilePath] = downloadItem
        
        let startTime = ISO8601DateFormatter().string(from: downloadItem.addedAt)
        return [
            "id": downloadItem.id,
            "filename": downloadItem.fileName,
            "mime": downloadItem.mimeType ?? "",
            "startTime": startTime,
            "state": 0,
            "paused": false,
            "canResume": false,
            "bytesReceived": 0,
            "totalBytes": -1,
            "fileSize": -1,
            "exists": false,
            "localFilePath": downloadItem.localFilePath,
        ]
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, didCompleteDownloadAt localFilePath: String, succeeded: Bool) {
        _ = controller
        guard let downloadItem = pendingWebExtensionDownloadsByPath.removeValue(forKey: localFilePath) else {
            return
        }
        
        let fileSize: Int64
        if succeeded,
           let attributes = try? FileManager.default.attributesOfItem(atPath: localFilePath),
           let size = attributes[.size] as? NSNumber {
            fileSize = size.int64Value
        } else {
            fileSize = 0
        }
        
        DownloadStore.shared.completeCapturedDownload(
            localFilePath: localFilePath,
            succeeded: succeeded
        )
        
        GeckoRuntime.dispatchEvent(
            type: "GeckoView:WebExtension:DownloadChanged",
            message: [
                "downloadItemId": downloadItem.id,
                "state": succeeded ? 2 : 1,
                "error": succeeded ? 0 : 11,
                "endTime": ISO8601DateFormatter().string(from: Date()),
                "bytesReceived": fileSize,
                "totalBytes": fileSize,
                "fileSize": fileSize,
                "exists": succeeded,
            ]
        )
    }
    
    func addonController(_ controller: AddonRuntime, createNewTabFor addon: Addon, details: AddonCreateTabDetails, newSessionID: String) -> Bool {
        let isImportingAddon = AddonImporter.importingAddonIDs.contains(addon.id)
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(
                selecting: details.active ?? true,
                url: details.url,
                windowId: newSessionID,
                at: details.index
            )
        }
        
        if isImportingAddon || delegate?.dismissAddonModal(self, completion: createTab) != true {
            createTab()
        }
        return true
    }
    
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny {
        _ = addon
        guard let tab = tabManager.activeTabs.first(where: { $0.session === session }) else {
            return .deny
        }
        
        if details.active == true {
            tabManager.selectTab(tab)
        }
        
        return .allow
    }
    
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny {
        _ = addon
        guard let tab = tabManager.activeTabs.first(where: { $0.session === session }) else {
            return .deny
        }
        
        tabManager.removeTab(tab, behavior: .recent)
        return .allow
    }
    
    // MARK: - Action State
    
    private func clearCachedActions(for addonID: String) {
        browserActionsBySession = browserActionsBySession.reduce(into: [:]) { result, entry in
            var actions = entry.value
            actions.removeValue(forKey: addonID)
            if !actions.isEmpty {
                result[entry.key] = actions
            }
        }
        
        pageActionsBySession = pageActionsBySession.reduce(into: [:]) { result, entry in
            var actions = entry.value
            actions.removeValue(forKey: addonID)
            if !actions.isEmpty {
                result[entry.key] = actions
            }
        }
    }
    
    private func mergedBrowserAction(for addon: Addon, session: GeckoSession) -> AddonAction? {
        let key = ObjectIdentifier(session)
        if let override = browserActionsBySession[key]?[addon.id],
           let defaultAction = addon.browserAction {
            return override.merged(with: defaultAction)
        }
        return browserActionsBySession[key]?[addon.id] ?? addon.browserAction
    }
    
    private func mergedPageAction(for addon: Addon, session: GeckoSession) -> AddonAction? {
        let key = ObjectIdentifier(session)
        if let override = pageActionsBySession[key]?[addon.id],
           let defaultAction = addon.pageAction {
            return override.merged(with: defaultAction)
        }
        return pageActionsBySession[key]?[addon.id] ?? addon.pageAction
    }
    
    private func shouldInterceptAMOInstall(_ response: ExternalResponseInfo) -> Bool {
        guard let url = URL(string: response.url),
              url.host?.lowercased() == "addons.mozilla.org" else {
            return false
        }
        
        let path = url.path.lowercased()
        return path.contains("/firefox/downloads/file/") && path.hasSuffix(".xpi")
    }
    
    // MARK: - Presentation
    
    @MainActor
    private func presentPopupAfterMenuDismissal(url: String) {
        delegate?.performAfterAddonMenuDismissal(self, work: { [weak self] in
            self?.presentPopup(url: url)
        })
    }
    
    private func presentPopup(url: String) {
        let isPopover = delegate?.shouldPresentAddonPopupAsPopover == true
        let popupViewController = AddonPopupViewController(
            url: url,
            sessionManager: sessionManager,
            openInNewTab: { [weak self] url in
                self?.openPopupURLInTab(url)
            },
            createSession: { [weak self] url, windowId in
                self?.createPopupTabSession(url: url, windowId: windowId)
            },
            didDismiss: { [weak self] in
                guard let self else {
                    return
                }
                self.delegate?.restoreAddonTabInteraction(self)
            },
            presentation: isPopover ? .popover : .sheet
        )
        if !isPopover {
            if #unavailable(iOS 26.0) {
                // Hack: Use .overFullScreen so GeckoView can scroll
                popupViewController.modalPresentationStyle = .overFullScreen
            }
            popupViewController.isModalInPresentation = true
        }
        delegate?.presentAddonViewController(self, popupViewController)
    }
    
    // MARK: - Tab Actions
    
    @discardableResult
    private func createAddonTab(
        selecting: Bool,
        url: String?,
        windowId: String? = nil,
        at index: Int? = nil,
        loadImmediately: Bool = false
    ) -> Tab {
        let tab = tabManager.createTab(
            selecting: selecting,
            windowId: windowId,
            target: index.map(TabInsertionTarget.index) ?? .end,
            mode: .regular,
            url: url,
            loadImmediately: loadImmediately
        )
        delegate?.refreshAddonChrome(self)
        return tab
    }
    
    private func openPopupURLInTab(_ url: String) {
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(selecting: true, url: url, loadImmediately: true)
        }
        
        if delegate?.dismissAddonModal(self, completion: createTab) != true {
            createTab()
        }
    }
    
    private func createPopupTabSession(url: String, windowId: String) -> GeckoSession? {
        let session = createAddonTab(selecting: true, url: url, windowId: windowId).session
        _ = delegate?.dismissAddonModal(self, completion: nil)
        return session
    }
    
    // MARK: - Icons
    
    func menuIcon(for addon: Addon) -> UIImage? {
        let cacheKey = addon.id as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }
        return UIImage(named: "reynard.puzzlepiece.extension")
    }
    
    private func prefetchIconIfNeeded(for addon: Addon) {
        let cacheKey = addon.id as NSString
        guard iconCache.object(forKey: cacheKey) == nil,
              loadingIconIDs.contains(addon.id) == false,
              addon.metaData.iconURL != nil else {
            return
        }
        
        loadingIconIDs.insert(addon.id)
        let iconURL = addon.metaData.iconURL
        iconLoadingQueue.async { [weak self] in
            guard let self else {
                return
            }
            let image = AddonIconLoader.loadImage(
                from: iconURL,
                targetSize: CGSize(width: UX.menuIconSize, height: UX.menuIconSize)
            )
            DispatchQueue.main.async {
                self.loadingIconIDs.remove(addon.id)
                guard let image else {
                    return
                }
                self.iconCache.setObject(image, forKey: cacheKey)
                self.delegate?.refreshAddonChrome(self)
            }
        }
    }
    
    func prepareMenuIcons() {
        guard let session = tabManager.selectedTab?.session else {
            return
        }
        
        menuAddons
            .filter { addon in
                visibleActions(for: addon, session: session).isEmpty == false
            }
            .forEach { prefetchIconIfNeeded(for: $0) }
    }
}
