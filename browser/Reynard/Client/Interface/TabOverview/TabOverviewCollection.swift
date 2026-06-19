//
//  TabOverviewCollection.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewCollection: NSObject {
    private enum UX {
        static let privateModeIntroIconSideLength: CGFloat = 80
        static let privateModeIntroMaximumWidth: CGFloat = 360
        static let privateModeIntroHorizontalInset: CGFloat = 48
        static let privateModeIntroItemSpacing: CGFloat = 10
        static let tabCardReorderMinimumPressDuration: TimeInterval = 0.35
        static let tabCardReorderStartDelay: TimeInterval = 0.06
        static let insertionPlaceholderScrollDuration: TimeInterval = 0.4
    }
    
    enum ReorderState {
        case idle
        case pending(cell: TabOverviewCard, workItem: DispatchWorkItem)
        case active(cell: TabOverviewCard)
    }
    
    private final class TabChangeAnimationState {
        var hasTabIdentitySnapshot = false
        var regularTabIDs: [UUID] = []
        var privateTabIDs: [UUID] = []
        var insertionPlaceholderMode: TabOverview.Mode?
    }
    
    static let insertionPlaceholderReuseIdentifier = "TabOverviewInsertionPlaceholderCell"
    
    weak var tabOverview: TabOverview?
    private let collectionContentInset: CGFloat
    private let collectionItemSpacing: CGFloat
    private let tabChangeAnimationState = TabChangeAnimationState()
    private var presentationVerticalOffset: CGFloat = 0
    private var reorderState: ReorderState = .idle
    private(set) var mode: TabOverview.Mode = .regularTabs
    
    lazy var regularTabsCollectionView = makeTabCollectionView()
    
    lazy var privateTabsCollectionView: UICollectionView = {
        let view = makeTabCollectionView()
        view.transform = CGAffineTransform(translationX: -1, y: 0)
        view.isUserInteractionEnabled = false
        view.backgroundView = privateModeIntroView
        return view
    }()
    
    private lazy var privateModeIntroView = makePrivateModeIntroView()
    
    var allCollectionViews: [UICollectionView] {
        return [privateTabsCollectionView, regularTabsCollectionView]
    }
    
    init(contentInset: CGFloat, itemSpacing: CGFloat) {
        collectionContentInset = contentInset
        collectionItemSpacing = itemSpacing
        super.init()
    }
    
    func configure(tabOverview: TabOverview) {
        self.tabOverview = tabOverview
    }
    
    // MARK: - Updates
    
    func collectionView(for mode: TabOverview.Mode) -> UICollectionView {
        mode == .privateTabs ? privateTabsCollectionView : regularTabsCollectionView
    }
    
    func tabs(for mode: TabOverview.Mode) -> [Tab] {
        guard let dataSource = tabOverview?.dataSource else { return [] }
        return mode == .privateTabs ? dataSource.privateTabs : dataSource.regularTabs
    }
    
    func tabMode(for collectionView: UICollectionView) -> TabOverview.Mode? {
        if collectionView === privateTabsCollectionView { return .privateTabs }
        if collectionView === regularTabsCollectionView { return .regularTabs }
        return nil
    }
    
    func itemIndex(forTabAt index: Int, mode: TabOverview.Mode? = nil) -> Int? {
        guard let selectedMode = tabOverview?.dataSource?.selectedMode else { return nil }
        let resolvedMode = mode ?? self.mode
        guard selectedMode == resolvedMode.tabMode,
              tabs(for: resolvedMode).indices.contains(index) else {
            return nil
        }
        return index
    }
    
    func setMode(_ mode: TabOverview.Mode, containerWidth: CGFloat, animated: Bool) {
        let modeChanged = mode != self.mode
        self.mode = mode
        privateTabsCollectionView.isUserInteractionEnabled = mode == .privateTabs
        regularTabsCollectionView.isUserInteractionEnabled = mode == .regularTabs
        
        let width = max(containerWidth, 1)
        let animations = {
            self.applyPresentationTransforms(width: width)
        }
        if animated && modeChanged {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: animations)
        } else {
            animations()
        }
    }
    
    func setPresentationVerticalOffset(_ offset: CGFloat) {
        presentationVerticalOffset = offset
        applyPresentationTransforms()
    }
    
    func applyPresentationTransforms(width: CGFloat? = nil) {
        let resolvedWidth = width ?? max(tabOverview?.bounds.width ?? 0, 1)
        let regularX = mode == .regularTabs ? 0 : resolvedWidth
        let privateX = mode == .privateTabs ? 0 : -resolvedWidth
        regularTabsCollectionView.transform = CGAffineTransform(translationX: regularX, y: presentationVerticalOffset)
        privateTabsCollectionView.transform = CGAffineTransform(translationX: privateX, y: presentationVerticalOffset)
    }
    
    func invalidateCardLayouts() {
        allCollectionViews.forEach { $0.collectionViewLayout.invalidateLayout() }
    }
    
    func reloadTabCards() {
        tabChangeAnimationState.insertionPlaceholderMode = nil
        allCollectionViews.forEach { $0.reloadData() }
        refreshTabIdentitySnapshot()
    }
    
    func refreshTabIdentitySnapshot() {
        updateTabIdentitySnapshot(
            regularIDs: tabs(for: .regularTabs).map(\.id),
            privateIDs: tabs(for: .privateTabs).map(\.id)
        )
    }
    
    func refreshVisibleTabCard(at index: Int, mode: TabOverview.Mode) {
        let modeTabs = tabs(for: mode)
        guard modeTabs.indices.contains(index),
              let cell = collectionView(for: mode).cellForItem(at: IndexPath(item: index, section: 0)) as? TabOverviewCard else {
            return
        }
        cell.configure(with: modeTabs[index])
    }
    
    func prepareInsertionPlaceholder(for mode: TabOverview.Mode, completion: @escaping () -> Void) {
        guard tabOverview?.isPresented == true,
              tabOverview?.isTransitionRunning == false,
              tabChangeAnimationState.insertionPlaceholderMode == nil else {
            completion()
            return
        }
        
        let collectionView = collectionView(for: mode)
        let fakeIndexPath = IndexPath(item: tabs(for: mode).count, section: 0)
        tabChangeAnimationState.insertionPlaceholderMode = mode
        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: [fakeIndexPath])
            } completion: { [weak self, weak collectionView] _ in
                guard let self, let collectionView,
                      self.tabChangeAnimationState.insertionPlaceholderMode == mode,
                      collectionView.numberOfItems(inSection: 0) > fakeIndexPath.item else {
                    completion()
                    return
                }
                collectionView.layoutIfNeeded()
                guard let targetOffset = self.contentOffsetForBottomAlignedItem(at: fakeIndexPath, in: collectionView) else {
                    completion()
                    return
                }
                UIView.animate(
                    withDuration: UX.insertionPlaceholderScrollDuration,
                    delay: 0,
                    usingSpringWithDamping: 0.9,
                    initialSpringVelocity: 1,
                    options: [.curveEaseInOut, .allowUserInteraction]
                ) {
                    collectionView.contentOffset = targetOffset
                }
                self.completeWhenScrollReachesTarget(
                    collectionView,
                    targetContentOffset: targetOffset,
                    timeout: UX.insertionPlaceholderScrollDuration,
                    completion: completion
                )
            }
        }
    }
    
    func applyTabCollectionChanges() {
        let regularIDs = tabs(for: .regularTabs).map(\.id)
        let privateIDs = tabs(for: .privateTabs).map(\.id)
        guard tabChangeAnimationState.hasTabIdentitySnapshot,
              tabOverview?.isPresented == true,
              tabOverview?.isTransitionRunning == false else {
            reloadTabCards()
            return
        }
        
        let previousRegularCount = tabChangeAnimationState.regularTabIDs.count
        let previousPrivateCount = tabChangeAnimationState.privateTabIDs.count
        let insertionPlaceholderMode = tabChangeAnimationState.insertionPlaceholderMode
        let regularInsertions = insertedTabCardIndexPaths(previousIDs: tabChangeAnimationState.regularTabIDs, currentIDs: regularIDs)
        let privateInsertions = insertedTabCardIndexPaths(previousIDs: tabChangeAnimationState.privateTabIDs, currentIDs: privateIDs)
        let regularDeletions = deletedTabCardIndexPaths(previousIDs: tabChangeAnimationState.regularTabIDs, currentIDs: regularIDs)
        let privateDeletions = deletedTabCardIndexPaths(previousIDs: tabChangeAnimationState.privateTabIDs, currentIDs: privateIDs)
        let isPureInsertion = previousRegularCount + regularInsertions.count == regularIDs.count
        && previousPrivateCount + privateInsertions.count == privateIDs.count
        let isPureDeletion = regularIDs.count + regularDeletions.count == previousRegularCount
        && privateIDs.count + privateDeletions.count == previousPrivateCount
        
        updateTabIdentitySnapshot(regularIDs: regularIDs, privateIDs: privateIDs)
        tabChangeAnimationState.insertionPlaceholderMode = nil
        guard ((!regularInsertions.isEmpty || !privateInsertions.isEmpty) && isPureInsertion)
                || ((!regularDeletions.isEmpty || !privateDeletions.isEmpty) && isPureDeletion) else {
            reloadTabCards()
            return
        }
        
        insertTabCards(regularInsertions, in: regularTabsCollectionView, insertionPlaceholderMode: insertionPlaceholderMode, mode: .regularTabs, previousCount: previousRegularCount)
        deleteTabCards(regularDeletions, in: regularTabsCollectionView)
        insertTabCards(privateInsertions, in: privateTabsCollectionView, insertionPlaceholderMode: insertionPlaceholderMode, mode: .privateTabs, previousCount: previousPrivateCount)
        deleteTabCards(privateDeletions, in: privateTabsCollectionView)
    }
    
    // MARK: - Collection Setup
    
    private func makeTabCollectionView() -> UICollectionView {
        let layout = TabOverviewCollectionLayout()
        layout.minimumLineSpacing = collectionItemSpacing
        layout.minimumInteritemSpacing = collectionItemSpacing
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.contentInset = UIEdgeInsets(top: collectionContentInset, left: collectionContentInset, bottom: collectionContentInset, right: collectionContentInset)
        view.dataSource = self
        view.delegate = self
        let reorderGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTabCardReorderLongPress(_:)))
        reorderGesture.minimumPressDuration = UX.tabCardReorderMinimumPressDuration
        reorderGesture.delegate = self
        view.addGestureRecognizer(reorderGesture)
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Self.insertionPlaceholderReuseIdentifier)
        view.register(TabOverviewCard.self, forCellWithReuseIdentifier: TabOverviewCard.reuseIdentifier)
        return view
    }
    
    private func makePrivateModeIntroView() -> UIView {
        let container = UIView()
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isUserInteractionEnabled = false
        let imageView = UIImageView(image: UIImage(named: "private.mode.icon")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        let titleLabel = UILabel()
        titleLabel.text = "Private Browsing"
        titleLabel.textAlignment = .center
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Reynard won't remember any of your browsing history or cookies. However, downloads and new bookmarks will be saved."
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = UX.privateModeIntroItemSpacing
        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: UX.privateModeIntroIconSideLength),
            imageView.heightAnchor.constraint(equalToConstant: UX.privateModeIntroIconSideLength),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -UX.privateModeIntroHorizontalInset),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.privateModeIntroMaximumWidth),
        ])
        return container
    }
    
    // MARK: - Animation Helpers
    
    func hasInsertionPlaceholder(for mode: TabOverview.Mode) -> Bool {
        tabChangeAnimationState.insertionPlaceholderMode == mode
    }
    
    func isInsertionPlaceholder(in collectionView: UICollectionView, at indexPath: IndexPath) -> Bool {
        guard let mode = tabMode(for: collectionView), hasInsertionPlaceholder(for: mode) else { return false }
        return indexPath.item == tabs(for: mode).count
    }
    
    private func updateTabIdentitySnapshot(regularIDs: [UUID], privateIDs: [UUID]) {
        tabChangeAnimationState.hasTabIdentitySnapshot = true
        tabChangeAnimationState.regularTabIDs = regularIDs
        tabChangeAnimationState.privateTabIDs = privateIDs
    }
    
    private func insertedTabCardIndexPaths(previousIDs: [UUID], currentIDs: [UUID]) -> [IndexPath] {
        let previous = Set(previousIDs)
        return currentIDs.indices.compactMap { previous.contains(currentIDs[$0]) ? nil : IndexPath(item: $0, section: 0) }
    }
    
    private func deletedTabCardIndexPaths(previousIDs: [UUID], currentIDs: [UUID]) -> [IndexPath] {
        let current = Set(currentIDs)
        return previousIDs.indices.compactMap { current.contains(previousIDs[$0]) ? nil : IndexPath(item: $0, section: 0) }
    }
    
    private func insertTabCards(_ indexPaths: [IndexPath], in collectionView: UICollectionView, insertionPlaceholderMode: TabOverview.Mode?, mode: TabOverview.Mode, previousCount: Int) {
        guard !indexPaths.isEmpty else { return }
        let placeholderDeletion = insertionPlaceholderMode == mode ? [IndexPath(item: previousCount, section: 0)] : []
        if placeholderDeletion.isEmpty, previousCount > 0, let last = indexPaths.last {
            collectionView.scrollToItem(at: IndexPath(item: min(max(last.item - 1, 0), previousCount - 1), section: 0), at: .bottom, animated: false)
            collectionView.layoutIfNeeded()
        }
        collectionView.performBatchUpdates {
            if !placeholderDeletion.isEmpty { collectionView.deleteItems(at: placeholderDeletion) }
            collectionView.insertItems(at: indexPaths)
        }
    }
    
    private func deleteTabCards(_ indexPaths: [IndexPath], in collectionView: UICollectionView) {
        guard !indexPaths.isEmpty else { return }
        collectionView.layoutIfNeeded()
        collectionView.performBatchUpdates { collectionView.deleteItems(at: indexPaths) }
    }
    
    private func contentOffsetForBottomAlignedItem(at indexPath: IndexPath, in collectionView: UICollectionView) -> CGPoint? {
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        let inset = collectionView.adjustedContentInset
        let minimumY = -inset.top
        let maximumY = max(minimumY, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)
        let targetY = min(max(attributes.frame.maxY - collectionView.bounds.height + inset.bottom, minimumY), maximumY)
        return CGPoint(x: collectionView.contentOffset.x, y: targetY)
    }
    
    private func completeWhenScrollReachesTarget(_ collectionView: UICollectionView, targetContentOffset: CGPoint, timeout: TimeInterval, completion: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func checkScrollPosition() {
            if abs(collectionView.contentOffset.y - targetContentOffset.y) <= 1 || Date() >= deadline {
                completion()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: checkScrollPosition)
            }
        }
        DispatchQueue.main.async(execute: checkScrollPosition)
    }
    
    // MARK: - Reordering
    
    @objc private func handleTabCardReorderLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard let collectionView = gestureRecognizer.view as? UICollectionView else { return }
        let location = gestureRecognizer.location(in: collectionView)
        switch gestureRecognizer.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let cell = collectionView.cellForItem(at: indexPath) as? TabOverviewCard,
                  !cell.isCloseButton(at: collectionView.convert(location, to: cell)) else { return }
            cell.setReorderState(.lifted, animated: true)
            let workItem = DispatchWorkItem { [weak self, weak collectionView, weak cell] in
                guard let self, let collectionView, let cell,
                      case .pending(let pendingCell, _) = self.reorderState,
                      pendingCell === cell else { return }
                if collectionView.beginInteractiveMovementForItem(at: indexPath) {
                    self.reorderState = .active(cell: cell)
                } else {
                    cell.setReorderState(.resting, animated: true)
                    self.reorderState = .idle
                }
            }
            reorderState = .pending(cell: cell, workItem: workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + UX.tabCardReorderStartDelay, execute: workItem)
        case .changed:
            if case .active = reorderState { collectionView.updateInteractiveMovementTargetPosition(location) }
        case .ended:
            finishTabCardReordering(in: collectionView, cancelled: false)
        default:
            finishTabCardReordering(in: collectionView, cancelled: true)
        }
    }
    
    private func finishTabCardReordering(in collectionView: UICollectionView, cancelled: Bool) {
        switch reorderState {
        case .pending(let cell, let workItem):
            workItem.cancel()
            cell.setReorderState(.resting, animated: true)
        case .active(let cell):
            cancelled ? collectionView.cancelInteractiveMovement() : collectionView.endInteractiveMovement()
            cell.setReorderState(.resting, animated: true)
        case .idle:
            break
        }
        reorderState = .idle
    }
}
