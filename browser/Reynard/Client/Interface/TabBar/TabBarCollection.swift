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
        
        guard showsSeparator(after: indexPath.item),
              let attributes = separatorAttributes(after: indexPath.item, in: nil) else {
            let attributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: elementKind, with: indexPath)
            attributes.isHidden = true
            return attributes
        }
        return attributes
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

final class TabBarCollection: UICollectionView {
    private enum UX {
        static let tabUpdateAnimationDuration: TimeInterval = 0.3
        static let reorderEdgeInset: CGFloat = 128
    }
    
    private weak var tabBar: TabBar?
    private let layout: TabBarCollectionLayout
    private var lastLayoutWidth: CGFloat = 0
    private var isUpdatingTabs = false
    private var needsReload = false
    private var pendingInsertedIndices = Set<Int>()
    private var pendingDeletedIndices = Set<Int>()
    private var isSettlingDrop = false
    
    init() {
        let layout = TabBarCollectionLayout()
        self.layout = layout
        super.init(frame: .zero, collectionViewLayout: layout)
        configureAppearance()
        configureLayout(layout)
        configureCollection()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    
    @objc(_indexPathForItemAtPoint:)
    private func indexPathForItemInTabRow(at point: CGPoint) -> IndexPath? {
        let selector = #selector(indexPathForItemInTabRow(at:))
        typealias IndexPathForItemAtPoint = @convention(c) (AnyObject, Selector, CGPoint) -> Unmanaged<NSIndexPath>?
        let indexPathForItem = unsafeBitCast(UICollectionView.instanceMethod(for: selector), to: IndexPathForItemAtPoint.self)
        var rowPoint = CGPoint(x: point.x, y: bounds.midY)
        let visibleMaxX = min(bounds.maxX, contentSize.width)
        let visibleWidth = visibleMaxX - bounds.minX
        let dragWidth = visibleWidth - UX.reorderEdgeInset * 2
        
        if hasActiveDrag && dragWidth > 0 {
            let stretchedX = bounds.minX + (point.x - bounds.minX - UX.reorderEdgeInset) * visibleWidth / dragWidth
            rowPoint.x = min(max(stretchedX, bounds.minX + 1), visibleMaxX - 1)
        }
        
        return indexPathForItem(self, selector, rowPoint)?.takeUnretainedValue() as IndexPath?
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
        isUpdatingTabs = true
        updateScrollability()
        
        UIView.animate(withDuration: UX.tabUpdateAnimationDuration) {
            self.performBatchUpdates({
                if !deletedIndexPaths.isEmpty {
                    self.deleteItems(at: deletedIndexPaths)
                }
                if !insertedIndexPaths.isEmpty {
                    self.insertItems(at: insertedIndexPaths)
                }
            }, completion: { [weak self] _ in
                guard let self else {
                    return
                }
                
                self.finishTabUpdate()
            })
            
            if shouldRevealRightmostTab {
                let contentWidth = self.collectionViewLayout.collectionViewContentSize.width
                self.contentOffset.x = max(0, contentWidth - self.bounds.width)
            }
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
        dragDelegate = self
        dropDelegate = self
        dragInteractionEnabled = true
        scrollsToTop = false
        register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseIdentifier)
        layout.register(
            TabBarSeparatorView.self,
            forDecorationViewOfKind: TabBarCollectionLayout.separatorKind
        )
    }
}

extension TabBarCollection: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabBar?.dataSource?.activeTabs.count ?? 0
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

extension TabBarCollection: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let tabBarCell = cellForItem(at: indexPath) as? TabBarCell,
              !tabBarCell.containsCloseButton(at: session.location(in: tabBarCell)),
              let tab = tabBar?.dataSource?.activeTabs[safe: indexPath.item] else {
            return []
        }
        
        clipsToBounds = false
        tabBar?.clipsToBounds = false
        return [UIDragItem(tab: tab)]
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        dragPreviewParametersForItemAt indexPath: IndexPath
    ) -> UIDragPreviewParameters? {
        guard let tabBarCell = cellForItem(at: indexPath) else {
            return nil
        }
        
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(
            roundedRect: tabBarCell.bounds.inset(by: TabBarCell.contentInsets),
            cornerRadius: TabBarCell.contentCornerRadius
        )
        return parameters
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        if !isSettlingDrop {
            clipsToBounds = true
            tabBar?.clipsToBounds = true
        }
        updateLayout()
        refreshVisibleTabs()
    }
}

extension TabBarCollection: UICollectionViewDropDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard let tab = session.localDragSession?.items.first?.draggedTab,
              tab.mode == tabBar?.dataSource?.selectedTabMode else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let tab = item.dragItem.draggedTab,
              let tabCount = tabBar?.dataSource?.activeTabs.count else {
            return
        }
        
        guard let sourceIndexPath = item.sourceIndexPath else {
            tabBar?.requestMoveTab(tab, to: coordinator.destinationIndexPath?.item ?? tabCount)
            return
        }
        
        let destinationItem = min(coordinator.destinationIndexPath?.item ?? tabCount, tabCount - 1)
        let destinationIndexPath = IndexPath(item: destinationItem, section: 0)
        performBatchUpdates {
            tabBar?.requestMoveTab(from: sourceIndexPath.item, to: destinationItem)
            moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }
        
        isSettlingDrop = true
        coordinator.drop(item.dragItem, toItemAt: destinationIndexPath).addCompletion { [weak self] _ in
            self?.isSettlingDrop = false
            self?.clipsToBounds = true
            self?.tabBar?.clipsToBounds = true
        }
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        dropPreviewParametersForItemAt indexPath: IndexPath
    ) -> UIDragPreviewParameters? {
        let parameters = self.collectionView(collectionView, dragPreviewParametersForItemAt: indexPath)
        if #available(iOS 14.0, *) {
            parameters?.shadowPath = UIBezierPath()
        }
        return parameters
    }
}
