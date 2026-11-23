//
//  BrowserViewController+Addons.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: AddonCoordinatorDelegate {
    var shouldPresentAddonPopupAsPopover: Bool {
        return browserLayout.chromeMode == .pad
    }
    
    func refreshAddonChrome(_ coordinator: AddonCoordinator) {
        refreshAddressBar()
    }
    
    func performAfterAddonMenuDismissal(_ coordinator: AddonCoordinator, work: @escaping () -> Void) {
        browserChrome.addressBar.performAfterMenuDismissal(work)
    }
    
    func presentAddonViewController(_ coordinator: AddonCoordinator, _ viewController: UIViewController) {
        let presentViewController = { [weak self] in
            guard let self else {
                return
            }
            
            UIApplication.shared.topViewController(from: self).present(viewController, animated: true)
        }
        
        if let popupViewController = viewController as? AddonPopupViewController,
           let popover = popupViewController.popoverPresentationController {
            toolbarController.lock(for: .addonPopover)
            let sourceButton = browserChrome.addressBar.addressBarButton
            popover.sourceView = sourceButton
            popover.sourceRect = sourceButton.bounds
            popover.permittedArrowDirections = .up
            popover.delegate = popupViewController
            browserChrome.addressBar.performAfterMenuDismissal(presentViewController)
            return
        }
        
        presentViewController()
    }
    
    func presentAddonAlert(_ coordinator: AddonCoordinator, title: String?, message: String) {
        AlertPresenter.show(title: title, message: message)
    }
    
    func dismissAddonModal(_ coordinator: AddonCoordinator, completion: (() -> Void)?) -> Bool {
        let presenter = UIApplication.shared.topViewController(from: self)
        guard presenter !== self else {
            return false
        }
        
        presenter.dismiss(animated: true, completion: completion)
        return true
    }
    
    @MainActor
    func confirmAddonDownload(
        _ coordinator: AddonCoordinator,
        options: [String: Any?]
    ) async -> DownloadStore.WebExtensionDownloadItem? {
        guard let pendingDownload = DownloadStore.shared.pendingDownload(
            from: options
        ) else {
            return nil
        }
        
        return await downloadsCoordinator.confirmWebExtensionDownload(pendingDownload)
    }
    
    func restoreAddonTabInteraction(_ coordinator: AddonCoordinator) {
        toolbarController.unlock(for: .addonPopover)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let session = tabManager.selectedTab?.session else {
                return
            }
            
            contentView.restoreInteraction(for: session)
            sessionManager.activate(session)
            requestContentKeyboardFocus(for: session)
        }
    }
}
