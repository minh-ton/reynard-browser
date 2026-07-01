//
//  HomepageThumbnailRenderer.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

final class HomepageThumbnailRenderer {
    private weak var homepageViewController: HomepageViewController?
    
    init(homepageViewController: HomepageViewController) {
        self.homepageViewController = homepageViewController
    }
    
    func prepareForCapture(contentMode: HomepageContentMode, isPrivateBrowsing: Bool) {
        guard let homepageViewController else {
            return
        }
        
        homepageViewController.loadViewIfNeeded()
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
        homepageViewController.setContentMode(contentMode)
        homepageViewController.setShowsBackground(true)
        homepageViewController.view.setNeedsLayout()
        homepageViewController.view.layoutIfNeeded()
    }
    
    func capture(
        size: CGSize,
        contentMode: HomepageContentMode,
        isPrivateBrowsing: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard size.width > 1,
              size.height > 1 else {
            completion(nil)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            completion(self?.snapshot(size: size, contentMode: contentMode, isPrivateBrowsing: isPrivateBrowsing))
        }
    }

    func snapshot(
        size: CGSize,
        contentMode: HomepageContentMode,
        isPrivateBrowsing: Bool
    ) -> UIImage? {
        guard size.width > 1,
              size.height > 1,
              let homepageViewController else {
            return nil
        }

        homepageViewController.loadViewIfNeeded()
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
        homepageViewController.setContentMode(contentMode)
        homepageViewController.setShowsBackground(true)

        let view = homepageViewController.view!
        let originalFrame = view.frame
        let temporarilyAttachedView = view.superview == nil
        if temporarilyAttachedView {
            let captureContainer = UIView(frame: CGRect(origin: .zero, size: size))
            captureContainer.addSubview(view)
            view.frame = captureContainer.bounds
        }

        view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }

        if temporarilyAttachedView {
            view.removeFromSuperview()
        }
        view.frame = originalFrame
        return image
    }
}
