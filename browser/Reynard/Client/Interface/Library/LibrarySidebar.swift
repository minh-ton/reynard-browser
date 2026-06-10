//
//  LibrarySidebar.swift
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

import UIKit

final class LibrarySidebarViewController: UIViewController, UICollectionViewDelegate, UINavigationControllerDelegate {
    private let mainSection = "main"
    private let cellReuseIdentifier = "LibrarySidebarCell"
    private var dataSource: UICollectionViewDiffableDataSource<String, LibrarySection>!
    private lazy var sidebarButton = makeLibrarySidebarButton(target: self, action: #selector(collapseSidebarFromRoot))
    
    private lazy var collectionView: UICollectionView = {
        let layout: UICollectionViewLayout
        if #available(iOS 14.0, *) {
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.backgroundColor = .systemGray6
            layout = UICollectionViewCompositionalLayout.list(using: configuration)
        } else {
            let flowLayout = UICollectionViewFlowLayout()
            flowLayout.itemSize = CGSize(width: 1, height: 48)
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
        collectionView.register(LibrarySidebarCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
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
                content.image = UIImage(systemName: section.symbolName)
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
            if let sidebarCell = cell as? LibrarySidebarCell {
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

private final class LibrarySidebarCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .label
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        contentView.addSubview(iconView)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(title: String, symbolName: String) {
        titleLabel.text = title
        iconView.image = UIImage(systemName: symbolName)
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
        
        NSLayoutConstraint.activate([
            contentViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

final class LibraryEmptyBackgroundView: UIView {
    private var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != contentInsets else {
                return
            }
            
            setNeedsLayout()
        }
    }
    
    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    var message: String? {
        get {
            label.text
        }
        set {
            label.text = newValue
            setNeedsLayout()
        }
    }
    
    init(message: String) {
        super.init(frame: .zero)
        label.text = message
        addSubview(label)
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateContentInsets(from tableView: UITableView) {
        let contentFrame = tableView.layoutMarginsGuide.layoutFrame
        contentInsets = UIEdgeInsets(
            top: 0,
            left: contentFrame.minX,
            bottom: 0,
            right: max(tableView.bounds.width - contentFrame.maxX, 0)
        )
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let availableWidth = max(bounds.width - contentInsets.left - contentInsets.right, 0)
        let fittingSize = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = label.sizeThatFits(fittingSize)
        label.frame = CGRect(
            x: contentInsets.left,
            y: (bounds.height - labelSize.height) / 2,
            width: availableWidth,
            height: labelSize.height
        ).integral
    }
}
