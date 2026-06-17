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
}
