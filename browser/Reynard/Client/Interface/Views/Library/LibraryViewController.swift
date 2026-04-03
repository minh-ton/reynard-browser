//
//  LibraryViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class LibraryViewController: UITabBarController, UITabBarControllerDelegate, UINavigationControllerDelegate {
    private let initialSection: LibrarySection
    private let onClose: (() -> Void)?
    
    init(initialSection: LibrarySection = .bookmarks, onClose: (() -> Void)? = nil) {
        self.initialSection = initialSection
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
        selectedIndex = initialSection.rawValue
        LibraryTabBarStyle.apply(to: tabBar)
        if onClose != nil {
            navigationItem.rightBarButtonItem = makeCloseBarButtonItem()
        }
        updateNavigationTitle()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard onClose != nil else {
            return
        }
        
        viewController.navigationItem.rightBarButtonItem = makeCloseBarButtonItem()
    }
    
    private func makeSectionViewControllers() -> [UIViewController] {
        [
            makeSectionViewController(for: .bookmarks, contentViewController: LibraryHostedSectionViewController(hostedViewFactory: { BookmarksManagerView() })),
            makeSectionViewController(for: .history, contentViewController: LibraryHostedSectionViewController(hostedViewFactory: { HistoryManagerView() })),
            makeSectionViewController(for: .downloads, contentViewController: LibraryHostedSectionViewController(hostedViewFactory: { DownloadsManagerView() })),
            makeSectionViewController(for: .settings, contentViewController: SettingsRootViewController()),
        ]
    }
    
    private func makeSectionViewController(for section: LibrarySection, contentViewController: UIViewController) -> UIViewController {
        contentViewController.tabBarItem = section.tabBarItem
        return contentViewController
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateNavigationTitle()
    }
    
    private func updateNavigationTitle() {
        guard let section = LibrarySection(rawValue: selectedIndex) else {
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
            hostedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}
