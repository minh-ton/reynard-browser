//
//  PagePrintPreparationAlert.swift
//  Reynard
//
//  Created by Minh Ton on 22/9/26.
//

import UIKit

@MainActor
enum PagePrintPreparationAlert {
    static func prepare(
        in window: UIWindow?,
        _ operation: @escaping @MainActor () async throws -> URL
    ) async throws -> URL {
        guard let presenter = UIApplication.shared.topViewController(in: window) else {
            throw PagePrintPreparationError.unavailable
        }
        return try await PagePrintPreparation(operation: operation).run(from: presenter)
    }
}

@MainActor
private final class PagePrintPreparation {
    private enum UX {
        static let activityIndicatorSpacing: CGFloat = 8
    }
    
    private let operation: @MainActor () async throws -> URL
    private let alert = UIAlertController(
        title: nil,
        message: NSLocalizedString("Preparing Page for Printing…", comment: ""),
        preferredStyle: .alert
    )
    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<URL, Error>?
    
    init(operation: @escaping @MainActor () async throws -> URL) {
        self.operation = operation
        alert.addAction(
            UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
                self?.cancel()
            }
        )
    }
    
    func run(from presenter: UIViewController) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presenter.present(alert, animated: true) { [weak self] in
                guard let self else {
                    return
                }
                self.installActivityIndicator()
                self.task = Task { @MainActor [weak self] in
                    await self?.prepare()
                }
            }
        }
    }
    
    private func prepare() async {
        defer {
            task = nil
        }
        do {
            let fileURL = try await operation()
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            dismissAlert {
                self.resume(with: .success(fileURL))
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            dismissAlert {
                self.resume(with: .failure(error))
            }
        }
    }
    
    private func cancel() {
        task?.cancel()
        task = nil
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }
    
    private func installActivityIndicator() {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else {
            return
        }
        
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        
        let statusLabel = UILabel()
        statusLabel.font = messageLabel.font
        statusLabel.text = messageText
        statusLabel.textColor = messageLabel.textColor
        
        let contentView = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .horizontal
        contentView.alignment = .center
        contentView.spacing = UX.activityIndicatorSpacing
        alert.view.addSubview(contentView)
        messageLabel.textColor = .clear
        messageLabel.isAccessibilityElement = false
        
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
        ])
    }
    
    private func dismissAlert(completion: @escaping () -> Void) {
        guard alert.presentingViewController != nil else {
            completion()
            return
        }
        alert.dismiss(animated: true, completion: completion)
    }
    
    private func resume(with result: Result<URL, Error>) {
        guard let continuation else {
            if case .success(let fileURL) = result {
                try? FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

private enum PagePrintPreparationError: Error {
    case unavailable
}
