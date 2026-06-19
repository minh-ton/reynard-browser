//
//  LibraryViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class LibraryViewController: UITabBarController, UITabBarControllerDelegate, UINavigationControllerDelegate {
    private let initialSection: LibrarySection
    private let isPrivateMode: Bool
    private let onClose: (() -> Void)?
    
    private var visibleSections: [LibrarySection] {
        return isPrivateMode ? LibrarySection.allCases.filter { $0 != .history } : LibrarySection.allCases
    }
    
    // MARK: - Lifecycle
    
    init(initialSection: LibrarySection = .bookmarks, isPrivateMode: Bool = false, onClose: (() -> Void)? = nil) {
        self.initialSection = initialSection
        self.isPrivateMode = isPrivateMode
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        installSections()
        installCloseButtonIfNeeded()
        observeAppUpdateBadge()
        updateNavigationTitle()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        removeNavigationActionsIfNeeded()
    }
    
    // MARK: - Delegates
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard onClose != nil else {
            return
        }
        
        viewController.navigationItem.rightBarButtonItem = makeCloseButton()
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateNavigationTitle()
        removeNavigationActionsIfNeeded()
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        view.backgroundColor = .systemGroupedBackground
        delegate = self
        LibraryTabBarStyle.apply(to: tabBar)
    }
    
    private func installSections() {
        setViewControllers(makeViewControllers(), animated: false)
        let selectedSection = visibleSections.contains(initialSection) ? initialSection : .bookmarks
        selectedIndex = visibleSections.firstIndex(of: selectedSection) ?? 0
    }
    
    private func installCloseButtonIfNeeded() {
        guard onClose != nil else {
            return
        }
        
        navigationItem.rightBarButtonItem = makeCloseButton()
    }
    
    private func observeAppUpdateBadge() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(markSettingsUpdateAvailable),
            name: .appUpdateAvailable,
            object: nil
        )
        if BrowserUpdates.shared.hasUpdate {
            markSettingsUpdateAvailable()
        }
    }
    
    private func makeViewControllers() -> [UIViewController] {
        visibleSections.map { section in
            let sectionController: UIViewController
            switch section {
            case .bookmarks:
                sectionController = BookmarksViewController()
            case .history:
                sectionController = HistoryViewController()
            case .downloads:
                sectionController = DownloadsViewController()
            case .settings:
                sectionController = SettingsViewController()
            }
            sectionController.tabBarItem = section.tabBarItem
            return sectionController
        }
    }
    
    // MARK: - Navigation
    
    private func updateNavigationTitle() {
        guard let tag = viewControllers?[safe: selectedIndex]?.tabBarItem.tag,
              let section = LibrarySection(rawValue: tag) else {
            title = nil
            return
        }
        
        title = section.title
    }
    
    private func removeNavigationActionsIfNeeded() {
        guard !selectedSectionHasNavigationAction else {
            return
        }
        
        LibraryActionButton.removeNavigationActions(from: navigationItem)
    }
    
    private var selectedSectionHasNavigationAction: Bool {
        guard #available(iOS 26.0, *),
              let selectedTag = viewControllers?[safe: selectedIndex]?.tabBarItem.tag else {
            return false
        }
        
        return selectedTag == LibrarySection.bookmarks.rawValue ||
        selectedTag == LibrarySection.history.rawValue ||
        selectedTag == LibrarySection.downloads.rawValue
    }
    
    @objc private func closeLibrary() {
        onClose?()
    }
    
    private func makeCloseButton() -> UIBarButtonItem {
        if #available(iOS 26.0, *) {
            let button = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeLibrary)
            )
            button.tintColor = .label
            return button
        }
        
        return UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeLibrary)
        )
    }
    
    // MARK: - Badges
    
    @objc private func markSettingsUpdateAvailable() {
        viewControllers?.first { viewController in
            viewController.tabBarItem.tag == LibrarySection.settings.rawValue
        }?.tabBarItem.badgeValue = ""
    }
}
