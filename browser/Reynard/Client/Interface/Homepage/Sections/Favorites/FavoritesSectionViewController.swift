//
//  FavoritesSectionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

protocol FavoritesSectionViewControllerDelegate: HomepageSectionDelegate {
    func favoritesSectionViewController(_ controller: FavoritesSectionViewController, didSelectFolder folder: BookmarkFolderSnapshot)
}

final class FavoritesSectionViewController: UIViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let titleBottomSpacing: CGFloat = 3
        static let titleFontSize: CGFloat = 22
        static let reorderMinimumPressDuration: TimeInterval = 0.25
        static let contextMenuPresentationDelay: TimeInterval = 0.55
        static let reorderMovementThreshold: CGFloat = 8
        static let rowSpacing: CGFloat = 16
    }
    
    private enum ReorderState {
        case idle
        case pending(cell: UICollectionViewCell, indexPath: IndexPath, startLocation: CGPoint, workItem: DispatchWorkItem)
        case active(cell: UICollectionViewCell)
    }
    
    weak var delegate: FavoritesSectionViewControllerDelegate?
    
    private static let titleFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
        for: .systemFont(ofSize: UX.titleFontSize, weight: .bold)
    )
    
    private let bookmarkStore: BookmarkStore
    private let folder: BookmarkFolderSnapshot?
    private let showsSectionTitle: Bool
    private var allFavoriteItems: [BookmarkContentSnapshot] = []
    private var displayedFavoriteItems: [BookmarkContentSnapshot] = []
    private var favoritesFolderGUID: String?
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var showsExpandedFavorites = false
    private var collectionHeightConstraint: NSLayoutConstraint?
    private var lastLaidOutWidth: CGFloat = -1
    private var collectionMaskLayer: CALayer?
    private var reorderState: ReorderState = .idle
    private var contextMenuInteraction: UIContextMenuInteraction?
    
    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = FavoritesSectionViewController.titleFont
        label.textColor = .label
        label.text = NSLocalizedString("Favorites", comment: "")
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private lazy var showAllButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: #selector(showAllButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let collectionLayout = FavoritesCollectionViewLayout()
    
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            FavoriteSiteCollectionViewCell.self,
            forCellWithReuseIdentifier: FavoriteSiteCollectionViewCell.reuseIdentifier
        )
        collectionView.register(
            FavoriteFolderCollectionViewCell.self,
            forCellWithReuseIdentifier: FavoriteFolderCollectionViewCell.reuseIdentifier
        )
        return collectionView
    }()
    
    // MARK: - Lifecycle
    
    init(bookmarkStore: BookmarkStore = .shared, folder: BookmarkFolderSnapshot? = nil, showsSectionTitle: Bool = true) {
        self.bookmarkStore = bookmarkStore
        self.folder = folder
        self.showsSectionTitle = showsSectionTitle
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
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureGestures()
        observeBookmarks()
        reloadFavorites()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFavoriteGridLayout()
    }
    
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        applyFavoriteItemLimit()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        view.backgroundColor = .clear
        headerView.isHidden = !showsSectionTitle
    }
    
    private func configureHierarchy() {
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(showAllButton)
        view.addSubview(collectionView)
    }
    
    private func configureConstraints() {
        let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
        let collectionTopAnchor = showsSectionTitle ? headerView.bottomAnchor : view.topAnchor
        let collectionTopSpacing = showsSectionTitle ? UX.titleBottomSpacing : 0
        collectionHeightConstraint = heightConstraint
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: showAllButton.leadingAnchor, constant: -UX.horizontalInset),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            
            showAllButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            showAllButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            showAllButton.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor),
            
            collectionView.topAnchor.constraint(equalTo: collectionTopAnchor, constant: collectionTopSpacing),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,
        ])
    }
    
    private func configureGestures() {
        let reorderGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderLongPress(_:)))
        reorderGesture.minimumPressDuration = UX.reorderMinimumPressDuration
        reorderGesture.delegate = self
        collectionView.addGestureRecognizer(reorderGesture)
    }
    
    private func observeBookmarks() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarkStoreDidChange,
            object: nil
        )
    }
    
    // MARK: - Bookmarks
    
    private func reloadFavorites() {
        let contents: BookmarkFolderContentsSnapshot
        if let folder {
            contents = bookmarkStore.contents(of: folder.guid)
        } else {
            contents = bookmarkStore.favoritesFolderContents()
        }
        
        favoritesFolderGUID = contents.parent.guid
        allFavoriteItems = contents.items
        applyFavoriteItemLimit()
    }
    
    @objc private func bookmarksDidChange() {
        reloadFavorites()
    }
    
    // MARK: - Collection Animation
    
    private func applyFavoriteItemLimit() {
        if !hasExpandableFavorites {
            showsExpandedFavorites = false
        }
        
        displayedFavoriteItems = currentFavoriteItems()
        updateShowAllButton()
        collectionView.reloadData()
        view.isHidden = allFavoriteItems.isEmpty
        invalidateFavoriteLayout()
    }
    
    private func currentFavoriteItems() -> [BookmarkContentSnapshot] {
        guard folder == nil,
              !showsExpandedFavorites else {
            return allFavoriteItems
        }
        
        return Array(allFavoriteItems.prefix(collapsedFavoriteItemLimit))
    }
    
    private var collapsedFavoriteItemLimit: Int {
        return Prefs.HomepageSettings.favoriteRowCount * contentMode.favoriteColumnCount
    }
    
    private var hasExpandableFavorites: Bool {
        guard folder == nil else {
            return false
        }
        
        let columnCount = max(contentMode.favoriteColumnCount, 1)
        let rowCount = Int(ceil(CGFloat(allFavoriteItems.count) / CGFloat(columnCount)))
        return rowCount > Prefs.HomepageSettings.favoriteRowCount
    }
    
    private func updateShowAllButton() {
        let isHidden = !showsSectionTitle || !hasExpandableFavorites
        UIView.performWithoutAnimation {
            showAllButton.isHidden = isHidden
            showAllButton.setTitle(isHidden ? nil : (showsExpandedFavorites ? NSLocalizedString("Show Less", comment: "") : NSLocalizedString("Show All", comment: "")), for: .normal)
            showAllButton.layoutIfNeeded()
        }
    }
    
    @objc private func showAllButtonTapped() {
        guard hasExpandableFavorites else {
            return
        }
        
        let previousCount = displayedFavoriteItems.count
        showsExpandedFavorites.toggle()
        let updatedItems = currentFavoriteItems()
        let updatedCount = updatedItems.count
        updateShowAllButton()
        
        let indexPaths = indexPathsForItemCountChange(from: previousCount, to: updatedCount)
        
        if updatedCount > previousCount {
            showAdditionalFavorites(updatedItems, at: indexPaths)
        } else {
            hideAdditionalFavorites(updatedItems, at: indexPaths)
        }
    }
    
    private func showAdditionalFavorites(_ updatedItems: [BookmarkContentSnapshot], at indexPaths: [IndexPath]) {
        view.superview?.layoutIfNeeded()
        collectionView.performBatchUpdates {
            self.displayedFavoriteItems = updatedItems
            self.collectionLayout.invalidateLayout()
            self.updateFavoriteGridLayout()
            self.collectionView.insertItems(at: indexPaths)
            self.view.superview?.layoutIfNeeded()
        }
    }
    
    private func hideAdditionalFavorites(_ updatedItems: [BookmarkContentSnapshot], at indexPaths: [IndexPath]) {
        view.superview?.layoutIfNeeded()
        applyCollectionVerticalMask()
        collectionView.performBatchUpdates {
            self.displayedFavoriteItems = updatedItems
            self.collectionLayout.invalidateLayout()
            self.updateFavoriteGridLayout(itemCount: updatedItems.count)
            self.collectionView.deleteItems(at: indexPaths)
            self.view.superview?.layoutIfNeeded()
            self.updateCollectionVerticalMask()
        } completion: { [weak self] _ in
            self?.removeCollectionVerticalMask()
        }
    }
    
    private func indexPathsForItemCountChange(from previousCount: Int, to updatedCount: Int) -> [IndexPath] {
        let range = updatedCount > previousCount ? previousCount..<updatedCount : updatedCount..<previousCount
        return range.map { item in
            return IndexPath(item: item, section: 0)
        }
    }
    
    // MARK: - Layout
    
    private func invalidateFavoriteLayout() {
        lastLaidOutWidth = -1
        UIView.performWithoutAnimation {
            collectionLayout.invalidateLayout()
            view.setNeedsLayout()
        }
    }
    
    private func updateFavoriteGridLayout(itemCount: Int? = nil) {
        let width = collectionView.bounds.width
        guard width > 0 else {
            return
        }
        
        let metrics = FavoritesLayoutMetrics(
            width: width,
            columnCount: contentMode.favoriteColumnCount,
            horizontalInset: UX.horizontalInset,
            lineSpacing: UX.rowSpacing
        )
        if abs(lastLaidOutWidth - width) > 0.5
            || collectionLayout.metrics != metrics {
            lastLaidOutWidth = width
            collectionLayout.metrics = metrics
        }
        
        let displayedItemCount = itemCount ?? displayedFavoriteItems.count
        let rowCount = Int(ceil(CGFloat(displayedItemCount) / CGFloat(metrics.columnCount)))
        let contentHeight = metrics.contentHeight(rowCount: rowCount)
        guard abs((collectionHeightConstraint?.constant ?? 0) - contentHeight) > 0.5 else {
            return
        }
        
        collectionHeightConstraint?.constant = contentHeight
        updateCollectionVerticalMask()
    }
    
    private func applyCollectionVerticalMask() {
        let maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.black.cgColor
        collectionMaskLayer = maskLayer
        collectionView.layer.mask = maskLayer
        updateCollectionVerticalMask()
    }
    
    private func updateCollectionVerticalMask() {
        guard let collectionMaskLayer else {
            return
        }
        
        let horizontalOutset = FavoritesLayoutMetrics.shadowPadding
        collectionMaskLayer.frame = collectionView.bounds.insetBy(dx: -horizontalOutset, dy: 0)
    }
    
    private func removeCollectionVerticalMask() {
        collectionView.layer.mask = nil
        collectionMaskLayer = nil
    }
    
    // MARK: - Favorite Actions
    
    func favoriteItem(at indexPath: IndexPath) -> BookmarkContentSnapshot? {
        guard displayedFavoriteItems.indices.contains(indexPath.item) else {
            return nil
        }
        
        return displayedFavoriteItems[indexPath.item]
    }
    
    func favoriteItem(for cell: UICollectionViewCell) -> BookmarkContentSnapshot? {
        guard let indexPath = collectionView.indexPath(for: cell) else {
            return nil
        }
        
        return favoriteItem(at: indexPath)
    }
    
    func favoriteItem(forContextMenuAnchor anchorView: UIView) -> BookmarkContentSnapshot? {
        guard let cell = favoriteItemCell(containing: anchorView) else {
            return nil
        }
        
        return favoriteItem(for: cell)
    }
    
    func presentBookmarkEditor(for bookmark: BookmarkSnapshot) {
        let viewController = EditBookmarkViewController(bookmark: bookmark, store: bookmarkStore)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        UIApplication.shared.topViewController()?.present(navigationController, animated: true)
    }
    
    func deleteFavoriteBookmark(_ bookmark: BookmarkSnapshot) {
        _ = bookmarkStore.removeBookmark(guid: bookmark.guid)
    }
    
    func deleteFavoriteFolder(_ folder: BookmarkFolderSnapshot) {
        _ = bookmarkStore.removeFolder(guid: folder.guid)
    }
    
    func removeFavoriteContextMenuInteraction(_ interaction: UIContextMenuInteraction) {
        guard contextMenuInteraction === interaction else {
            return
        }
        
        interaction.view?.removeInteraction(interaction)
        contextMenuInteraction = nil
    }
    
    // MARK: - Reorder
    
    @objc private func handleReorderLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        let pressLocation = gestureRecognizer.location(in: collectionView)
        
        switch gestureRecognizer.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: pressLocation),
                  let cell = collectionView.cellForItem(at: indexPath) else {
                return
            }
            setFavoriteCell(cell, lifted: true, animated: true)
            let workItem = DispatchWorkItem { [weak self, weak cell] in
                guard let self,
                      let cell,
                      case .pending(let pendingCell, _, _, _) = self.reorderState,
                      pendingCell === cell else {
                    return
                }
                
                Haptics.prepareRigid()
                Haptics.rigid()
                self.presentFavoriteContextMenu(for: cell)
            }
            reorderState = .pending(cell: cell, indexPath: indexPath, startLocation: pressLocation, workItem: workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + UX.contextMenuPresentationDelay, execute: workItem)
            
        case .changed:
            if case .pending(let cell, let indexPath, let startLocation, let workItem) = reorderState {
                let movement = hypot(pressLocation.x - startLocation.x, pressLocation.y - startLocation.y)
                guard movement >= UX.reorderMovementThreshold else {
                    return
                }
                
                workItem.cancel()
                if collectionView.beginInteractiveMovementForItem(at: indexPath) {
                    reorderState = .active(cell: cell)
                    collectionView.updateInteractiveMovementTargetPosition(pressLocation)
                } else {
                    setFavoriteCell(cell, lifted: false, animated: true)
                    reorderState = .idle
                }
            } else if case .active = reorderState {
                collectionView.updateInteractiveMovementTargetPosition(pressLocation)
            }
            
        case .ended:
            finishFavoriteReordering(cancelled: false)
            
        default:
            finishFavoriteReordering(cancelled: true)
        }
    }
    
    private func finishFavoriteReordering(cancelled: Bool) {
        switch reorderState {
        case .pending(let cell, _, _, let workItem):
            workItem.cancel()
            setFavoriteCell(cell, lifted: false, animated: true)
        case .active(let cell):
            cancelled ? collectionView.cancelInteractiveMovement() : collectionView.endInteractiveMovement()
            setFavoriteCell(cell, lifted: false, animated: true)
        case .idle:
            break
        }
        reorderState = .idle
    }
    
    func cancelFavoriteReordering() {
        finishFavoriteReordering(cancelled: true)
    }
    
    private func presentFavoriteContextMenu(for cell: UICollectionViewCell) {
        if let contextMenuInteraction {
            contextMenuInteraction.view?.removeInteraction(contextMenuInteraction)
            self.contextMenuInteraction = nil
        }
        
        let interaction = UIContextMenuInteraction(delegate: self)
        let anchorView = contextMenuAnchorView(for: cell)
        anchorView.addInteraction(interaction)
        contextMenuInteraction = interaction
        
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            removeFavoriteContextMenuInteraction(interaction)
            cancelFavoriteReordering()
            return
        }
        
        let location = CGPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY)
        DispatchQueue.main.async { [weak self, weak interaction] in
            guard let self,
                  let interaction,
                  self.contextMenuInteraction === interaction else {
                return
            }
            
            _ = interaction.perform(selector, with: NSValue(cgPoint: location))
        }
    }
    
    private func contextMenuAnchorView(for cell: UICollectionViewCell) -> UIView {
        if let siteCell = cell as? FavoriteSiteCollectionViewCell {
            return siteCell.contextMenuAnchorView
        } else if let folderCell = cell as? FavoriteFolderCollectionViewCell {
            return folderCell.contextMenuAnchorView
        }
        
        return cell
    }
    
    private func favoriteItemCell(containing view: UIView) -> UICollectionViewCell? {
        var currentView: UIView? = view
        while let view = currentView {
            if let cell = view as? UICollectionViewCell {
                return cell
            }
            currentView = view.superview
        }
        
        return nil
    }
    
    private func setFavoriteCell(_ cell: UICollectionViewCell, lifted: Bool, animated: Bool) {
        if let siteCell = cell as? FavoriteSiteCollectionViewCell {
            siteCell.setReorderState(lifted ? .lifted : .resting, animated: animated)
        } else if let folderCell = cell as? FavoriteFolderCollectionViewCell {
            folderCell.setReorderState(lifted ? .lifted : .resting, animated: animated)
        }
    }
    
}

// MARK: - Collection View Delegate

extension FavoritesSectionViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayedFavoriteItems.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch displayedFavoriteItems[indexPath.item] {
        case let .bookmark(bookmark):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FavoriteSiteCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as! FavoriteSiteCollectionViewCell
            cell.configure(favorite: bookmark)
            return cell
            
        case let .folder(folder):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FavoriteFolderCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as! FavoriteFolderCollectionViewCell
            cell.configure(folder: folder, previewBookmarks: previewBookmarks(for: folder))
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard displayedFavoriteItems.indices.contains(indexPath.item) else {
            return
        }
        
        switch displayedFavoriteItems[indexPath.item] {
        case let .bookmark(bookmark):
            delegate?.homepageSection(self, didRequestOpenURL: bookmark.url, disposition: .currentTab)
        case let .folder(folder):
            delegate?.favoritesSectionViewController(self, didSelectFolder: folder)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return displayedFavoriteItems.indices.contains(indexPath.item)
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard displayedFavoriteItems.indices.contains(sourceIndexPath.item) else {
            reloadFavorites()
            return
        }
        
        let destinationIndex = min(max(destinationIndexPath.item, 0), displayedFavoriteItems.count - 1)
        let favoriteItem = displayedFavoriteItems.remove(at: sourceIndexPath.item)
        displayedFavoriteItems.insert(favoriteItem, at: destinationIndex)
        
        guard let favoritesFolderGUID,
              bookmarkStore.moveBookmarkItem(guid: favoriteItem.guid, to: destinationIndex, in: favoritesFolderGUID) else {
            reloadFavorites()
            return
        }
    }
    
    private func previewBookmarks(for folder: BookmarkFolderSnapshot) -> [BookmarkSnapshot] {
        let contents = bookmarkStore.contents(of: folder.guid)
        return contents.items.compactMap { item in
            guard case let .bookmark(bookmark) = item else {
                return nil
            }
            return bookmark
        }
    }
}

extension FavoritesSectionViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}

private extension BookmarkContentSnapshot {
    var guid: String {
        switch self {
        case let .bookmark(bookmark):
            return bookmark.guid
        case let .folder(folder):
            return folder.guid
        }
    }
}
