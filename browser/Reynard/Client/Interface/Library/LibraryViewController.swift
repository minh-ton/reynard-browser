//
//  LibraryViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

enum LibrarySection: Int, CaseIterable {
    case bookmarks
    case history
    case downloads
    case settings
    
    var title: String {
        switch self {
        case .bookmarks:
            return "Bookmarks"
        case .history:
            return "History"
        case .downloads:
            return "Downloads"
        case .settings:
            return "Settings"
        }
    }
    
    var symbolName: String {
        switch self {
        case .bookmarks:
            return "book"
        case .history:
            return "clock"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gearshape"
        }
    }
    
    var selectedSymbolName: String {
        switch self {
        case .bookmarks:
            return "book.fill"
        case .history:
            return "clock.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
    
    var tabBarItem: UITabBarItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let item = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbolName, withConfiguration: configuration),
            selectedImage: UIImage(systemName: selectedSymbolName, withConfiguration: configuration)
        )
        item.tag = rawValue
        return item
    }
}

private enum LibraryTabBarStyle {
    static func apply(to tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .regular)]
        
        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = .secondaryLabel
            itemAppearance.normal.titleTextAttributes = titleAttributes.merging([.foregroundColor: UIColor.secondaryLabel]) { _, new in new }
            itemAppearance.selected.iconColor = .label
            itemAppearance.selected.titleTextAttributes = titleAttributes.merging([.foregroundColor: UIColor.label]) { _, new in new }
        }
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
    }
}

final class LibraryViewController: UITabBarController, UITabBarControllerDelegate, UINavigationControllerDelegate {
    private let initialSection: LibrarySection
    private let isPrivateMode: Bool
    private let onClose: (() -> Void)?
    private var visibleSections: [LibrarySection] {
        isPrivateMode ? LibrarySection.allCases.filter { $0 != .history } : LibrarySection.allCases
    }
    
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
        view.backgroundColor = .systemGroupedBackground
        delegate = self
        setViewControllers(makeSectionViewControllers(), animated: false)
        let selectedSection = visibleSections.contains(initialSection) ? initialSection : .bookmarks
        selectedIndex = visibleSections.firstIndex(of: selectedSection) ?? 0
        LibraryTabBarStyle.apply(to: tabBar)
        if onClose != nil {
            navigationItem.rightBarButtonItem = makeCloseBarButtonItem()
        }
        updateNavigationTitle()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applySettingsTabBadge),
            name: AppUpdates.updateAvailableNotification,
            object: nil
        )
        if AppUpdates.shared.hasUpdate {
            applySettingsTabBadge()
        }
    }
    
    @objc private func applySettingsTabBadge() {
        viewControllers?.first { viewController in
            viewController.tabBarItem.tag == LibrarySection.settings.rawValue
        }?.tabBarItem.badgeValue = ""
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        
        let selectedTag = viewControllers?[safe: selectedIndex]?.tabBarItem.tag
        let keepsLibraryActionsButton: Bool
        if #available(iOS 26.0, *) {
            keepsLibraryActionsButton = MakeButtons.hasLiquidGlass && (
                selectedTag == LibrarySection.bookmarks.rawValue ||
                selectedTag == LibrarySection.history.rawValue ||
                selectedTag == LibrarySection.downloads.rawValue
            )
        } else {
            keepsLibraryActionsButton = false
        }
        
        if !keepsLibraryActionsButton {
            MakeButtons.removeLibraryActionBarButtons(from: navigationItem)
        }
    }
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard onClose != nil else {
            return
        }
        
        viewController.navigationItem.rightBarButtonItem = makeCloseBarButtonItem()
    }
    
    private func makeSectionViewControllers() -> [UIViewController] {
        visibleSections.map { section in
            let contentViewController: UIViewController
            switch section {
            case .bookmarks:
                contentViewController = LibraryHostedSectionViewController(hostedViewFactory: { BookmarksManagerView() })
            case .history:
                contentViewController = LibraryHostedSectionViewController(hostedViewFactory: { HistoryManagerView() })
            case .downloads:
                contentViewController = LibraryHostedSectionViewController(hostedViewFactory: { DownloadsManagerView() })
            case .settings:
                contentViewController = LibraryHostedSectionViewController(hostedViewFactory: { SettingsView() })
            }
            contentViewController.tabBarItem = section.tabBarItem
            return contentViewController
        }
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateNavigationTitle()
        
        let selectedTag = viewController.tabBarItem.tag
        if #available(iOS 26.0, *),
           MakeButtons.hasLiquidGlass,
           (selectedTag == LibrarySection.bookmarks.rawValue ||
            selectedTag == LibrarySection.history.rawValue ||
            selectedTag == LibrarySection.downloads.rawValue) {
            return
        }
        
        MakeButtons.removeLibraryActionBarButtons(from: navigationItem)
    }
    
    private func updateNavigationTitle() {
        guard let tag = viewControllers?[safe: selectedIndex]?.tabBarItem.tag,
              let section = LibrarySection(rawValue: tag) else {
            title = nil
            return
        }
        
        title = section.title
    }
    
    @objc private func dismissLibraryMenu() {
        onClose?()
    }
    
    private func makeCloseBarButtonItem() -> UIBarButtonItem {
        if #available(iOS 26.0, *) {
            let button = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(dismissLibraryMenu)
            )
            button.tintColor = .label
            return button
        }
        
        return UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissLibraryMenu)
        )
    }
}

private final class LibraryHostedSectionViewController: UIViewController {
    private let hostedViewFactory: () -> UIView
    
    init(hostedViewFactory: @escaping () -> UIView) {
        self.hostedViewFactory = hostedViewFactory
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGray6
        
        let hostedView = hostedViewFactory()
        
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostedView)
        
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
