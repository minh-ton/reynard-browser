//
//  PermissionPromptPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

struct PermissionPromptPresenter: PermissionPromptPresenting {
    let window: () -> UIWindow?
    
    @MainActor
    func request(
        title: String,
        message: String?,
        cancelTitle: String,
        for session: GeckoSession
    ) async -> Bool {
        guard let presenter = UIApplication.shared.topViewController(in: window()) else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            var allowed = false
            let alert = PromptAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: allowed)
            }
            alert.setValue(
                NSAttributedString(
                    string: title,
                    attributes: [.font: UIFont.boldSystemFont(ofSize: 17)]
                ),
                forKey: "attributedTitle"
            )
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Allow", comment: ""), style: .default) { _ in
                allowed = true
            })
            presenter.present(alert, animated: true)
        }
    }
}
