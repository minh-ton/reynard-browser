//
//  DataTransferOperationViewController.swift
//  Reynard
//

import UIKit

final class DataTransferOperationViewController: UIViewController, UIDocumentPickerDelegate {
    private enum OperationError: Error {
        case invalidBookmark
        case unavailableCapacity
    }

    private let operation: ReynardDataTransferOperation
    private let launchStore: ReynardDataTransferLaunchStore
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var didStart = false
    private var exportedPackageURL: URL?

    init(
        operation: ReynardDataTransferOperation,
        launchStore: ReynardDataTransferLaunchStore = .shared
    ) {
        self.operation = operation
        self.launchStore = launchStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.accessibilityTraits = [.updatesFrequently]

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        beginOperation()
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finishExport(
            message: NSLocalizedString("Reynard backup saved. Close and reopen Reynard.", comment: "")
        )
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishExport(
            message: NSLocalizedString("Backup export cancelled. Close and reopen Reynard.", comment: "")
        )
    }

    private func beginOperation() {
        activityIndicator.startAnimating()
        setStatus(NSLocalizedString("Preparing your Reynard data…", comment: ""))

        switch operation {
        case .export:
            runExport()
        case let .importBackup(bookmarkData):
            runImport(bookmarkData: bookmarkData)
        }
    }

    private func runExport() {
        let registeredDefaults = Prefs.shared.registeredDefaults
        let preferences = ReynardPreferencesSnapshot(
            registeredDefaults: registeredDefaults
        ).effectiveDomain()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try ReynardBackupExporter(preferences: { preferences }).export()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case let .success(packageURL):
                    self.presentExporter(for: packageURL)
                case let .failure(error):
                    self.finishWithFailure(error)
                }
            }
        }
    }

    private func runImport(bookmarkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.importBackup(bookmarkData: bookmarkData) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.launchStore.clear()
                self.activityIndicator.stopAnimating()
                switch result {
                case .success:
                    self.setStatus(NSLocalizedString(
                        "Reynard data restored. Close and reopen Reynard.",
                        comment: ""
                    ))
                case let .failure(error):
                    self.setStatus(self.message(for: error))
                }
            }
        }
    }

    private static func importBackup(bookmarkData: Data) throws {
        var isStale = false
        let packageURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else {
            throw OperationError.invalidBookmark
        }

        let hasSecurityScope = packageURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                packageURL.stopAccessingSecurityScopedResource()
            }
            removeOwnedPendingImport(at: packageURL)
        }

        let values = try ReynardDirectories.shared.temporary.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )
        guard let availableCapacity = values.volumeAvailableCapacity,
              availableCapacity >= 0 else {
            throw OperationError.unavailableCapacity
        }
        let validated = try ReynardBackupValidator().validate(
            at: packageURL,
            availableCapacity: UInt64(availableCapacity)
        )
        try ReynardMigrationTransaction().apply(validated)
    }

    private static func removeOwnedPendingImport(at packageURL: URL) {
        let pendingRoot = ReynardDirectories.shared.temporary
            .appendingPathComponent("PendingImport", isDirectory: true)
            .standardizedFileURL
        let package = packageURL.standardizedFileURL
        guard package.pathComponents.starts(with: pendingRoot.pathComponents),
              package.pathComponents.count == pendingRoot.pathComponents.count + 1 else {
            return
        }
        try? FileManager.default.removeItem(at: package)
    }

    private func presentExporter(for packageURL: URL) {
        exportedPackageURL = packageURL
        activityIndicator.stopAnimating()
        setStatus(NSLocalizedString("Choose where to save your Reynard backup.", comment: ""))

        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forExporting: [packageURL], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(url: packageURL, in: .exportToService)
        }
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    private func finishExport(message: String) {
        launchStore.clear()
        if let exportedPackageURL {
            try? FileManager.default.removeItem(at: exportedPackageURL)
        }
        exportedPackageURL = nil
        activityIndicator.stopAnimating()
        setStatus(message)
    }

    private func finishWithFailure(_ error: Error) {
        launchStore.clear()
        activityIndicator.stopAnimating()
        setStatus(message(for: error))
    }

    private func setStatus(_ message: String) {
        statusLabel.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func message(for error: Error) -> String {
        guard let transferError = error as? ReynardDataTransferError else {
            return NSLocalizedString(
                "Reynard couldn’t finish the data transfer. Close and reopen Reynard to try again.",
                comment: ""
            )
        }
        switch transferError {
        case .unsupportedVersion:
            return NSLocalizedString("This backup version isn’t supported.", comment: "")
        case .unsafePath, .unsupportedFileType, .invalidManifest, .missingFile, .extraFile:
            return NSLocalizedString("This Reynard backup is invalid or unsafe.", comment: "")
        case .sizeMismatch, .checksumMismatch:
            return NSLocalizedString("This Reynard backup is damaged.", comment: "")
        case .insufficientSpace:
            return NSLocalizedString("There isn’t enough free space to restore this backup.", comment: "")
        case .stagingFailure:
            return NSLocalizedString("Reynard couldn’t prepare this backup for restore.", comment: "")
        case .applyFailure:
            return NSLocalizedString("The restore failed. Your previous Reynard data was restored.", comment: "")
        case .rollbackFailure:
            return NSLocalizedString(
                "Automatic recovery couldn’t finish. Your recovery files were kept.",
                comment: ""
            )
        }
    }
}
