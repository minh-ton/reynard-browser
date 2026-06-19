//
//  AddonCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import GeckoView
import UIKit

protocol AddonCoordinatorDataSource: AnyObject {
    var selectedAddonSession: GeckoSession? { get }
    var isSelectedAddonTabPrivate: Bool { get }
    var addonTabs: [Tab] { get }
    var selectedAddonTabMode: TabMode { get }
    
    func indexOfAddonTab(for session: GeckoSession) -> Int?
}

protocol AddonCoordinatorDelegate: AnyObject {
    func refreshAddonChrome(_ coordinator: AddonCoordinator)
    func performAfterAddonMenuDismissal(_ coordinator: AddonCoordinator, work: @escaping () -> Void)
    func presentAddonViewController(_ coordinator: AddonCoordinator, _ viewController: UIViewController)
    func presentAddonAlert(_ coordinator: AddonCoordinator, title: String?, message: String)
    func dismissAddonModal(_ coordinator: AddonCoordinator, completion: (() -> Void)?) -> Bool
    func createAddonTab(
        _ coordinator: AddonCoordinator,
        selecting: Bool,
        url: String?,
        windowId: String?,
        at index: Int?,
        loadImmediately: Bool
    ) -> Tab?
    func selectAddonTab(_ coordinator: AddonCoordinator, at index: Int, mode: TabMode?)
    func closeAddonTab(_ coordinator: AddonCoordinator, at index: Int, mode: TabMode?)
    func restoreAddonTabInteraction(_ coordinator: AddonCoordinator)
}

final class AddonCoordinator: NSObject, AddonEmbedderDelegate {
    private enum UX {
        static let menuIconSize: CGFloat = 18
    }
    
    private weak var dataSource: AddonCoordinatorDataSource?
    private weak var delegate: AddonCoordinatorDelegate?
    private let sessionManager: SessionManager
    private var browserActionsBySession: [ObjectIdentifier: [String: AddonAction]] = [:]
    private var pageActionsBySession: [ObjectIdentifier: [String: AddonAction]] = [:]
    private let iconCache = NSCache<NSString, UIImage>()
    private let iconLoadingQueue = DispatchQueue(label: "com.minh-ton.Reynard.AddonCoordinator.IconLoadingQueue", qos: .utility)
    private var loadingIconIDs = Set<String>()
    let updateCoordinator: AddonUpdateCoordinator
    
    init(
        dataSource: AddonCoordinatorDataSource,
        delegate: AddonCoordinatorDelegate,
        sessionManager: SessionManager
    ) {
        self.dataSource = dataSource
        self.delegate = delegate
        self.sessionManager = sessionManager
        updateCoordinator = AddonUpdateCoordinator()
        super.init()
        iconCache.countLimit = 64
    }
    
    // MARK: - Runtime Lifecycle
    
    func start() async {
        AddonRuntime.shared.delegate = self
        _ = try? await AddonRuntime.shared.list()
        updateCoordinator.start()
        delegate?.refreshAddonChrome(self)
    }
    
    func handleExternalResponse(_ response: ExternalResponseInfo) -> Bool {
        guard shouldInterceptAMOInstall(response) else {
            return false
        }
        
        Task { @MainActor [weak self] in
            do {
                _ = try await AddonRuntime.shared.install(url: response.url, installMethod: .manager)
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
    
    func handleTabSelectionChange(selectedIndex: Int, previousIndex: Int?) {
        let activeTabs = dataSource?.addonTabs ?? []
        if let previousIndex,
           activeTabs.indices.contains(previousIndex) {
            activeTabs[previousIndex].session.setAddonTabActive(false)
        }
        
        if activeTabs.indices.contains(selectedIndex) {
            activeTabs[selectedIndex].session.setAddonTabActive(true)
        }
    }
    
    private var menuAddons: [Addon] {
        guard dataSource?.isSelectedAddonTabPrivate == true else {
            return AddonRuntime.shared.installedAddons
        }
        
        return AddonRuntime.shared.installedAddons.filter { $0.metaData.allowedInPrivateBrowsing }
    }
    
    // MARK: - Menu Actions
    
    func currentSiteMenuItems() -> [AddonMenuItem] {
        guard let session = dataSource?.selectedAddonSession else {
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
        
        if session === dataSource?.selectedAddonSession {
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
        
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(
                selecting: true,
                url: value,
                loadImmediately: true
            )
        }
        
        if delegate?.dismissAddonModal(self, completion: createTab) == true {
            return
        }
        
        createTab()
    }
    
    func addonController(_ controller: AddonRuntime, createNewTabFor addon: Addon, details: AddonCreateTabDetails, newSessionID: String) -> Bool {
        _ = addon
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(
                selecting: details.active ?? true,
                url: details.url,
                windowId: newSessionID,
                at: details.index
            )
        }
        
        if delegate?.dismissAddonModal(self, completion: createTab) != true {
            createTab()
        }
        return true
    }
    
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny {
        _ = addon
        guard let dataSource,
              let index = dataSource.indexOfAddonTab(for: session) else {
            return .deny
        }
        
        if details.active == true {
            delegate?.selectAddonTab(self, at: index, mode: dataSource.selectedAddonTabMode)
        }
        
        return .allow
    }
    
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny {
        _ = addon
        guard let dataSource,
              let index = dataSource.indexOfAddonTab(for: session) else {
            return .deny
        }
        
        delegate?.closeAddonTab(self, at: index, mode: dataSource.selectedAddonTabMode)
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
            }
        )
        
        // Hack: Use .overFullScreen so GeckoView can scroll
        popupViewController.modalPresentationStyle = .overFullScreen
        popupViewController.isModalInPresentation = true
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
    ) -> Tab? {
        let tab = delegate?.createAddonTab(
            self,
            selecting: selecting,
            url: url,
            windowId: windowId,
            at: index,
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
        let session = createAddonTab(selecting: true, url: url, windowId: windowId)?.session
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
                if let image {
                    self.iconCache.setObject(image, forKey: cacheKey)
                }
                self.delegate?.refreshAddonChrome(self)
            }
        }
    }
    
    func prepareMenuIcons() {
        guard let session = dataSource?.selectedAddonSession else {
            return
        }
        
        menuAddons
            .filter { addon in
                visibleActions(for: addon, session: session).isEmpty == false
            }
            .forEach { prefetchIconIfNeeded(for: $0) }
    }
}
