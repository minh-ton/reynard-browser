//
//  UIApplication+Presentation.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

extension UIApplication {
    var isSidebarOverlayWidth: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        let screenWidth = max(window.screen.bounds.width, window.screen.bounds.height)
        let windowWidth = window.bounds.width
        
        return windowWidth <= (3.0 / 4.0) * screenWidth + 0.5
    }
    
    func topViewController() -> UIViewController? {
        let rootViewController = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        
        guard let rootViewController else {
            return nil
        }
        
        return topViewController(from: rootViewController)
    }
    
    func topViewController(from rootViewController: UIViewController) -> UIViewController {
        var controller = rootViewController
        while let presentedController = controller.presentedViewController {
            controller = presentedController
        }
        return controller
    }
}
