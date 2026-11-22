//
//  HomepageViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

protocol HomepageViewControllerDelegate: AnyObject {
    func homepageViewController(_ controller: HomepageViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition)
    func homepageViewController(
        _ controller: HomepageViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    )
    func homepageViewController(_ controller: HomepageViewController, didRequestHideFromSuggestions siteID: Int64)
    func homepageViewController(_ controller: HomepageViewController, didSelectRecentlyClosedTab id: UUID)
    func homepageViewControllerDidSelectSettings(_ controller: HomepageViewController)
    func homepageViewControllerDidStartScrolling()
}

final class HomepageViewController: UINavigationController {
    weak var homepageDelegate: HomepageViewControllerDelegate?
    
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
        viewControllers.forEach { viewController in
            guard let viewController = viewController as? HomepageRootViewController else {
                return
            }
            viewController.delegate = self
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

extension HomepageViewController: HomepageRootViewControllerDelegate {
    func homepageRootViewController(_ controller: HomepageRootViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition) {
        homepageDelegate?.homepageViewController(self, didRequestOpenURL: url, disposition: disposition)
    }
    
    func homepageRootViewController(
        _ controller: HomepageRootViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    ) {
        homepageDelegate?.homepageViewController(
            self,
            didRequestShareURL: url,
            sourceView: sourceView
        )
    }
    
    func homepageRootViewController(_ controller: HomepageRootViewController, didRequestHideFromSuggestions siteID: Int64) {
        homepageDelegate?.homepageViewController(self, didRequestHideFromSuggestions: siteID)
    }
    
    func homepageRootViewController(_ controller: HomepageRootViewController, didSelectRecentlyClosedTab id: UUID) {
        homepageDelegate?.homepageViewController(self, didSelectRecentlyClosedTab: id)
    }
    
    func homepageRootViewControllerDidSelectSettings(_ controller: HomepageRootViewController) {
        homepageDelegate?.homepageViewControllerDidSelectSettings(self)
    }
    
    func homepageRootViewControllerDidSelectFolder(_ folder: BookmarkFolderSnapshot) {
        let viewController = HomepageRootViewController(
            bookmarkStore: bookmarkStore,
            folder: folder,
            sections: [.favorites],
            isPrivateBrowsing: isPrivateBrowsing
        )
        viewController.delegate = self
        viewController.setContentMode(contentMode)
        viewController.setVisibleContentInsets(visibleContentInsets)
        setNavigationBarHidden(false, animated: false)
        pushViewController(viewController, animated: true)
    }
    
    func homepageRootViewControllerDidStartScrolling() {
        homepageDelegate?.homepageViewControllerDidStartScrolling()
    }
}
