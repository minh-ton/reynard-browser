//
//  DownloadsCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

protocol DownloadsCoordinatorDelegate: AnyObject {
    var downloadsShouldRefreshLayoutForStoreChange: Bool { get }
    var downloadsConfirmationWindow: UIWindow? { get }
    
    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary)
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator)
}

final class DownloadsCoordinator {
    private struct ConfirmationRequest {
        let download: DownloadStore.PendingDownload
        let completion: (Bool) -> Void
    }
    
    private weak var delegate: DownloadsCoordinatorDelegate?
    private let initiatorID = UUID()
    private var confirmationQueue: [ConfirmationRequest] = []
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
        let summary = DownloadStore.shared.summary(for: initiatorID)
        delegate?.downloadsCoordinator(self, didUpdate: summary)
        if delegate?.downloadsShouldRefreshLayoutForStoreChange == true {
            delegate?.downloadsCoordinatorDidRequestLayoutRefresh(self)
        }
    }
    
    // MARK: - Download Confirmation
    
    func enqueueConfirmation(_ pendingDownload: DownloadStore.PendingDownload) {
        queueConfirmation(pendingDownload) { [initiatorID] shouldStart in
            if shouldStart {
                DownloadStore.shared.startDownload(pendingDownload, initiatorID: initiatorID)
            }
        }
    }
    
    func confirm(_ pendingDownload: DownloadStore.PendingDownload) async -> Bool {
        return await withCheckedContinuation { continuation in
            queueConfirmation(pendingDownload) { [initiatorID] shouldStart in
                if shouldStart {
                    DownloadStore.shared.startDownload(pendingDownload, initiatorID: initiatorID)
                }
                continuation.resume(returning: shouldStart)
            }
        }
    }
    
    func confirmWebExtensionDownload(_ pendingDownload: DownloadStore.PendingDownload) async -> DownloadStore.WebExtensionDownloadItem? {
        return await withCheckedContinuation { continuation in
            queueConfirmation(pendingDownload) { [initiatorID] shouldStart in
                guard shouldStart else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: DownloadStore.shared.startDownload(pendingDownload, initiatorID: initiatorID))
            }
        }
    }
    
    private func queueConfirmation(
        _ pendingDownload: DownloadStore.PendingDownload,
        completion: @escaping (Bool) -> Void
    ) {
        confirmationQueue.append(
            ConfirmationRequest(download: pendingDownload, completion: completion)
        )
        presentNextConfirmationAlertIfNeeded()
    }
    
    private func presentNextConfirmationAlertIfNeeded() {
        guard !isShowingConfirmationAlert,
              let request = confirmationQueue.first else {
            return
        }
        
        isShowingConfirmationAlert = true
        
        AlertPresenter.show(
            title: String(format: NSLocalizedString("Do you want to download \"%@\"?", comment: "File name"), request.download.fileName),
            message: nil,
            in: delegate?.downloadsConfirmationWindow,
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] in
                    self?.resolveConfirmation(shouldStartDownload: false)
                },
                AlertPresenter.Button(title: NSLocalizedString("Download", comment: "")) { [weak self] in
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
        
        let request = confirmationQueue.removeFirst()
        isShowingConfirmationAlert = false
        request.completion(shouldStartDownload)
        
        DispatchQueue.main.async { [weak self] in
            self?.presentNextConfirmationAlertIfNeeded()
        }
    }
}
