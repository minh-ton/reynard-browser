//
//  UIViewController+Presentation.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension UIViewController {
    func topPresentedController() -> UIViewController {
        var controller = self
        while let presentedController = controller.presentedViewController {
            controller = presentedController
        }
        return controller
    }

    func presentAlert(title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
