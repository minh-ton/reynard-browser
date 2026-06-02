//
//  AddonController.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import GeckoView
import UIKit
import zlib

struct AddonMenuItem {
    let addon: Addon
    let action: AddonAction
    let title: String
}

final class AddonController: NSObject, AddonEmbedderDelegate {
    private weak var controller: BrowserViewController?
    private var sessionBrowserActions: [ObjectIdentifier: [String: AddonAction]] = [:]
    private var sessionPageActions: [ObjectIdentifier: [String: AddonAction]] = [:]
    private let iconCache = NSCache<NSString, UIImage>()
    private let iconLoadingQueue = DispatchQueue(label: "com.minh-ton.addons-controller-icon-queue", qos: .utility)
    private var iconPrefetchIDs = Set<String>()
    let updateController: AddonUpdateController
    
    init(controller: BrowserViewController) {
        self.controller = controller
        updateController = AddonUpdateController()
        iconCache.countLimit = 64
    }
    
    func start() async {
        AddonRuntime.shared.delegate = self
        _ = try? await AddonRuntime.shared.list()
        updateController.start()
        controller?.refreshAddressBar()
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
                let presentation = AddonErrors.installErrPresentation(
                    for: error,
                    addonName: nil
                )
                if !presentation.isUserCancelled {
                    self.presentAlert(title: nil, message: presentation.alertMessage)
                }
            }
        }
        return true
    }
    
    func handleTabSelectionChange(selectedIndex: Int, previousIndex: Int?) {
        guard let controller else {
            return
        }
        
        if let previousIndex,
           (controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs).indices.contains(previousIndex) {
            (controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs)[previousIndex].session.setAddonTabActive(false)
        }
        
        let activeTabs = controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        if activeTabs.indices.contains(selectedIndex) {
            activeTabs[selectedIndex].session.setAddonTabActive(true)
        }
    }
    
    private var addonsInMenu: [Addon] {
        guard controller?.tabManager.selectedTab?.isPrivate == true else {
            return AddonRuntime.shared.installedAddons
        }
        
        return AddonRuntime.shared.installedAddons.filter { $0.metaData.allowedInPrivateBrowsing }
    }
    
    func visibleMenuItemsForCurrentSite() -> [AddonMenuItem] {
        guard let session = currentSession() else {
            return []
        }
        
        return addonsInMenu
            .filter { addon in
                visibleActions(for: addon, session: session).isEmpty == false
            }
            .flatMap { addon in
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
    
    func presentCurrentSiteSettings(for item: AddonMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            do {
                if let popupURL = try await AddonRuntime.shared.clickAction(kind: item.action.kind, addon: item.addon),
                   !popupURL.isEmpty {
                    self.presentPopupAfterMenuDismissal(url: popupURL, title: item.title)
                }
            } catch {
                self.presentAlert(title: nil, message: "\(error)")
            }
        }
    }
    
    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon) {
        _ = addon
        if addon.metaData.enabled == false || AddonRuntime.shared.installedAddons.contains(where: { $0.id == addon.id }) == false {
            clearCachedActions(for: addon.id)
        }
        self.controller?.refreshAddressBar()
    }
    
    func addonController(_ controller: AddonRuntime, didFailInstall failure: AddonInstallFailure) {
        _ = controller
        _ = failure
    }
    
    @MainActor
    func addonController(_ controller: AddonRuntime, promptFor prompt: AddonPermissionPrompt) async -> AddonPermissionPromptResponse {
        let presentPrompt: @MainActor (AddonPermissionPrompt) async -> AddonPermissionPromptResponse = { prompt in
            await withCheckedContinuation { continuation in
                let promptViewController = AddonPromptViewController(prompt: prompt) { response in
                    continuation.resume(returning: response)
                }
                
                let navigationController = UINavigationController(rootViewController: promptViewController)
                navigationController.modalPresentationStyle = .pageSheet
                
                guard let presenter = self.topPresentedViewController() ?? self.controller else {
                    continuation.resume(returning: .deny)
                    return
                }
                
                presenter.present(navigationController, animated: true)
            }
        }
        
        if prompt.kind == .update {
            return await updateController.responseForUpdatePrompt(prompt, presentPrompt: presentPrompt)
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
            var actions = sessionBrowserActions[key] ?? [:]
            actions[addon.id] = action
            sessionBrowserActions[key] = actions
        case .page:
            var actions = sessionPageActions[key] ?? [:]
            actions[addon.id] = action
            sessionPageActions[key] = actions
        }
        
        if session === currentSession() {
            self.controller?.refreshAddressBar()
        }
    }
    
    func addonController(_ controller: AddonRuntime, didRequestOpenPopup popupURL: String, for addon: Addon, action: AddonAction, session: GeckoSession?) {
        Task { @MainActor [weak self] in
            self?.presentPopupAfterMenuDismissal(
                url: popupURL,
                title: action.title ?? addon.metaData.name ?? L("Extension")
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
                windowId: nil,
                at: self?.controller?.tabManager.regularTabs.count,
                loadURLInApp: true
            )
        }
        
        if let presentedViewController = presentedViewControllerForDismissal() {
            presentedViewController.dismiss(animated: true, completion: createTab)
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
        
        if let presentedViewController = presentedViewControllerForDismissal() {
            presentedViewController.dismiss(animated: true, completion: createTab)
        } else {
            createTab()
        }
        return true
    }
    
    func addonController(_ controller: AddonRuntime, updateTab session: GeckoSession, for addon: Addon, details: AddonUpdateTabDetails) -> AllowOrDeny {
        _ = addon
        guard let index = self.controller?.tabManager.tabIndex(for: session) else {
            return .deny
        }
        
        if details.active == true {
            self.controller?.selectTab(at: index, animated: false)
        }
        
        return .allow
    }
    
    func addonController(_ controller: AddonRuntime, closeTab session: GeckoSession, for addon: Addon) -> AllowOrDeny {
        _ = addon
        guard let index = self.controller?.tabManager.tabIndex(for: session) else {
            return .deny
        }
        
        self.controller?.closeTab(at: index)
        return .allow
    }
    
    private func currentSession() -> GeckoSession? {
        controller?.tabManager.selectedTab?.session
    }
    
    private func clearCachedActions(for addonID: String) {
        sessionBrowserActions = sessionBrowserActions.reduce(into: [:]) { result, entry in
            var actions = entry.value
            actions.removeValue(forKey: addonID)
            if !actions.isEmpty {
                result[entry.key] = actions
            }
        }
        
        sessionPageActions = sessionPageActions.reduce(into: [:]) { result, entry in
            var actions = entry.value
            actions.removeValue(forKey: addonID)
            if !actions.isEmpty {
                result[entry.key] = actions
            }
        }
    }
    
    private func mergedBrowserAction(for addon: Addon, session: GeckoSession) -> AddonAction? {
        let key = ObjectIdentifier(session)
        if let override = sessionBrowserActions[key]?[addon.id],
           let defaultAction = addon.browserAction {
            return override.merged(with: defaultAction)
        }
        return sessionBrowserActions[key]?[addon.id] ?? addon.browserAction
    }
    
    private func mergedPageAction(for addon: Addon, session: GeckoSession) -> AddonAction? {
        let key = ObjectIdentifier(session)
        if let override = sessionPageActions[key]?[addon.id],
           let defaultAction = addon.pageAction {
            return override.merged(with: defaultAction)
        }
        return sessionPageActions[key]?[addon.id] ?? addon.pageAction
    }
    
    private func shouldInterceptAMOInstall(_ response: ExternalResponseInfo) -> Bool {
        guard let url = URL(string: response.url),
              url.host?.lowercased() == "addons.mozilla.org" else {
            return false
        }
        
        let path = url.path.lowercased()
        return path.contains("/firefox/downloads/file/") && path.hasSuffix(".xpi")
    }
    
    @MainActor
    private func presentPopupAfterMenuDismissal(url: String, title: String) {
        controller?.browserUI.addressBar.performAfterMenuDismissal { [weak self] in
            self?.presentModalPopup(url: url, title: title)
        }
    }
    
    private func presentModalPopup(url: String, title: String) {
        let popupViewController = AddonPopupViewController(
            url: url,
            title: title,
            openURLInTab: { [weak self] url in
                self?.openPopupURLInNewTab(url)
            },
            createNewSessionTab: { [weak self] url, windowId in
                self?.createPopupSessionTab(url: url, windowId: windowId)
            },
            onDismiss: { [weak self] in
                self?.restoreBrowserTabInteraction()
            }
        )
        
        // Hack: Use .overFullScreen so GeckoView can scroll
        popupViewController.modalPresentationStyle = .overFullScreen
        popupViewController.isModalInPresentation = true
        
        let presenter = self.topPresentedViewController() ?? self.controller
        presenter?.present(popupViewController, animated: true)
    }
    
    private func presentAlert(title: String?, message: String) {
        guard let presenter = topPresentedViewController() else {
            return
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("OK"), style: .default))
        presenter.present(alert, animated: true)
    }
    
    @discardableResult
    private func createAddonTab(
        selecting: Bool,
        url: String?,
        windowId: String? = nil,
        at index: Int? = nil,
        loadURLInApp: Bool = false
    ) -> Tab? {
        guard let controller else {
            return nil
        }
        
        let tabIndex = controller.createTab(selecting: selecting, windowId: windowId, at: index, isPrivate: false)
        guard controller.tabManager.regularTabs.indices.contains(tabIndex) else {
            return nil
        }
        
        let tab = controller.tabManager.regularTabs[tabIndex]
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            if loadURLInApp {
                controller.tabManager.browse(to: url, in: tab)
            } else {
                tab.pendingDisplayText = url
            }
            
            if tabIndex == controller.tabManager.selectedTabIndex,
               controller.tabManager.selectedTabMode == .regular {
                controller.refreshAddressBar()
            }
        }
        
        return tab
    }
    
    private func openPopupURLInNewTab(_ url: String) {
        let createTab: () -> Void = { [weak self] in
            self?.createAddonTab(selecting: true, url: url, loadURLInApp: true)
        }
        
        if let presentedViewController = presentedViewControllerForDismissal() {
            presentedViewController.dismiss(animated: true, completion: createTab)
        } else {
            createTab()
        }
    }
    
    private func createPopupSessionTab(url: String, windowId: String) -> GeckoSession? {
        let session = createAddonTab(selecting: true, url: url, windowId: windowId)?.session
        presentedViewControllerForDismissal()?.dismiss(animated: true)
        return session
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
    
    func iconImage(for addon: Addon) -> UIImage? {
        let cacheKey = addon.id as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }
        return UIImage(systemName: "puzzlepiece.extension")
    }
    
    private func prefetchIconIfNeeded(for addon: Addon) {
        let cacheKey = addon.id as NSString
        guard iconCache.object(forKey: cacheKey) == nil,
              iconPrefetchIDs.contains(addon.id) == false,
              addon.metaData.iconURL != nil else {
            return
        }
        
        iconPrefetchIDs.insert(addon.id)
        let iconURL = addon.metaData.iconURL
        iconLoadingQueue.async { [weak self] in
            guard let self else {
                return
            }
            let image = AddonIconLoader.loadImage(from: iconURL, targetSize: CGSize(width: 18, height: 18))
            DispatchQueue.main.async {
                self.iconPrefetchIDs.remove(addon.id)
                if let image {
                    self.iconCache.setObject(image, forKey: cacheKey)
                }
                self.controller?.refreshAddressBar()
            }
        }
    }
    
    private func presentedViewControllerForDismissal() -> UIViewController? {
        guard let controller,
              let presentedViewController = topPresentedViewController(),
              presentedViewController !== controller else {
            return nil
        }
        return presentedViewController
    }
    
    private func restoreBrowserTabInteraction() {
        DispatchQueue.main.async { [weak self] in
            guard let controller = self?.controller,
                  let session = controller.tabManager.selectedTab?.session else {
                return
            }
            
            controller.browserUI.geckoView.session = session
            session.setActive(true)
            session.setFocused(true)
        }
    }
    
    func prepareVisibleAddonIcons() {
        guard let session = currentSession() else {
            return
        }
        
        addonsInMenu
            .filter { addon in
                visibleActions(for: addon, session: session).isEmpty == false
            }
            .forEach { prefetchIconIfNeeded(for: $0) }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

private final class AddonPopupViewController: UIViewController, ContentDelegate, NavigationDelegate {
    private let popupURL: String
    private let popupTitle: String
    private let openURLInTab: (String) -> Void
    private let createNewSessionTab: (String, String) -> GeckoSession?
    private let onDismiss: () -> Void
    private let geckoView = GeckoView()
    private let session = GeckoSession()
    private var hasClosedSession = false
    
    init(
        url: String,
        title: String,
        openURLInTab: @escaping (String) -> Void,
        createNewSessionTab: @escaping (String, String) -> GeckoSession?,
        onDismiss: @escaping () -> Void
    ) {
        popupURL = url
        popupTitle = title
        self.openURLInTab = openURLInTab
        self.createNewSessionTab = createNewSessionTab
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        session.isAddonPopup = true
        session.contentDelegate = self
        session.navigationDelegate = self
        session.updateSettings(GeckoSessionController.shared.sessionSettings(for: popupURL, tabID: nil))
        session.open()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        view.addSubview(containerView)
        
        let maxSheetWidth: CGFloat = 430
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: maxSheetWidth),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultLow),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let mediumHeight = containerView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.7)
        let largeHeight = containerView.heightAnchor.constraint(equalTo: view.heightAnchor)
        
        if traitCollection.horizontalSizeClass == .compact &&
            traitCollection.verticalSizeClass == .compact {
            largeHeight.isActive = true
        } else {
            mediumHeight.isActive = true
        }
        
        let sheetView = UIView()
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.backgroundColor = UIColor.systemBackground
        sheetView.layer.cornerRadius = 16
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.clipsToBounds = true
        
        containerView.addSubview(sheetView)
        
        NSLayoutConstraint.activate([
            sheetView.topAnchor.constraint(equalTo: containerView.topAnchor),
            sheetView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        containerView.layer.cornerRadius = 16
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.18
        containerView.layer.shadowRadius = 12
        containerView.layer.shadowOffset = CGSize(width: 0, height: -4)
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = UIColor.separator.cgColor
        
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        sheetView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            closeButton.widthAnchor.constraint(equalToConstant: 30)
        ])
        
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(geckoView)
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            geckoView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor)
        ])
        
        geckoView.session = session
        session.load(popupURL)
    }
    
    @objc private func closeTapped() {
        onCloseRequest(session: session)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true {
            closeSessionIfNeeded()
            onDismiss()
        }
    }
    
    deinit {
        closeSessionIfNeeded()
    }
    
    func onCloseRequest(session: GeckoSession) {
        closeSessionIfNeeded()
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        guard request.target == .new else {
            return .allow
        }
        
        openURLInTab(request.uri)
        return .deny
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        createNewSessionTab(uri, windowId)
    }
    
    private func closeSessionIfNeeded() {
        guard !hasClosedSession else {
            return
        }
        hasClosedSession = true
        geckoView.session = nil
        self.session.close()
    }
}

enum AddonIconLoader {
    static func loadImage(from iconURLString: String?, targetSize: CGSize) -> UIImage? {
        guard let iconURLString,
              let url = URL(string: iconURLString),
              let data = loadData(from: url) else {
            return nil
        }
        
        if iconURLString.lowercased().hasSuffix(".svg") {
            return SVGIconRenderer.render(data: data, size: targetSize)
        }
        
        guard let image = UIImage(data: data) else {
            return nil
        }
        return resizedImage(from: image, targetSize: targetSize)
    }
    
    private static func loadData(from url: URL) -> Data? {
        switch url.scheme?.lowercased() {
        case "file":
            return try? Data(contentsOf: url)
        case "jar":
            return jarEntryData(from: url)
        default:
            return nil
        }
    }
    
    private static func jarEntryData(from url: URL) -> Data? {
        let absoluteString = url.absoluteString
        guard absoluteString.hasPrefix("jar:") else {
            return nil
        }
        
        let jarString = String(absoluteString.dropFirst(4))
        let components = jarString.components(separatedBy: "!/")
        guard components.count == 2,
              let archiveURL = URL(string: components[0]),
              archiveURL.isFileURL,
              let archiveData = try? Data(contentsOf: archiveURL) else {
            return nil
        }
        
        return ZipArchiveReader.entryData(in: archiveData, path: components[1])
    }
    
    private static func resizedImage(from image: UIImage, targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private enum ZipArchiveReader {
    static func entryData(in archiveData: Data, path: String) -> Data? {
        guard let endOfCentralDirectoryOffset = endOfCentralDirectoryOffset(in: archiveData) else {
            return nil
        }
        
        let entryCount = Int(readUInt16(in: archiveData, at: endOfCentralDirectoryOffset + 10))
        var offset = Int(readUInt32(in: archiveData, at: endOfCentralDirectoryOffset + 16))
        
        for _ in 0..<entryCount {
            guard readUInt32(in: archiveData, at: offset) == 0x02014B50 else {
                return nil
            }
            
            let compressionMethod = readUInt16(in: archiveData, at: offset + 10)
            let compressedSize = Int(readUInt32(in: archiveData, at: offset + 20))
            let uncompressedSize = Int(readUInt32(in: archiveData, at: offset + 24))
            let fileNameLength = Int(readUInt16(in: archiveData, at: offset + 28))
            let extraFieldLength = Int(readUInt16(in: archiveData, at: offset + 30))
            let commentLength = Int(readUInt16(in: archiveData, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(in: archiveData, at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            
            guard let fileName = String(data: archiveData.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
                return nil
            }
            
            if fileName == path {
                return localEntryData(
                    in: archiveData,
                    localHeaderOffset: localHeaderOffset,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
            }
            
            offset = nameEnd + extraFieldLength + commentLength
        }
        
        return nil
    }
    
    private static func localEntryData(
        in archiveData: Data,
        localHeaderOffset: Int,
        compressionMethod: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) -> Data? {
        guard readUInt32(in: archiveData, at: localHeaderOffset) == 0x04034B50 else {
            return nil
        }
        
        let fileNameLength = Int(readUInt16(in: archiveData, at: localHeaderOffset + 26))
        let extraFieldLength = Int(readUInt16(in: archiveData, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        let dataEnd = dataStart + compressedSize
        guard archiveData.count >= dataEnd else {
            return nil
        }
        
        let compressedData = archiveData.subdata(in: dataStart..<dataEnd)
        switch compressionMethod {
        case 0:
            return compressedData
        case 8:
            return inflate(data: compressedData, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }
    
    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let minimumSize = 22
        guard data.count >= minimumSize else {
            return nil
        }
        
        let startOffset = max(0, data.count - 65557)
        let signature: UInt32 = 0x06054B50
        for offset in stride(from: data.count - minimumSize, through: startOffset, by: -1) {
            if readUInt32(in: data, at: offset) == signature {
                return offset
            }
        }
        return nil
    }
    
    private static func readUInt16(in data: Data, at offset: Int) -> UInt16 {
        let lower = UInt16(data[offset])
        let upper = UInt16(data[offset + 1]) << 8
        return lower | upper
    }
    
    private static func readUInt32(in data: Data, at offset: Int) -> UInt32 {
        let lower = UInt32(readUInt16(in: data, at: offset))
        let upper = UInt32(readUInt16(in: data, at: offset + 2)) << 16
        return lower | upper
    }
    
    private static func inflate(data: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        var status = data.withUnsafeBytes { inputBuffer -> Int32 in
            guard let baseAddress = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(inputBuffer.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        
        guard status == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        
        let chunkSize = max(expectedSize, 32 * 1024)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        
        repeat {
            status = buffer.withUnsafeMutableBytes { outputBuffer -> Int32 in
                guard let baseAddress = outputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_DATA_ERROR
                }
                stream.next_out = baseAddress
                stream.avail_out = uInt(outputBuffer.count)
                return zlib.inflate(&stream, Z_NO_FLUSH)
            }
            
            let producedCount = buffer.count - Int(stream.avail_out)
            if producedCount > 0 {
                output.append(contentsOf: buffer.prefix(producedCount))
            }
        } while status == Z_OK
        
        guard status == Z_STREAM_END else {
            return nil
        }
        
        return output
    }
}

private enum SVGIconRenderer {
    private typealias SVGDocumentRef = UnsafeMutableRawPointer
    private typealias CreateDocumentFunction = @convention(c) (CFData, CFDictionary?) -> SVGDocumentRef?
    private typealias ReleaseDocumentFunction = @convention(c) (SVGDocumentRef) -> Void
    private typealias DrawDocumentFunction = @convention(c) (CGContext, SVGDocumentRef) -> Void
    private typealias GetCanvasSizeFunction = @convention(c) (SVGDocumentRef) -> CGSize
    
    private static let frameworkHandle = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_LAZY)
    private static let createDocument = symbol(named: "CGSVGDocumentCreateFromData", as: CreateDocumentFunction.self)
    private static let releaseDocument = symbol(named: "CGSVGDocumentRelease", as: ReleaseDocumentFunction.self)
    private static let drawDocument = symbol(named: "CGContextDrawSVGDocument", as: DrawDocumentFunction.self)
    private static let getCanvasSize = symbol(named: "CGSVGDocumentGetCanvasSize", as: GetCanvasSizeFunction.self)
    
    static func render(data: Data, size: CGSize) -> UIImage? {
        guard let createDocument,
              let releaseDocument,
              let drawDocument else {
            return nil
        }
        
        guard let document = createDocument(data as CFData, nil) else {
            return nil
        }
        defer { releaseDocument(document) }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            
            if let getCanvasSize {
                let canvasSize = getCanvasSize(document)
                if canvasSize.width > 0, canvasSize.height > 0 {
                    let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
                    let scaledSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
                    let origin = CGPoint(x: (size.width - scaledSize.width) / 2, y: (size.height - scaledSize.height) / 2)
                    cgContext.translateBy(x: origin.x, y: origin.y + scaledSize.height)
                    cgContext.scaleBy(x: scale, y: -scale)
                } else {
                    cgContext.translateBy(x: 0, y: size.height)
                    cgContext.scaleBy(x: 1, y: -1)
                }
            } else {
                cgContext.translateBy(x: 0, y: size.height)
                cgContext.scaleBy(x: 1, y: -1)
            }
            
            drawDocument(cgContext, document)
            cgContext.restoreGState()
        }
    }
    
    private static func symbol<T>(named name: String, as type: T.Type) -> T? {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}
