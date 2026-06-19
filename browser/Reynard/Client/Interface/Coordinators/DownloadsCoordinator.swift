//
//  DownloadsCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

protocol DownloadsCoordinatorDelegate: AnyObject {
    var downloadsShouldRefreshLayoutForStoreChange: Bool { get }
    
    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary)
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator)
}

final class DownloadsCoordinator {
    private weak var delegate: DownloadsCoordinatorDelegate?
    private var confirmationQueue: [DownloadStore.PendingDownload] = []
    private var isShowingConfirmationAlert = false
    private var storeObserver: NSObjectProtocol?
    
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
              let pendingDownload = confirmationQueue.first else {
            return
        }
        
        isShowingConfirmationAlert = true
        
        AlertPresenter.show(
            title: "Do you want to download \"\(pendingDownload.fileName)\"?",
            message: nil,
            buttons: [
                AlertPresenter.Button(title: "Cancel", style: .cancel) { [weak self] in
                    self?.resolveConfirmation(shouldStartDownload: false)
                },
                AlertPresenter.Button(title: "Download") { [weak self] in
                    Haptics.success()
                    self?.resolveConfirmation(shouldStartDownload: true)
                },
            ]
        )
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
