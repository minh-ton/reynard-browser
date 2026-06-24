//
//  HomepageViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

protocol HomepageViewControllerDelegate: AnyObject {
    func homepageViewControllerDidSelectFavorite(_ favorite: BookmarkSnapshot)
    func homepageViewControllerDidSelectPerformanceGuide(_ controller: HomepageViewController)
    func homepageViewControllerDidSelectPerformanceSettings(_ controller: HomepageViewController)
    func homepageViewControllerDidStartScrolling()
}

final class HomepageViewController: UINavigationController {
    weak var homepageDelegate: HomepageViewControllerDelegate? {
        didSet {
            rootViewController.delegate = self
        }
    }
    
    private let rootViewController: HomepageRootViewController
    private let bookmarkStore: BookmarkStore
    private var isPrivateBrowsing: Bool
    private var contentMode: HomepageContentMode = .embeddedNarrow
    
    // MARK: - Lifecycle
    
    init(bookmarkStore: BookmarkStore = .shared, isPrivateBrowsing: Bool = false) {
        self.bookmarkStore = bookmarkStore
        self.isPrivateBrowsing = isPrivateBrowsing
        rootViewController = HomepageRootViewController(
            bookmarkStore: bookmarkStore,
            isPrivateBrowsing: isPrivateBrowsing
        )
        super.init(rootViewController: rootViewController)
        rootViewController.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
    }
    
    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        assignRootDelegates(viewControllers)
    }
    
    // MARK: - Public API
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        self.contentMode = contentMode
        rootViewController.setContentMode(contentMode)
        viewControllers.forEach { viewController in
            guard let viewController = viewController as? HomepageRootViewController else {
                return
            }
            
            viewController.setContentMode(contentMode)
        }
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        rootViewController.setPrivateBrowsing(isPrivateBrowsing)
        viewControllers.forEach { viewController in
            guard let viewController = viewController as? HomepageRootViewController else {
                return
            }
            
            viewController.setPrivateBrowsing(isPrivateBrowsing)
        }
    }
    
    func prepareForPresentation(resetNavigation: Bool) {
        loadViewIfNeeded()
        if resetNavigation {
            popToRootViewController(animated: false)
            rootViewController.resetScrollPosition()
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    func renderSnapshot(size: CGSize, contentMode: HomepageContentMode) -> UIImage? {
        loadViewIfNeeded()
        setContentMode(contentMode)
        
        let wasAttached = view.superview != nil
        let originalFrame = view.frame
        let snapshotContainer = UIView(frame: CGRect(origin: .zero, size: size))
        
        if !wasAttached {
            snapshotContainer.addSubview(view)
            view.frame = snapshotContainer.bounds
        }
        
        view.layoutIfNeeded()
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        if !wasAttached {
            view.removeFromSuperview()
        }
        view.frame = originalFrame
        return image
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        view.backgroundColor = .clear
        delegate = self
        navigationBar.isTranslucent = false
        setNavigationBarHidden(true, animated: false)
    }
    
    private func makeFolderRootViewController(folder: BookmarkFolderSnapshot) -> HomepageRootViewController {
        let viewController = HomepageRootViewController(
            bookmarkStore: bookmarkStore,
            folder: folder,
            sections: [.favorites],
            isPrivateBrowsing: isPrivateBrowsing
        )
        viewController.delegate = self
        viewController.setContentMode(contentMode)
        return viewController
    }
    
    private func assignRootDelegates(_ viewControllers: [UIViewController]) {
        viewControllers.forEach { viewController in
            guard let viewController = viewController as? HomepageRootViewController else {
                return
            }
            
            viewController.delegate = self
        }
    }
}

extension HomepageViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        setNavigationBarHidden(viewController === rootViewController, animated: false)
    }
}

extension HomepageViewController: HomepageRootViewControllerDelegate {
    func homepageRootViewControllerDidSelectFavorite(_ favorite: BookmarkSnapshot) {
        homepageDelegate?.homepageViewControllerDidSelectFavorite(favorite)
    }
    
    func homepageRootViewControllerDidSelectPerformanceGuide(_ controller: HomepageRootViewController) {
        homepageDelegate?.homepageViewControllerDidSelectPerformanceGuide(self)
    }
    
    func homepageRootViewControllerDidSelectPerformanceSettings(_ controller: HomepageRootViewController) {
        homepageDelegate?.homepageViewControllerDidSelectPerformanceSettings(self)
    }
    
    func homepageRootViewControllerDidSelectFolder(_ folder: BookmarkFolderSnapshot) {
        let viewController = makeFolderRootViewController(folder: folder)
        setNavigationBarHidden(false, animated: false)
        pushViewController(viewController, animated: true)
    }
    
    func homepageRootViewControllerDidStartScrolling() {
        homepageDelegate?.homepageViewControllerDidStartScrolling()
    }
}
