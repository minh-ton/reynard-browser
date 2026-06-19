//
//  AlertPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

enum AlertPresenter {
    struct Button {
        let title: String
        let style: UIAlertAction.Style
        let handler: (() -> Void)?
        
        init(
            title: String,
            style: UIAlertAction.Style = .default,
            handler: (() -> Void)? = nil
        ) {
            self.title = title
            self.style = style
            self.handler = handler
        }
    }
    
    static func show(
        title: String?,
        message: String?,
        buttons: [Button] = [Button(title: "OK")]
    ) {
        DispatchQueue.main.async {
            guard let presenter = UIApplication.shared.topViewController() else {
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            for button in buttons {
                alert.addAction(UIAlertAction(title: button.title, style: button.style) { _ in
                    button.handler?()
                })
            }
            presenter.present(alert, animated: true)
        }
    }
}
