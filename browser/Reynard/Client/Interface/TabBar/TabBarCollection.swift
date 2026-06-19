//
//  TabBarCollection.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabBarCollection: UICollectionView, UIGestureRecognizerDelegate {
    private enum UX {
        static let tabReorderMinimumPressDuration: TimeInterval = 0.35
        static let tabReorderStartDelay: TimeInterval = 0.06
        static let tabReorderDirectionThreshold: CGFloat = 1
        static let tabReorderTargetHysteresis: CGFloat = 8
        static let dragSnapshotScale: CGFloat = 1.04
        static let dragSnapshotAnimationDuration: TimeInterval = 0.15
        static let dragSnapshotShadowOpacity: Float = 0.18
        static let dragSnapshotShadowRadius: CGFloat = 10
        static let dragSnapshotShadowOffset = CGSize(width: 0, height: 6)
    }
    
    private weak var tabBar: TabBar?
    private weak var draggedCell: UICollectionViewCell?
    private weak var dragSnapshot: UIView?
    private var reorderStartWorkItem: DispatchWorkItem?
    private var dragTouchOffset: CGPoint = .zero
    private var previousDragX: CGFloat?
    private var hasCommittedReorder = false
    
    private(set) var dragSourceIndex: Int?
    private(set) var dragDestinationIndex: Int?
    
    init() {
        let layout = UICollectionViewFlowLayout()
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
    
    func attach(to tabBar: TabBar) {
        self.tabBar = tabBar
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        reloadData()
        updateLayout()
        refreshVisibleTabs()
    }
    
    func reloadTab(at index: Int) {
        guard numberOfSections > 0,
              index >= 0,
              index < numberOfItems(inSection: 0) else {
            return
        }
        
        reloadItems(at: [IndexPath(item: index, section: 0)])
    }
    
    func invalidateLayout() {
        collectionViewLayout.invalidateLayout()
    }
    
    func updateLayout() {
        let tabCount = tabBar?.dataSource?.tabs.count ?? 0
        let horizontalInsets = adjustedContentInset.left + adjustedContentInset.right
        let baseWidth = bounds.width > 1 ? bounds.width : tabBar?.bounds.width ?? 0
        let availableWidth = max(0, baseWidth - horizontalInsets)
        let selectedIndex = tabBar?.dataSource?.selectedTabID.flatMap { selectedTabID in
            tabBar?.dataSource?.tabs.firstIndex { $0.id == selectedTabID }
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
            
            let hasPendingExpanded = pendingIndex != nil
            && pendingIndex != selectedIndex
            && (0..<tabCount).contains(pendingIndex ?? -1)
            let expandedCount = hasPendingExpanded ? 2 : 1
            let otherCount = tabCount - expandedCount
            guard otherCount > 0 else {
                return false
            }
            
            let remainingWidth = availableWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedCount))
            let otherWidth = floor(remainingWidth / CGFloat(otherCount))
            return otherWidth <= TabBarCell.collapsedMinimumWidth
        }()
        
        isScrollEnabled = shouldScroll
        collectionViewLayout.invalidateLayout()
        guard tabBar?.visibility != .hidden else {
            return
        }
        layoutIfNeeded()
    }
    
    private func refreshVisibleTabs() {
        for case let tabBarCell as TabBarCell in visibleCells {
            guard let indexPath = indexPath(for: tabBarCell) else {
                continue
            }
            configure(tabBarCell, at: indexPath)
        }
    }
    
    private func configure(_ tabBarCell: TabBarCell, at indexPath: IndexPath) {
        guard let tabBar,
              let tabs = tabBar.dataSource?.tabs,
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
        backgroundColor = .systemGray6
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
        register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseIdentifier)
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
        hasCommittedReorder = false
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
                self.endDragSnapshot()
                self.resetReorderState()
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
        cancelReorderStart()
        if tabBar?.reorderState == .active {
            cancelled ? cancelInteractiveMovement() : endInteractiveMovement()
        }
        if hasCommittedReorder {
            reloadData()
        }
        collectionViewLayout.invalidateLayout()
        layoutIfNeeded()
        endDragSnapshot()
        resetReorderState()
        previousDragX = nil
        hasCommittedReorder = false
    }
    
    private func cancelReorderStart() {
        reorderStartWorkItem?.cancel()
        reorderStartWorkItem = nil
    }
    
    private func updateDragDestination(at location: CGPoint, previousX: CGFloat?) {
        guard let previousX,
              let currentDestinationIndex = dragDestinationIndex,
              let tabCount = tabBar?.dataSource?.tabs.count else {
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
    
    private func resetReorderState() {
        dragSourceIndex = nil
        dragDestinationIndex = nil
        tabBar?.updateReorderState(.idle)
    }
    
    // MARK: - Drag Snapshot
    
    private func beginDragSnapshot(for tabBarCell: UICollectionViewCell, at location: CGPoint) {
        guard let dragContainer = tabBar?.superview,
              let dragSnapshot = tabBarCell.snapshotView(afterScreenUpdates: false) else {
            return
        }
        
        dragSnapshot.frame = tabBarCell.convert(tabBarCell.bounds, to: dragContainer)
        dragSnapshot.isUserInteractionEnabled = false
        dragSnapshot.layer.masksToBounds = false
        dragSnapshot.layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark
        ? UIColor.white.cgColor
        : UIColor.black.cgColor
        dragSnapshot.layer.shadowOpacity = UX.dragSnapshotShadowOpacity
        dragSnapshot.layer.shadowRadius = UX.dragSnapshotShadowRadius
        dragSnapshot.layer.shadowOffset = UX.dragSnapshotShadowOffset
        dragContainer.addSubview(dragSnapshot)
        dragContainer.bringSubviewToFront(dragSnapshot)
        UIView.animate(
            withDuration: UX.dragSnapshotAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            dragSnapshot.transform = CGAffineTransform(scaleX: UX.dragSnapshotScale, y: UX.dragSnapshotScale)
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
    }
    
    private func endDragSnapshot() {
        dragSnapshot?.removeFromSuperview()
        dragSnapshot = nil
        draggedCell?.isHidden = false
        draggedCell = nil
        dragTouchOffset = .zero
    }
}

extension TabBarCollection: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabBar?.dataSource?.tabs.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let tabBar,
              let tabs = tabBar.dataSource?.tabs,
              tabs.indices.contains(indexPath.item),
              let tabBarCell = dequeueReusableCell(
                withReuseIdentifier: TabBarCell.reuseIdentifier,
                for: indexPath
              ) as? TabBarCell else {
            return UICollectionViewCell()
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
        toProposedIndexPath proposedIndexPath: IndexPath
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
        hasCommittedReorder = true
        resetReorderState()
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
