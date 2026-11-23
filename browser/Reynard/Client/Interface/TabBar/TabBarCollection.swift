//
//  TabBarCollection.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

private final class TabBarCollectionLayout: UICollectionViewFlowLayout {
    private enum UX {
        static let separatorWidth: CGFloat = 2 / UIScreen.main.scale
        static let separatorHeight: CGFloat = 20
    }
    
    static let separatorKind = "TabBarSeparator"
    weak var tabBar: TabBar?
    private var insertedIndexPaths = Set<IndexPath>()
    
    func prepareForInsertion(at indexPaths: [IndexPath]) {
        insertedIndexPaths.formUnion(indexPaths)
    }
    
    override func initialLayoutAttributesForAppearingItem(
        at itemIndexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath) else {
            return nil
        }
        
        guard insertedIndexPaths.contains(itemIndexPath) else {
            return attributes
        }
        
        attributes.transform = CGAffineTransform(translationX: attributes.size.width, y: 0)
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths.removeAll()
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes = super.layoutAttributesForElements(in: rect) ?? []
        guard let collectionView,
              let dataSourceTabCount = tabBar?.dataSource?.activeTabs.count else {
            return attributes
        }
        let tabCount = min(collectionView.numberOfItems(inSection: 0), dataSourceTabCount)
        guard tabCount > 1 else {
            return attributes
        }
        
        for index in 0..<(tabCount - 1) {
            guard showsSeparator(after: index),
                  let separatorAttributes = separatorAttributes(after: index, in: rect) else {
                continue
            }
            attributes.append(separatorAttributes)
        }
        return attributes
    }
    
    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == Self.separatorKind else {
            return super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath)
        }
        
        guard showsSeparator(after: indexPath.item) else {
            return nil
        }
        return separatorAttributes(after: indexPath.item, in: nil)
    }
    
    private func showsSeparator(after index: Int) -> Bool {
        guard let collectionView,
              let tabBar,
              let dataSourceTabCount = tabBar.dataSource?.activeTabs.count else {
            return false
        }
        let tabCount = min(collectionView.numberOfItems(inSection: 0), dataSourceTabCount)
        guard tabCount > 1,
              index >= 0,
              index < tabCount - 1 else {
            return false
        }
        
        return !tabBar.isTabSelected(at: index) && !tabBar.isTabSelected(at: index + 1)
    }
    
    private func separatorAttributes(
        after index: Int,
        in rect: CGRect?
    ) -> UICollectionViewLayoutAttributes? {
        guard let leftAttributes = super.layoutAttributesForItem(at: IndexPath(item: index, section: 0)),
              let rightAttributes = super.layoutAttributesForItem(at: IndexPath(item: index + 1, section: 0)) else {
            return nil
        }
        
        let centerX = (leftAttributes.frame.maxX + rightAttributes.frame.minX) / 2
        let frame = CGRect(
            x: centerX - (UX.separatorWidth / 2),
            y: leftAttributes.frame.midY - (UX.separatorHeight / 2),
            width: UX.separatorWidth,
            height: UX.separatorHeight
        )
        if let rect,
           !rect.insetBy(dx: -UX.separatorWidth, dy: -UX.separatorHeight).intersects(frame) {
            return nil
        }
        
        let attributes = UICollectionViewLayoutAttributes(
            forDecorationViewOfKind: Self.separatorKind,
            with: IndexPath(item: index, section: 0)
        )
        attributes.frame = frame
        attributes.zIndex = 1
        return attributes
    }
    
}

final class TabBarCollection: UICollectionView, UIGestureRecognizerDelegate {
    private enum UX {
        static let tabReorderMinimumPressDuration: TimeInterval = 0.35
        static let tabReorderStartDelay: TimeInterval = 0.06
        static let tabReorderDirectionThreshold: CGFloat = 1
        static let tabReorderTargetHysteresis: CGFloat = 8
        static let dragSnapshotScale: CGFloat = 1.04
        static let dragSnapshotAnimationDuration: TimeInterval = 0.15
        static let dragSnapshotSnapDuration: TimeInterval = 0.24
        static let dragSnapshotSnapDamping: CGFloat = 0.82
        static let dragSnapshotBackgroundFadeDuration: TimeInterval = 0.12
        static let dragSnapshotBackgroundOpacity: CGFloat = 0.5
        static let selectedDragSnapshotBackgroundOpacity: CGFloat = 0.75
    }
    
    private weak var tabBar: TabBar?
    private let layout: TabBarCollectionLayout
    private var lastLayoutWidth: CGFloat = 0
    private var isUpdatingTabs = false
    private var needsReload = false
    private var pendingInsertedIndices = Set<Int>()
    private var pendingDeletedIndices = Set<Int>()
    
    private weak var draggedCell: TabBarCell?
    private var dragSnapshot: UIView?
    private var dragSnapshotBackground: UIView?
    private var reorderStartWorkItem: DispatchWorkItem?
    private var dragTouchOffset: CGPoint = .zero
    private var previousDragX: CGFloat?
    private var didMoveTab = false
    private var isEndingReorder = false
    
    private(set) var dragSourceIndex: Int?
    private(set) var dragDestinationIndex: Int?
    
    init() {
        let layout = TabBarCollectionLayout()
        self.layout = layout
        super.init(frame: .zero, collectionViewLayout: layout)
        configureAppearance()
        configureLayout(layout)
        configureCollection()
        configureGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressGesture = gestureRecognizer as? UILongPressGestureRecognizer,
              let indexPath = indexPathForItem(at: longPressGesture.location(in: self)),
              let tabBarCell = cellForItem(at: indexPath) as? TabBarCell else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        
        let locationInCell = convert(longPressGesture.location(in: self), to: tabBarCell)
        return !tabBarCell.containsCloseButton(at: locationInCell)
    }
    
    override func layoutSubviews() {
        let widthChanged = abs(lastLayoutWidth - bounds.width) > 0.5
        super.layoutSubviews()
        guard widthChanged else {
            return
        }
        lastLayoutWidth = bounds.width
        guard !isUpdatingTabs else {
            return
        }
        updateScrollability()
        refreshVisibleTabs()
        revealSelectedTab()
    }
    
    // MARK: - Configuration
    
    func attach(to tabBar: TabBar) {
        self.tabBar = tabBar
        layout.tabBar = tabBar
        layout.invalidateLayout()
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        guard !isUpdatingTabs else {
            needsReload = true
            refreshVisibleTabs()
            return
        }
        
        reloadData()
        updateLayout()
        refreshVisibleTabs()
    }
    
    func updateTabs(inserting insertedIndices: [Int] = [], deleting deletedIndices: [Int] = []) {
        guard !isUpdatingTabs else {
            pendingInsertedIndices.formUnion(insertedIndices)
            pendingDeletedIndices.formUnion(deletedIndices)
            return
        }
        
        let currentCount = numberOfItems(inSection: 0)
        let hasSingleChangeType = insertedIndices.isEmpty != deletedIndices.isEmpty
        guard let tabBar,
              hasSingleChangeType,
              let tabCount = tabBar.dataSource?.activeTabs.count,
              currentCount + insertedIndices.count - deletedIndices.count == tabCount,
              insertedIndices.allSatisfy((0..<tabCount).contains),
              deletedIndices.allSatisfy((0..<currentCount).contains) else {
            reloadTabs()
            return
        }
        
        let insertedIndexPaths = insertedIndices.map { IndexPath(item: $0, section: 0) }
        let deletedIndexPaths = deletedIndices.map { IndexPath(item: $0, section: 0) }
        let shouldRevealRightmostTab = insertedIndices.contains(tabCount - 1)
        layout.prepareForInsertion(at: insertedIndexPaths)
        updateLayout()
        isUpdatingTabs = true
        performBatchUpdates({
            if !deletedIndexPaths.isEmpty {
                deleteItems(at: deletedIndexPaths)
            }
            if !insertedIndexPaths.isEmpty {
                insertItems(at: insertedIndexPaths)
            }
        }, completion: { [weak self] _ in
            guard let self else {
                return
            }
            
            self.finishTabUpdate()
        })
        
        if shouldRevealRightmostTab {
            updateScrollability()
            layoutIfNeeded()
            scrollToItem(
                at: IndexPath(item: tabCount - 1, section: 0),
                at: .right,
                animated: true
            )
        }
    }
    
    func reloadTab(at index: Int) {
        let indexPath = IndexPath(item: index, section: 0)
        guard let tabBarCell = cellForItem(at: indexPath) as? TabBarCell else {
            return
        }
        configure(tabBarCell, at: indexPath)
    }
    
    func invalidateLayout() {
        collectionViewLayout.invalidateLayout()
    }
    
    func updateLayout() {
        updateScrollability()
        collectionViewLayout.invalidateLayout()
        layoutIfNeeded()
        revealSelectedTab()
    }
    
    private func finishTabUpdate() {
        isUpdatingTabs = false
        updateLayout()
        refreshVisibleTabs()
        
        let insertedIndices = pendingInsertedIndices.sorted()
        let deletedIndices = pendingDeletedIndices.sorted()
        let reloadPending = needsReload
        pendingInsertedIndices.removeAll()
        pendingDeletedIndices.removeAll()
        needsReload = false
        
        let hasSingleChangeType = insertedIndices.isEmpty != deletedIndices.isEmpty
        if hasSingleChangeType {
            needsReload = reloadPending
            updateTabs(inserting: insertedIndices, deleting: deletedIndices)
        } else if reloadPending || !insertedIndices.isEmpty || !deletedIndices.isEmpty {
            reloadTabs()
        }
    }
    
    private func updateScrollability() {
        let tabCount = tabBar?.dataSource?.activeTabs.count ?? 0
        let horizontalInsets = adjustedContentInset.left + adjustedContentInset.right
        let baseWidth = bounds.width > 1 ? bounds.width : tabBar?.bounds.width ?? 0
        let availableWidth = max(0, baseWidth - horizontalInsets)
        let selectedIndex = tabBar?.dataSource?.selectedTab.flatMap { selectedTab in
            tabBar?.dataSource?.activeTabs.firstIndex { $0.id == selectedTab.id }
        }
        let pendingIndex = tabBar?.pendingExpandedTabIndex
        
        let shouldScroll: Bool = {
            guard tabCount > 1 else {
                return false
            }
            
            let equalWidth = floor(availableWidth / CGFloat(tabCount))
            guard equalWidth < TabBarCell.expandedMinimumWidth else {
                return false
            }
            
            let hasPendingExpandedTab = pendingIndex.map {
                $0 != selectedIndex && (0..<tabCount).contains($0)
            } ?? false
            let expandedCount = hasPendingExpandedTab ? 2 : 1
            let otherCount = tabCount - expandedCount
            guard otherCount > 0 else {
                return false
            }
            
            let remainingWidth = availableWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedCount))
            let otherWidth = floor(remainingWidth / CGFloat(otherCount))
            return otherWidth <= TabBarCell.collapsedMinimumWidth
        }()
        
        isScrollEnabled = shouldScroll
    }
    
    private func refreshVisibleTabs() {
        for case let tabBarCell as TabBarCell in visibleCells {
            guard let indexPath = indexPath(for: tabBarCell) else {
                continue
            }
            configure(tabBarCell, at: indexPath)
        }
    }
    
    private func revealSelectedTab() {
        guard isScrollEnabled,
              let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              let selectedIndex = tabs.indices.first(where: tabBar.isTabSelected(at:)),
              selectedIndex < numberOfItems(inSection: 0),
              let attributes = layoutAttributesForItem(
                at: IndexPath(item: selectedIndex, section: 0)
              ) else {
            return
        }
        
        scrollRectToVisible(attributes.frame, animated: false)
    }
    
    private func configure(_ tabBarCell: TabBarCell, at indexPath: IndexPath) {
        guard let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              tabs.indices.contains(indexPath.item) else {
            return
        }
        
        let tab = tabs[indexPath.item]
        let cellLayout = tabBar.cellLayout(at: indexPath.item)
        tabBarCell.configure(
            tab: tab,
            isSelected: tabBar.isTabSelected(at: indexPath.item),
            layoutMode: cellLayout.mode,
            cellWidth: cellLayout.width
        )
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        contentInset = .zero
        contentInsetAdjustmentBehavior = .never
    }
    
    private func configureLayout(_ layout: UICollectionViewFlowLayout) {
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
    }
    
    private func configureCollection() {
        dataSource = self
        delegate = self
        scrollsToTop = false
        register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseIdentifier)
        layout.register(
            TabBarSeparatorView.self,
            forDecorationViewOfKind: TabBarCollectionLayout.separatorKind
        )
    }
    
    private func configureGestures() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderLongPress(_:)))
        longPressGesture.minimumPressDuration = UX.tabReorderMinimumPressDuration
        longPressGesture.delegate = self
        addGestureRecognizer(longPressGesture)
    }
    
    // MARK: - Reordering
    
    @objc private func handleReorderLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        let location = gestureRecognizer.location(in: self)
        switch gestureRecognizer.state {
        case .began:
            beginReordering(at: location)
        case .changed:
            updateReordering(at: location)
        case .ended:
            finishReordering(cancelled: false)
        default:
            finishReordering(cancelled: true)
        }
    }
    
    private func beginReordering(at location: CGPoint) {
        guard let indexPath = indexPathForItem(at: location),
              let tabBarCell = cellForItem(at: indexPath) as? TabBarCell,
              !tabBarCell.containsCloseButton(at: convert(location, to: tabBarCell)) else {
            return
        }
        
        draggedCell = tabBarCell
        dragSourceIndex = indexPath.item
        dragDestinationIndex = indexPath.item
        previousDragX = location.x
        didMoveTab = false
        cancelReorderStart()
        beginDragSnapshot(for: tabBarCell, at: location)
        tabBar?.updateReorderState(.pending)
        
        let workItem = DispatchWorkItem { [weak self, weak tabBarCell] in
            guard let self,
                  let tabBarCell,
                  self.draggedCell === tabBarCell,
                  self.tabBar?.reorderState == .pending else {
                return
            }
            
            guard self.beginInteractiveMovementForItem(at: indexPath) else {
                self.isEndingReorder = true
                self.endDragSnapshot { [weak self] in
                    self?.resetReordering()
                }
                return
            }
            self.tabBar?.updateReorderState(.active)
        }
        reorderStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.tabReorderStartDelay, execute: workItem)
    }
    
    private func updateReordering(at location: CGPoint) {
        guard tabBar?.reorderState == .active else {
            return
        }
        
        updateDragDestination(at: location, previousX: previousDragX)
        previousDragX = location.x
        updateInteractiveMovementTargetPosition(location)
        updateDragSnapshotPosition(location)
    }
    
    private func finishReordering(cancelled: Bool) {
        guard !isEndingReorder else {
            return
        }
        
        cancelReorderStart()
        let destinationIndex = dragDestinationIndex
        if tabBar?.reorderState == .active {
            if cancelled {
                cancelInteractiveMovement()
            } else {
                endInteractiveMovement()
            }
        }
        
        guard !cancelled,
              didMoveTab,
              let destinationIndex else {
            isEndingReorder = true
            completeReordering()
            return
        }
        
        isEndingReorder = true
        animateDragSnapshot(to: destinationIndex) { [weak self] in
            self?.completeReordering()
        }
    }
    
    private func cancelReorderStart() {
        reorderStartWorkItem?.cancel()
        reorderStartWorkItem = nil
    }
    
    private func updateDragDestination(at location: CGPoint, previousX: CGFloat?) {
        guard let previousX,
              let currentDestinationIndex = dragDestinationIndex,
              let tabCount = tabBar?.dataSource?.activeTabs.count else {
            return
        }
        
        let horizontalDelta = location.x - previousX
        let candidateIndex: Int
        let crossedCandidateCenter: Bool
        
        if horizontalDelta >= UX.tabReorderDirectionThreshold {
            candidateIndex = currentDestinationIndex + 1
            guard candidateIndex < tabCount,
                  let candidateAttributes = layoutAttributesForItem(at: IndexPath(item: candidateIndex, section: 0)) else {
                return
            }
            crossedCandidateCenter = location.x >= candidateAttributes.center.x + UX.tabReorderTargetHysteresis
        } else if horizontalDelta <= -UX.tabReorderDirectionThreshold {
            candidateIndex = currentDestinationIndex - 1
            guard candidateIndex >= 0,
                  let candidateAttributes = layoutAttributesForItem(at: IndexPath(item: candidateIndex, section: 0)) else {
                return
            }
            crossedCandidateCenter = location.x <= candidateAttributes.center.x - UX.tabReorderTargetHysteresis
        } else {
            return
        }
        
        guard crossedCandidateCenter else {
            return
        }
        
        dragDestinationIndex = candidateIndex
        collectionViewLayout.invalidateLayout()
    }
    
    private func completeReordering() {
        if didMoveTab {
            reloadData()
        }
        collectionViewLayout.invalidateLayout()
        layoutIfNeeded()
        revealSelectedTab()
        endDragSnapshot { [weak self] in
            self?.resetReordering()
        }
    }
    
    private func resetReordering() {
        clearReorderState()
        previousDragX = nil
        didMoveTab = false
        isEndingReorder = false
    }
    
    private func clearReorderState() {
        dragSourceIndex = nil
        dragDestinationIndex = nil
        tabBar?.updateReorderState(.idle)
    }
    
    // MARK: - Drag Snapshot
    
    private func beginDragSnapshot(for tabBarCell: TabBarCell, at location: CGPoint) {
        guard let dragContainer = tabBar?.superview,
              let dragSnapshot = tabBarCell.snapshotView(afterScreenUpdates: true) else {
            return
        }
        
        dragSnapshot.frame = tabBarCell.convert(tabBarCell.bounds, to: dragContainer)
        dragSnapshot.isUserInteractionEnabled = false
        var backgroundView: UIView?
        var backgroundOpacity = UX.dragSnapshotBackgroundOpacity
        if let tabID = tabBarCell.tabID,
           let isSelected = tabBar?.isTabSelected(id: tabID) {
            let background = UIView(frame: dragSnapshot.frame.inset(by: TabBarCell.contentInsets))
            background.backgroundColor = .systemGray6
            background.layer.cornerRadius = TabBarCell.contentCornerRadius
            background.layer.cornerCurve = .continuous
            background.clipsToBounds = true
            background.isUserInteractionEnabled = false
            background.alpha = 0
            backgroundOpacity = isSelected
            ? UX.selectedDragSnapshotBackgroundOpacity
            : UX.dragSnapshotBackgroundOpacity
            dragContainer.addSubview(background)
            backgroundView = background
            dragSnapshotBackground = background
        }
        dragContainer.addSubview(dragSnapshot)
        UIView.animate(
            withDuration: UX.dragSnapshotAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            dragSnapshot.transform = CGAffineTransform(scaleX: UX.dragSnapshotScale, y: UX.dragSnapshotScale)
            backgroundView?.alpha = backgroundOpacity
            backgroundView?.transform = CGAffineTransform(scaleX: UX.dragSnapshotScale, y: UX.dragSnapshotScale)
        }
        
        tabBarCell.isHidden = true
        self.dragSnapshot = dragSnapshot
        let touchInDragContainer = convert(location, to: dragContainer)
        dragTouchOffset = CGPoint(
            x: touchInDragContainer.x - dragSnapshot.center.x,
            y: touchInDragContainer.y - dragSnapshot.center.y
        )
    }
    
    private func updateDragSnapshotPosition(_ location: CGPoint) {
        guard let dragContainer = tabBar?.superview,
              let dragSnapshot else {
            return
        }
        
        let touchInDragContainer = convert(location, to: dragContainer)
        dragSnapshot.center = CGPoint(
            x: touchInDragContainer.x - dragTouchOffset.x,
            y: touchInDragContainer.y - dragTouchOffset.y
        )
        dragSnapshotBackground?.center = dragSnapshot.center
    }
    
    private func animateDragSnapshot(to destinationIndex: Int, completion: @escaping () -> Void) {
        guard let dragContainer = tabBar?.superview,
              let dragSnapshot,
              let attributes = layoutAttributesForItem(
                at: IndexPath(item: destinationIndex, section: 0)
              ) else {
            completion()
            return
        }
        
        let targetFrame = convert(attributes.frame, to: dragContainer)
        let targetBackgroundFrame = targetFrame.inset(by: TabBarCell.contentInsets)
        let backgroundView = dragSnapshotBackground
        UIView.animate(
            withDuration: UX.dragSnapshotSnapDuration,
            delay: 0,
            usingSpringWithDamping: UX.dragSnapshotSnapDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .curveEaseOut],
            animations: {
                dragSnapshot.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                dragSnapshot.bounds.size = targetFrame.size
                dragSnapshot.transform = .identity
                backgroundView?.center = CGPoint(
                    x: targetBackgroundFrame.midX,
                    y: targetBackgroundFrame.midY
                )
                backgroundView?.bounds.size = targetBackgroundFrame.size
                backgroundView?.transform = .identity
                backgroundView?.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
    
    private func endDragSnapshot(completion: @escaping () -> Void) {
        let finish = { [weak self] in
            self?.removeDragSnapshot()
            completion()
        }
        
        guard let background = dragSnapshotBackground,
              background.alpha > 0 else {
            finish()
            return
        }
        
        UIView.animate(
            withDuration: UX.dragSnapshotBackgroundFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut],
            animations: {
                background.alpha = 0
            },
            completion: { _ in
                finish()
            }
        )
    }
    
    private func removeDragSnapshot() {
        dragSnapshotBackground?.removeFromSuperview()
        dragSnapshotBackground = nil
        dragSnapshot?.removeFromSuperview()
        dragSnapshot = nil
        draggedCell?.isHidden = false
        draggedCell = nil
        dragTouchOffset = .zero
    }
}

extension TabBarCollection: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabBar?.dataSource?.activeTabs.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tabBarCell = dequeueReusableCell(
            withReuseIdentifier: TabBarCell.reuseIdentifier,
            for: indexPath
        ) as! TabBarCell
        
        guard let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              tabs.indices.contains(indexPath.item) else {
            return tabBarCell
        }
        
        configure(tabBarCell, at: indexPath)
        tabBarCell.closeHandler = { [weak self, weak tabBarCell] in
            guard let self,
                  let tabBarCell,
                  let currentIndexPath = self.indexPath(for: tabBarCell) else {
                return
            }
            self.tabBar?.requestCloseTab(at: currentIndexPath.item)
        }
        return tabBarCell
    }
}

extension TabBarCollection: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tabBar?.requestSelectTab(at: indexPath.item)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
        toProposedIndexPath _: IndexPath
    ) -> IndexPath {
        guard let dragDestinationIndex else {
            return originalIndexPath
        }
        
        return IndexPath(item: dragDestinationIndex, section: originalIndexPath.section)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        moveItemAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        tabBar?.requestMoveTab(from: sourceIndexPath.item, to: destinationIndexPath.item)
        didMoveTab = true
        clearReorderState()
    }
}

extension TabBarCollection: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let tabBar else {
            return .zero
        }
        
        let cellLayout = tabBar.cellLayout(at: indexPath.item)
        return CGSize(width: cellLayout.width, height: bounds.height)
    }
}
