//
//  HomepageRootViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

protocol HomepageRootViewControllerDelegate: AnyObject {
    func homepageRootViewControllerDidSelectFavorite(_ favorite: BookmarkSnapshot)
    func homepageRootViewControllerDidSelectFolder(_ folder: BookmarkFolderSnapshot)
    func homepageRootViewControllerDidSelectPerformanceGuide(_ controller: HomepageRootViewController)
    func homepageRootViewControllerDidSelectPerformanceSettings(_ controller: HomepageRootViewController)
    func homepageRootViewControllerDidStartScrolling()
}

protocol HomepageRecommendationViewController: UIViewController {
    func setContentMode(_ contentMode: HomepageContentMode)
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool)
}

final class HomepageRootViewController: UIViewController {
    private enum UX {
        static let topInset: CGFloat = 48
        static let folderTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 16
        static let bottomInset: CGFloat = 24
    }
    
    weak var delegate: HomepageRootViewControllerDelegate?
    
    private let bookmarkStore: BookmarkStore
    private let folder: BookmarkFolderSnapshot?
    private let sections: [HomepageSection]
    private var isPrivateBrowsing: Bool
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var sectionViewControllers: [HomepageSection: UIViewController] = [:]
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.keyboardDismissMode = .none
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()
    
    private let sectionStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        return stackView
    }()
    
    // MARK: - Lifecycle
    
    init(
        bookmarkStore: BookmarkStore,
        folder: BookmarkFolderSnapshot? = nil,
        sections: [HomepageSection] = HomepageSection.allCases,
        isPrivateBrowsing: Bool = false
    ) {
        self.bookmarkStore = bookmarkStore
        self.folder = folder
        self.sections = sections
        self.isPrivateBrowsing = isPrivateBrowsing
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder?.title
        configureScrollView()
        configureHierarchy()
        configureConstraints()
        configureSections()
    }
    
    // MARK: - Public API
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        recommendationViewControllers.forEach { viewController in
            viewController.setContentMode(contentMode)
        }
        privateBrowsingSectionViewController?.setContentMode(contentMode)
        favoritesSectionViewController?.setContentMode(contentMode)
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        recommendationViewControllers.forEach { viewController in
            viewController.setPrivateBrowsing(isPrivateBrowsing)
        }
        privateBrowsingSectionViewController?.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    func resetScrollPosition() {
        loadViewIfNeeded()
        scrollView.setContentOffset(
            CGPoint(x: 0, y: -scrollView.adjustedContentInset.top),
            animated: false
        )
    }
    
    // MARK: - Configuration
    
    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: topContentInset,
            left: 0,
            bottom: UX.bottomInset,
            right: 0
        )
        scrollView.scrollIndicatorInsets = scrollView.contentInset
    }
    
    private func configureHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(sectionStackView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            sectionStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            sectionStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: UX.horizontalInset),
            sectionStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -UX.horizontalInset),
            sectionStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            sectionStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(UX.horizontalInset * 2)),
        ])
    }
    
    private func configureSections() {
        sections.forEach { section in
            let viewController = makeSectionViewController(for: section)
            addChild(viewController)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            sectionStackView.addArrangedSubview(viewController.view)
            viewController.didMove(toParent: self)
            sectionViewControllers[section] = viewController
        }
    }
    
    private func makeSectionViewController(for section: HomepageSection) -> UIViewController {
        switch section {
        case .recommendation(.performance):
            let viewController = PerformanceRecommendationViewController()
            viewController.delegate = self
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .recommendation(.donation):
            return UIViewController()
            
        case .privateBrowsing:
            let viewController = PrivateBrowsingSectionViewController()
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .favorites:
            let viewController = FavoritesSectionViewController(
                bookmarkStore: bookmarkStore,
                folder: folder,
                showsTitle: showsSectionTitles
            )
            viewController.delegate = self
            viewController.setContentMode(contentMode)
            return viewController
        }
    }
    
    // MARK: - Helpers
    
    private var recommendationViewControllers: [HomepageRecommendationViewController] {
        return sectionViewControllers.compactMap { section, viewController in
            guard case .recommendation = section else {
                return nil
            }
            
            return viewController as? HomepageRecommendationViewController
        }
    }
    
    private var privateBrowsingSectionViewController: PrivateBrowsingSectionViewController? {
        return sectionViewControllers[.privateBrowsing] as? PrivateBrowsingSectionViewController
    }
    
    private var favoritesSectionViewController: FavoritesSectionViewController? {
        return sectionViewControllers[.favorites] as? FavoritesSectionViewController
    }
    
    private var isFolderRoot: Bool {
        return folder != nil
    }
    
    private var topContentInset: CGFloat {
        return isFolderRoot ? UX.folderTopInset : UX.topInset
    }
    
    private var showsSectionTitles: Bool {
        return !isFolderRoot
    }
}

extension HomepageRootViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.homepageRootViewControllerDidStartScrolling()
    }
}

extension HomepageRootViewController: FavoritesSectionViewControllerDelegate {
    func favoritesSectionViewController(_ controller: FavoritesSectionViewController, didSelectFavorite favorite: BookmarkSnapshot) {
        delegate?.homepageRootViewControllerDidSelectFavorite(favorite)
    }
    
    func favoritesSectionViewController(_ controller: FavoritesSectionViewController, didSelectFolder folder: BookmarkFolderSnapshot) {
        delegate?.homepageRootViewControllerDidSelectFolder(folder)
    }
}

extension HomepageRootViewController: PerformanceRecommendationViewControllerDelegate {
    func performanceRecommendationViewControllerDidSelectGuide(_ controller: PerformanceRecommendationViewController) {
        delegate?.homepageRootViewControllerDidSelectPerformanceGuide(self)
    }
    
    func performanceRecommendationViewControllerDidSelectSettings(_ controller: PerformanceRecommendationViewController) {
        delegate?.homepageRootViewControllerDidSelectPerformanceSettings(self)
    }
}
