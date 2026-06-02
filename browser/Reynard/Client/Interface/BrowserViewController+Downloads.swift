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
    static var haptic = 0
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
    
    var downloadHaptic: UINotificationFeedbackGenerator {
        if let existing = objc_getAssociatedObject(self, &DownloadAssociatedKeys.haptic) as? UINotificationFeedbackGenerator {
            return existing
        }
        let generator = UINotificationFeedbackGenerator()
        objc_setAssociatedObject(self, &DownloadAssociatedKeys.haptic, generator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return generator
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
        let previousTopBarShowsDownloads = browserUI.topBarButtons.downloadButton.isShowingDownloads
        let summary = DownloadStore.shared.snapshot().summary
        browserUI.bottomToolbar.updateDownloadButton(summary: summary)
        browserUI.topBarButtons.updateDownloadButton(summary: summary)
        let showsTopBarDownloads = browserUI.topBarButtons.downloadButton.isShowingDownloads
        
        if !shouldEmbedSidebarContainer,
           isPad,
           !usesCompactPadChrome,
           previousTopBarShowsDownloads != showsTopBarDownloads {
            browserUI.applyChromeLayout(animated: false)
        }
    }
    
    func downloadsButtonClicked() {
        presentDownloadsFromToolbar()
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
        if isPad,
           !usesCompactPadChrome,
           let splitViewController = splitViewController as? BrowserSplitViewController {
            splitViewController.showLibrarySection(.downloads)
            return
        }
        
        presentMenuSheet(initialSection: .downloads)
    }
    
    private func presentNextDownloadConfirmationIfNeeded() {
        downloadHaptic.prepare()
        guard !isPresentingDownloadConfirmation,
              let download = pendingDownloadConfirmations.first,
              let presenter = topPresentedViewController else {
            return
        }
        
        isPresentingDownloadConfirmation = true
        
        let alert = UIAlertController(
            title: String(format: L("Do you want to download \"%@\"?"), download.fileName),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel) { [weak self] _ in
            self?.finishDownloadConfirmation(startDownload: false)
        })
        alert.addAction(UIAlertAction(title: L("Download"), style: .default) { [weak self] _ in
            self?.downloadHaptic.notificationOccurred(.success)
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
