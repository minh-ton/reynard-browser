//
//  UIApplication+Presentation.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

extension UIApplication {
    var isTwoThirdSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isTwoThirdSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    var isOneThirdSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isOneThirdSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    var isHalfSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isHalfSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    func isTwoThirdSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (3.0 / 4.0) * screenWidth + 0.5
    }
    
    func isOneThirdSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (2.0 / 5.0) * screenWidth + 0.5
    }
    
    func isHalfSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (3.0 / 5.0) * screenWidth + 0.5
    }
    
    func topViewController() -> UIViewController? {
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        
        return topViewController(in: keyWindow)
    }
    
    func topViewController(in window: UIWindow?) -> UIViewController? {
        guard let rootViewController = window?.rootViewController else {
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
