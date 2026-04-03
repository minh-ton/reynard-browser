//
//  LibrarySidebar.swift
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

import UIKit

final class LibrarySidebarViewController: UIViewController, UICollectionViewDelegate, UINavigationControllerDelegate {
    private let mainSection = "main"
    private var dataSource: UICollectionViewDiffableDataSource<String, LibrarySection>!
    private lazy var sidebarButton = makeLibrarySidebarButton(target: self, action: #selector(collapseSidebarFromRoot))
    
    private lazy var collectionView: UICollectionView = {
        var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
        configuration.backgroundColor = .systemGray6
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        view.delegate = self
        return view
    }()
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGray6
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        navigationController?.setNavigationBarHidden(false, animated: animated)
        SidebarToggleButtonConfiguration.configure(sidebarButton, in: splitViewController)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: sidebarButton)
        navigationItem.rightBarButtonItem = nil
    }
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if viewController === self {
            SidebarToggleButtonConfiguration.configure(sidebarButton, in: splitViewController)
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: sidebarButton)
            navigationItem.rightBarButtonItem = nil
            return
        }
        
        let button = makeLibrarySidebarButton(target: self, action: #selector(collapseSidebarFromAnyChild(_:)))
        SidebarToggleButtonConfiguration.configure(button, in: splitViewController)
        viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button)
    }
    
    private func configureCollectionView() {
        collectionView.contentInset.top = 32
        collectionView.verticalScrollIndicatorInsets.top = 32
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, LibrarySection> { cell, _, section in
            var content = cell.defaultContentConfiguration()
            content.text = section.title
            content.image = UIImage(systemName: section.symbolName)
            content.imageProperties.tintColor = .label
            cell.contentConfiguration = content
            cell.accessories = []
        }
        
        dataSource = UICollectionViewDiffableDataSource<String, LibrarySection>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, item: LibrarySection) in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, LibrarySection>()
        snapshot.appendSections([mainSection])
        snapshot.appendItems(LibrarySection.allCases, toSection: mainSection)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let section = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        
        showSection(section, animated: true)
    }
    
    func showSection(_ section: LibrarySection, animated: Bool) {
        loadViewIfNeeded()
        
        let indexPath = dataSource.indexPath(for: section)
        
        if let indexPath {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
        
        let viewController = makeSectionViewController(for: section)
        navigationController?.setViewControllers([self, viewController], animated: animated)
        if let indexPath {
            collectionView.deselectItem(at: indexPath, animated: animated)
        }
    }
    
    private func makeSectionViewController(for section: LibrarySection) -> UIViewController {
        let contentViewController: UIViewController
        
        switch section {
        case .bookmarks:
            contentViewController = LibrarySidebarHostedSectionViewController(hostedView: BookmarksManagerView())
        case .history:
            contentViewController = LibrarySidebarHostedSectionViewController(hostedView: HistoryManagerView())
        case .downloads:
            contentViewController = LibrarySidebarHostedSectionViewController(hostedView: DownloadsManagerView())
        case .settings:
            contentViewController = SettingsRootViewController()
        }
        
        return LibrarySidebarDetailViewController(
            title: section.title,
            contentViewController: contentViewController
        )
    }
    
    @objc private func collapseSidebarFromRoot() {
        (splitViewController as? BrowserSplitViewController)?.setLibrarySidebarVisible(false)
    }
    
    @objc private func collapseSidebarFromAnyChild(_ sender: UIButton) {
        (splitViewController as? BrowserSplitViewController)?.collapseLibrarySidebar(from: sender)
    }
}

private func makeLibrarySidebarButton(target: AnyObject, action: Selector) -> UIButton {
    let button = MakeButtons.makeToolbarButton(target: target, imageName: "sidebar.left", action: action)
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    return button
}

private final class LibrarySidebarHostedSectionViewController: UIViewController {
    private let hostedView: UIView
    
    init(hostedView: UIView) {
        self.hostedView = hostedView
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGray6
        
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

private final class LibrarySidebarDetailViewController: UIViewController {
    private let contentViewController: UIViewController
    private let detailTitle: String
    private let maximumContentWidth: CGFloat = 360
    
    init(title: String, contentViewController: UIViewController) {
        self.detailTitle = title
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = detailTitle
        
        addChild(contentViewController)
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentViewController.view)
        
        let safeArea = view.safeAreaLayoutGuide
        let fillWidthConstraint = contentViewController.view.widthAnchor.constraint(equalTo: safeArea.widthAnchor)
        fillWidthConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            contentViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentViewController.view.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            contentViewController.view.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor),
            contentViewController.view.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor),
            contentViewController.view.widthAnchor.constraint(lessThanOrEqualToConstant: maximumContentWidth),
            fillWidthConstraint,
        ])
        contentViewController.didMove(toParent: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.leftBarButtonItem = nil
    }
}
