//
//  HomepageViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

final class HomepageViewController: UINavigationController {
    weak var homepageDelegate: HomepageSectionDelegate? {
        didSet {
            rootViewController.delegate = homepageDelegate
        }
    }
    
    private let rootViewController: HomepageRootViewController
    private let bookmarkStore: BookmarkStore
    private var isPrivateBrowsing: Bool
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var visibleContentInsets: UIEdgeInsets = .zero
    private var showsBackground = false
    
    // MARK: - Lifecycle
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 26.0, *) {
            return .default
        }
        return super.preferredStatusBarStyle
    }
    
    init(bookmarkStore: BookmarkStore = .shared, isPrivateBrowsing: Bool = false) {
        self.bookmarkStore = bookmarkStore
        self.isPrivateBrowsing = isPrivateBrowsing
        rootViewController = HomepageRootViewController(
            bookmarkStore: bookmarkStore,
            isPrivateBrowsing: isPrivateBrowsing
        )
        super.init(rootViewController: rootViewController)
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
        viewControllers.forEach { viewController in
            guard let viewController = viewController as? HomepageRootViewController else {
                return
            }
            viewController.delegate = homepageDelegate
            viewController.setVisibleContentInsets(visibleContentInsets)
        }
    }
    
    // MARK: - Public API
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        self.contentMode = contentMode
        viewControllers.forEach { viewController in
            (viewController as? HomepageRootViewController)?.setContentMode(contentMode)
        }
        if isViewLoaded {
            updateNavigationBarAppearance()
        }
    }
    
    func setShowsBackground(_ showsBackground: Bool) {
        self.showsBackground = showsBackground
        updateBackgroundColor()
    }
    
    func setVisibleContentInsets(_ visibleContentInsets: UIEdgeInsets) {
        guard self.visibleContentInsets != visibleContentInsets else {
            return
        }
        
        self.visibleContentInsets = visibleContentInsets
        viewControllers.forEach { viewController in
            (viewController as? HomepageRootViewController)?.setVisibleContentInsets(visibleContentInsets)
        }
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        viewControllers.forEach { viewController in
            (viewController as? HomepageRootViewController)?.setPrivateBrowsing(isPrivateBrowsing)
        }
    }
    
    func prepareForPresentation(resetNavigation: Bool) {
        loadViewIfNeeded()
        if resetNavigation {
            popToRootViewController(animated: false)
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    func showFolder(_ folder: BookmarkFolderSnapshot) {
        let viewController = HomepageRootViewController(
            bookmarkStore: bookmarkStore,
            folder: folder,
            sections: [.favorites],
            isPrivateBrowsing: isPrivateBrowsing
        )
        viewController.delegate = homepageDelegate
        viewController.setContentMode(contentMode)
        viewController.setVisibleContentInsets(visibleContentInsets)
        setNavigationBarHidden(false, animated: false)
        pushViewController(viewController, animated: true)
    }
    
    // MARK: - Thumbnail
    
    func makeThumbnail(size: CGSize, visibleRect: CGRect) -> UIImage {
        setVisibleContentInsets(UIEdgeInsets(
            top: max(0, visibleRect.minY),
            left: 0,
            bottom: max(0, size.height - visibleRect.maxY),
            right: 0
        ))
        
        let originalFrame = view.frame
        let originalBounds = view.bounds
        let isTemporarilyAttached = view.superview == nil
        
        if isTemporarilyAttached {
            let captureContainer = UIView(frame: CGRect(origin: .zero, size: size))
            captureContainer.addSubview(view)
            view.frame = captureContainer.bounds
            captureContainer.layoutIfNeeded()
        } else {
            view.bounds.size = size
        }
        view.layoutIfNeeded()
        
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        }
        
        if isTemporarilyAttached {
            view.removeFromSuperview()
        }
        
        view.bounds = originalBounds
        view.frame = originalFrame
        view.layoutIfNeeded()
        return image
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        updateBackgroundColor()
        delegate = self
        updateNavigationBarAppearance()
        navigationBar.isTranslucent = true
        setNavigationBarHidden(true, animated: false)
    }
    
    private func updateNavigationBarAppearance() {
        let foregroundColor = HomepageWallpaper.foregroundColor(for: contentMode)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: foregroundColor]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = foregroundColor
    }
    
    private func updateBackgroundColor() {
        view.backgroundColor = showsBackground ? .systemBackground : .clear
    }
}

extension HomepageViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateNavigationBarAppearance()
        setNavigationBarHidden(viewController === rootViewController, animated: false)
    }
}
