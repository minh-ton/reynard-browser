//
//  DownloadsCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class DownloadsCoordinator {
    private weak var browser: BrowserViewController?
    private var confirmationQueue: [DownloadStore.PendingDownload] = []
    private var isShowingConfirmationAlert = false
    private var storeObserver: NSObjectProtocol?

    init(browserViewController: BrowserViewController) {
        self.browser = browserViewController
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    func startObservingStore() {
        guard storeObserver == nil else {
            return
        }

        storeObserver = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncToolbarButtonState()
        }
    }

    func syncToolbarButtonState() {
        guard let browser else {
            return
        }

        let summary = DownloadStore.shared.snapshot().summary
        browser.browserChrome.updateDownload(summary)
        if !browser.sidebarCoordinator.hostsSidebar,
           browser.browserLayout.interfaceIdiom == .pad,
           browser.browserLayout.chromeMode == .pad {
            browser.updateBrowserLayout(animated: false)
        }
    }

    func enqueueConfirmation(_ pendingDownload: DownloadStore.PendingDownload) {
        confirmationQueue.append(pendingDownload)
        presentNextConfirmationAlertIfNeeded()
    }

    private func presentNextConfirmationAlertIfNeeded() {
        guard !isShowingConfirmationAlert,
              let pendingDownload = confirmationQueue.first,
              let presenter = alertPresenter else {
            return
        }

        isShowingConfirmationAlert = true

        let alert = UIAlertController(
            title: "Do you want to download \"\(pendingDownload.fileName)\"?",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.resolveConfirmation(shouldStartDownload: false)
        })
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self?.resolveConfirmation(shouldStartDownload: true)
        })

        presenter.present(alert, animated: true)
    }

    private func resolveConfirmation(shouldStartDownload: Bool) {
        guard !confirmationQueue.isEmpty else {
            isShowingConfirmationAlert = false
            return
        }

        let pendingDownload = confirmationQueue.removeFirst()
        isShowingConfirmationAlert = false

        if shouldStartDownload {
            DownloadStore.shared.startDownload(pendingDownload)
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentNextConfirmationAlertIfNeeded()
        }
    }

    private var alertPresenter: UIViewController? {
        var presenter = browser as UIViewController?

        while let presentedController = presenter?.presentedViewController {
            presenter = presentedController
        }

        return presenter
    }
}
