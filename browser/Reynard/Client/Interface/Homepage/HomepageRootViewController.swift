//
//  HomepageRootViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

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
        static let embeddedMaximumWidth: CGFloat = 800
        static let detachedMaximumWidth: CGFloat = 700
    }
    
    private weak var delegate: HomepageSectionDelegate?
    private let bookmarkStore: BookmarkStore
    private let folder: BookmarkFolderSnapshot?
    private let sections: [HomepageSection]
    private var isPrivateBrowsing: Bool
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var visibleContentInsets: UIEdgeInsets = .zero
    private var sectionViewControllers: [HomepageSection: UIViewController] = [:]
    private var sectionStackWidthConstraint: NSLayoutConstraint?
    
    private let wallpaperImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()
    
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
        delegate: HomepageSectionDelegate?,
        bookmarkStore: BookmarkStore,
        folder: BookmarkFolderSnapshot? = nil,
        sections: [HomepageSection] = HomepageSection.allCases,
        isPrivateBrowsing: Bool = false
    ) {
        self.delegate = delegate
        self.bookmarkStore = bookmarkStore
        self.folder = folder
        self.sections = sections
        self.isPrivateBrowsing = isPrivateBrowsing
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder?.title
        observeHomepageSettings()
        configureScrollView()
        configureHierarchy()
        configureConstraints()
        configureSections()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSectionStackWidth()
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateScrollInsets()
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
        frequentlyVisitedSectionViewController?.setContentMode(contentMode)
        recentlyClosedTabsSectionViewController?.setContentMode(contentMode)
        if isViewLoaded {
            updateWallpaper()
            updateScrollInsets()
        }
        updateSectionStackWidth()
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        guard isViewLoaded else {
            return
        }
        
        if folder == nil {
            reloadSections()
            return
        }
        
        recommendationViewControllers.forEach { viewController in
            viewController.setPrivateBrowsing(isPrivateBrowsing)
        }
        privateBrowsingSectionViewController?.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    func setVisibleContentInsets(_ visibleContentInsets: UIEdgeInsets) {
        guard self.visibleContentInsets != visibleContentInsets else {
            return
        }
        
        self.visibleContentInsets = visibleContentInsets
        guard isViewLoaded else {
            return
        }
        updateScrollInsets()
    }
    
    // MARK: - Configuration
    
    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        updateScrollInsets()
    }
    
    private func updateScrollInsets() {
        let isAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top
        let effectiveVisibleContentInsets = contentMode.isDetached ? .zero : visibleContentInsets
        let topInset = folder == nil
        ? effectiveVisibleContentInsets.top + UX.topInset
        : max(effectiveVisibleContentInsets.top, view.safeAreaInsets.top) + UX.folderTopInset
        let contentInset = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: effectiveVisibleContentInsets.bottom + UX.bottomInset,
            right: 0
        )
        scrollView.contentInset = contentInset
        scrollView.scrollIndicatorInsets = contentInset
        if isAtTop {
            scrollView.contentOffset.y = -contentInset.top
        }
    }
    
    private func configureHierarchy() {
        view.addSubview(wallpaperImageView)
        view.addSubview(scrollView)
        scrollView.addSubview(sectionStackView)
        updateWallpaper()
    }
    
    private func configureConstraints() {
        let widthConstraint = sectionStackView.widthAnchor.constraint(equalToConstant: 1)
        sectionStackWidthConstraint = widthConstraint
        
        NSLayoutConstraint.activate([
            wallpaperImageView.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaperImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaperImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wallpaperImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            
            sectionStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            sectionStackView.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            sectionStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            widthConstraint,
        ])
    }
    
    private func configureSections() {
        displayedSections.forEach { section in
            let viewController = makeSectionViewController(for: section)
            addChild(viewController)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            sectionStackView.addArrangedSubview(viewController.view)
            viewController.didMove(toParent: self)
            sectionViewControllers[section] = viewController
        }
    }
    
    private func reloadSections() {
        sectionViewControllers.values.forEach { viewController in
            viewController.willMove(toParent: nil)
            sectionStackView.removeArrangedSubview(viewController.view)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
        }
        sectionViewControllers.removeAll(keepingCapacity: true)
        configureSections()
        updateSectionStackWidth()
    }
    
    private func makeSectionViewController(for section: HomepageSection) -> UIViewController {
        switch section {
        case .recommendation(.performance):
            let viewController = PerformanceRecommendationViewController()
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .recommendation(.updateAvailable):
            let viewController = UpdateAvailableViewController()
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .recommendation(.donation):
            let viewController = DonationRecommendationViewController()
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .privateBrowsing:
            let viewController = PrivateBrowsingSectionViewController()
            viewController.setContentMode(contentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .favorites:
            let viewController = FavoritesSectionViewController(
                bookmarkStore: bookmarkStore,
                folder: folder,
                showsSectionTitle: folder == nil
            )
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            return viewController
            
        case .frequentlyVisited:
            let viewController = FrequentlyVisitedSectionViewController()
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            return viewController
            
        case .recentlyClosedTabs:
            let viewController = RecentlyClosedTabsSectionViewController()
            viewController.delegate = delegate
            viewController.setContentMode(contentMode)
            return viewController
        }
    }
    
    // MARK: - Layout
    
    private func updateSectionStackWidth() {
        let width = scrollView.bounds.width - (UX.horizontalInset * 2)
        guard width > 0 else {
            return
        }
        
        let maximumWidth = contentMode.isDetached ? UX.detachedMaximumWidth : UX.embeddedMaximumWidth
        sectionStackWidthConstraint?.constant = min(width, maximumWidth)
    }
    
    private func updateWallpaper() {
        guard Prefs.HomepageSettings.showsWallpaper,
              !contentMode.isDetached else {
            wallpaperImageView.image = nil
            return
        }
        wallpaperImageView.image = HomepageWallpaper.image
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
    
    private var frequentlyVisitedSectionViewController: FrequentlyVisitedSectionViewController? {
        return sectionViewControllers[.frequentlyVisited] as? FrequentlyVisitedSectionViewController
    }
    
    private var recentlyClosedTabsSectionViewController: RecentlyClosedTabsSectionViewController? {
        return sectionViewControllers[.recentlyClosedTabs] as? RecentlyClosedTabsSectionViewController
    }
    
    private var displayedSections: [HomepageSection] {
        guard folder == nil else {
            return sections
        }
        
        return sections.filter { section in
            switch section {
            case .privateBrowsing:
                return isPrivateBrowsing
            case .favorites:
                return Prefs.HomepageSettings.showsFavorites &&
                (!isPrivateBrowsing || Prefs.HomepageSettings.showsFavoritesInPrivateBrowsing)
            case .frequentlyVisited:
                return Prefs.HomepageSettings.showsFrequentlyVisited &&
                (!isPrivateBrowsing || Prefs.HomepageSettings.showsFrequentlyVisitedInPrivateBrowsing)
            case .recentlyClosedTabs:
                return Prefs.HomepageSettings.showsRecentlyClosedTabs && !isPrivateBrowsing
            default:
                return true
            }
        }
    }
    
    private func observeHomepageSettings() {
        guard folder == nil else {
            return
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(homepageSettingsDidChange),
            name: .homepageSettingsDidChange,
            object: nil
        )
    }
    
    @objc private func homepageSettingsDidChange() {
        updateWallpaper()
        reloadSections()
    }
    
}

extension HomepageRootViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.homepageDidStartScrolling()
    }
}
