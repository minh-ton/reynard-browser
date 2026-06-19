//
//  SidebarMenuViewController.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

final class SidebarMenuViewController: UIViewController, UICollectionViewDelegate, UINavigationControllerDelegate {
    private enum UX {
        static let topContentInset: CGFloat = 32
        static let legacyItemHeight: CGFloat = 48
        static let collapseButtonSize: CGFloat = 30
    }
    
    private let mainSection = "main"
    private let cellReuseIdentifier = "SidebarActionCell"
    private var dataSource: UICollectionViewDiffableDataSource<String, LibrarySection>!
    
    private lazy var collapseButton: UIButton = {
        let button = ToolbarButton(buttonType: .sidebar, target: self, action: #selector(collapseFromRoot))
        button.widthAnchor.constraint(equalToConstant: UX.collapseButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: UX.collapseButtonSize).isActive = true
        return button
    }()
    
    private lazy var collectionView: UICollectionView = {
        let layout: UICollectionViewLayout
        if #available(iOS 14.0, *) {
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.backgroundColor = .systemGray6
            layout = UICollectionViewCompositionalLayout.list(using: configuration)
        } else {
            let flowLayout = UICollectionViewFlowLayout()
            flowLayout.itemSize = CGSize(width: 1, height: UX.legacyItemHeight)
            flowLayout.minimumLineSpacing = 0
            flowLayout.sectionInset = .zero
            layout = flowLayout
        }
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        view.delegate = self
        return view
    }()
    
    // MARK: - Lifecycle
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if (splitViewController as? SidebarViewController)?.showChromeSidebarButton == true {
            navigationItem.leftBarButtonItem = nil
        } else {
            configureCollapseButton(collapseButton)
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: collapseButton)
        }
        navigationItem.rightBarButtonItem = nil
    }
    
    // MARK: - UINavigationControllerDelegate
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let showChromeSidebarButton = (splitViewController as? SidebarViewController)?.showChromeSidebarButton == true
        if viewController === self {
            if showChromeSidebarButton {
                navigationItem.leftBarButtonItem = nil
            } else {
                configureCollapseButton(collapseButton)
                navigationItem.leftBarButtonItem = UIBarButtonItem(customView: collapseButton)
            }
            navigationItem.rightBarButtonItem = nil
            return
        }
        
        guard !showChromeSidebarButton else {
            viewController.navigationItem.rightBarButtonItem = nil
            return
        }
        
        let button = makeCollapseButton(action: #selector(collapseFromChild(_:)))
        configureCollapseButton(button)
        viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button)
    }
    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let section = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        
        showSection(section, animated: true)
    }
    
    // MARK: - Sections
    
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
            contentViewController = BookmarksViewController()
        case .history:
            contentViewController = HistoryViewController()
        case .downloads:
            contentViewController = DownloadsViewController()
        case .settings:
            contentViewController = SettingsViewController()
        }
        
        return SidebarDetailViewController(
            title: section.title,
            contentViewController: contentViewController
        )
    }
    
    // MARK: - Actions
    
    @objc private func collapseFromRoot() {
        (splitViewController as? SidebarViewController)?.setVisible(false)
    }
    
    @objc private func collapseFromChild(_ sender: UIButton) {
        (splitViewController as? SidebarViewController)?.collapse(from: sender)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        view.backgroundColor = .systemGray6
    }
    
    private func configureCollectionView() {
        collectionView.contentInset.top = UX.topContentInset
        collectionView.verticalScrollIndicatorInsets.top = UX.topContentInset
        collectionView.register(SidebarActionCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func configureDataSource() {
        if #available(iOS 14.0, *) {
            let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, LibrarySection> { cell, _, section in
                var content = cell.defaultContentConfiguration()
                content.text = section.title
                content.image = UIImage(named: section.symbolName)
                content.imageProperties.tintColor = .label
                cell.contentConfiguration = content
                cell.accessories = []
            }
            
            dataSource = UICollectionViewDiffableDataSource<String, LibrarySection>(collectionView: collectionView) { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            }
            return
        }
        
        dataSource = UICollectionViewDiffableDataSource<String, LibrarySection>(collectionView: collectionView) { collectionView, indexPath, item in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: self.cellReuseIdentifier, for: indexPath)
            if let sidebarCell = cell as? SidebarActionCell {
                sidebarCell.configure(title: item.title, symbolName: item.symbolName)
            }
            return cell
        }
    }
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, LibrarySection>()
        snapshot.appendSections([mainSection])
        snapshot.appendItems(LibrarySection.allCases, toSection: mainSection)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func makeCollapseButton(action: Selector) -> UIButton {
        let button = ToolbarButton(buttonType: .sidebar, target: self, action: action)
        button.widthAnchor.constraint(equalToConstant: UX.collapseButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: UX.collapseButtonSize).isActive = true
        return button
    }
    
    private func configureCollapseButton(_ button: UIButton) {
        button.setImage(splitViewController?.displayModeButtonItem.image ?? UIImage(named: "reynard.sidebar.left"), for: .normal)
        button.accessibilityLabel = splitViewController?.displayModeButtonItem.accessibilityLabel
    }
}
