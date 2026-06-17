//
//  UIView+ViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

extension UIView {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }
}
