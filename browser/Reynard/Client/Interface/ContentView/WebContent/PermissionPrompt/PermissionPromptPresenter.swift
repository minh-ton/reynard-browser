//
//  PermissionPromptPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

struct PermissionPromptPresenter: PermissionPromptPresenting {
    @MainActor
    func request(
        title: String,
        message: String?,
        cancelTitle: String,
        for session: GeckoSession
    ) async -> Bool {
        guard let presenter = UIApplication.shared.topViewController() else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            alert.setValue(
                NSAttributedString(
                    string: title,
                    attributes: [.font: UIFont.boldSystemFont(ofSize: 17)]
                ),
                forKey: "attributedTitle"
            )
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
}
