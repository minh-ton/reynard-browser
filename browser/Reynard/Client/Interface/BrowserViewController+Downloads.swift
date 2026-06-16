//
//  BrowserViewController+Downloads.swift
//  Reynard
//
//  Created by Minh Ton on 15/5/26.
//

import ObjectiveC
import UIKit

private enum DownloadAssociatedKeys {
    static var pendingConfirmations = 0
    static var presentingConfirmation = 0
}

private final class PendingDownloadConfirmationsBox {
    var value: [DownloadStore.PendingDownload] = []
}

extension BrowserViewController {
    var pendingDownloadConfirmations: [DownloadStore.PendingDownload] {
        get {
            if let box = objc_getAssociatedObject(self, &DownloadAssociatedKeys.pendingConfirmations) as? PendingDownloadConfirmationsBox {
                return box.value
            }
            let box = PendingDownloadConfirmationsBox()
            objc_setAssociatedObject(self, &DownloadAssociatedKeys.pendingConfirmations, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return box.value
        }
        set {
            let box: PendingDownloadConfirmationsBox
            if let existing = objc_getAssociatedObject(self, &DownloadAssociatedKeys.pendingConfirmations) as? PendingDownloadConfirmationsBox {
                box = existing
            } else {
                box = PendingDownloadConfirmationsBox()
                objc_setAssociatedObject(self, &DownloadAssociatedKeys.pendingConfirmations, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            box.value = newValue
        }
    }
    
    var isPresentingDownloadConfirmation: Bool {
        get {
            (objc_getAssociatedObject(self, &DownloadAssociatedKeys.presentingConfirmation) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &DownloadAssociatedKeys.presentingConfirmation,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

extension BrowserViewController {
    func observeDownloadState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadStoreDidChange),
            name: .downloadStoreDidChange,
            object: nil
        )
    }
    
    @objc func handleDownloadStoreDidChange() {
        syncDownloadButtonState()
    }
    
    func syncDownloadButtonState() {
        let summary = DownloadStore.shared.snapshot().summary
        browserChrome.updateDownload(summary)
        if !shouldEmbedSidebarContainer,
           browserLayout.interfaceIdiom == .pad,
           browserLayout.browserChromeMode == .pad {
            updateBrowserLayout(animated: false)
        }
    }
    
    func enqueueDownloadConfirmation(_ download: DownloadStore.PendingDownload) {
        pendingDownloadConfirmations.append(download)
        presentNextDownloadConfirmationIfNeeded()
    }
    
    @objc func topBarDownloadsTapped() {
        presentDownloadsFromToolbar()
    }
    
    private func presentDownloadsFromToolbar() {
        DownloadStore.shared.markCompletedDownloadsViewed()
        if browserLayout.interfaceIdiom == .pad,
           browserLayout.browserChromeMode == .pad,
           let splitViewController = splitViewController as? BrowserSplitViewController {
            splitViewController.showLibrarySection(.downloads)
            return
        }
        
        presentMenuSheet(initialSection: .downloads)
    }
    
    private func presentNextDownloadConfirmationIfNeeded() {
        guard !isPresentingDownloadConfirmation,
              let download = pendingDownloadConfirmations.first,
              let presenter = topPresentedViewController else {
            return
        }
        
        isPresentingDownloadConfirmation = true
        
        let alert = UIAlertController(
            title: "Do you want to download \"\(download.fileName)\"?",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finishDownloadConfirmation(startDownload: false)
        })
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            let downloadHaptic = UINotificationFeedbackGenerator()
            downloadHaptic.notificationOccurred(.success)
            self?.finishDownloadConfirmation(startDownload: true)
        })
        
        presenter.present(alert, animated: true)
    }
    
    private func finishDownloadConfirmation(startDownload: Bool) {
        guard !pendingDownloadConfirmations.isEmpty else {
            isPresentingDownloadConfirmation = false
            return
        }
        
        let download = pendingDownloadConfirmations.removeFirst()
        isPresentingDownloadConfirmation = false
        
        if startDownload {
            DownloadStore.shared.startDownload(download)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.presentNextDownloadConfirmationIfNeeded()
        }
    }
    
    private var topPresentedViewController: UIViewController? {
        var controller: UIViewController? = self
        
        while let presentedViewController = controller?.presentedViewController {
            controller = presentedViewController
        }
        
        return controller
    }
}
