//
//  DownloadsCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

protocol DownloadsCoordinatorDelegate: AnyObject {
    var downloadsAlertPresenter: UIViewController? { get }
    var downloadsShouldRefreshLayoutForStoreChange: Bool { get }

    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary)
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator)
}

final class DownloadsCoordinator {
    // MARK: - State

    private weak var delegate: DownloadsCoordinatorDelegate?
    private var confirmationQueue: [DownloadStore.PendingDownload] = []
    private var isShowingConfirmationAlert = false
    private var storeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    init(delegate: DownloadsCoordinatorDelegate) {
        self.delegate = delegate
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
        let summary = DownloadStore.shared.currentSnapshot().summary
        delegate?.downloadsCoordinator(self, didUpdate: summary)
        if delegate?.downloadsShouldRefreshLayoutForStoreChange == true {
            delegate?.downloadsCoordinatorDidRequestLayoutRefresh(self)
        }
    }

    func enqueueConfirmation(_ pendingDownload: DownloadStore.PendingDownload) {
        confirmationQueue.append(pendingDownload)
        presentNextConfirmationAlertIfNeeded()
    }

    private func presentNextConfirmationAlertIfNeeded() {
        guard !isShowingConfirmationAlert,
              let pendingDownload = confirmationQueue.first,
              let presenter = delegate?.downloadsAlertPresenter else {
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
            DownloadStore.shared.start(pendingDownload)
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentNextConfirmationAlertIfNeeded()
        }
    }

}
