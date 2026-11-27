//
//  TabOverviewCollection+UICollectionView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

extension TabOverviewCollection: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let tabMode = tabMode(for: collectionView) else { return 0 }
        let tabCount = tabs(for: tabMode).count
        let includesInsertionPlaceholder = hasInsertionPlaceholder(for: tabMode)
        if tabMode == .privateTabs {
            collectionView.backgroundView?.isHidden = tabCount != 0 || includesInsertionPlaceholder
        }
        return tabCount + (includesInsertionPlaceholder ? 1 : 0)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isInsertionPlaceholder(in: collectionView, at: indexPath) {
            return insertionPlaceholderCell(in: collectionView, at: indexPath)
        }
        
        let tabCard = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabOverviewCard.reuseIdentifier,
            for: indexPath
        ) as! TabOverviewCard
        
        guard let tabMode = tabMode(for: collectionView),
              tabs(for: tabMode).indices.contains(indexPath.item) else {
            return tabCard
        }
        
        tabCard.isHidden = false
        configureTabCard(tabCard, with: tabs(for: tabMode)[indexPath.item])
        tabCard.onClose = { [weak self, weak collectionView, weak tabCard] in
            guard let self, let collectionView, let tabCard else {
                return
            }
            self.closeTab(for: tabCard, in: collectionView)
        }
        return tabCard
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let tabMode = tabMode(for: collectionView),
              tabs(for: tabMode).indices.contains(indexPath.item),
              let tabOverview else {
            return
        }
        let selectedTab = tabs(for: tabMode)[indexPath.item]
        let previewImage = (collectionView.cellForItem(at: indexPath) as? TabOverviewCard)?.previewImage
        ?? selectedTab.thumbnail
        tabOverview.prepareDismissSelection(to: indexPath.item, mode: tabMode.tabMode, previewImage: previewImage)
        if !tabOverview.isTransitionRunning {
            tabOverview.reloadTabs()
        }
        tabOverview.delegate?.tabOverviewDidRequestDismiss(tabOverview, animated: true)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard cell is TabOverviewCard else { return }
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        tabOverview?.presentation.cardSize(in: collectionView) ?? .zero
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        tabOverview?.presentation.finishPresentationForScrolling(in: collectionView)
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           let collectionView = panGesture.view as? UICollectionView {
            let velocity = panGesture.velocity(in: collectionView)
            guard velocity.x < 0,
                  abs(velocity.x) > abs(velocity.y),
                  let indexPath = collectionView.indexPathForItem(at: panGesture.location(in: collectionView)),
                  !isInsertionPlaceholder(in: collectionView, at: indexPath),
                  let tabCard = collectionView.cellForItem(at: indexPath) as? TabOverviewCard else {
                return false
            }
            let locationInCard = collectionView.convert(panGesture.location(in: collectionView), to: tabCard)
            return !tabCard.isCloseButton(at: locationInCard)
        }
        
        return false
    }
    
    private func insertionPlaceholderCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let placeholderCell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.insertionPlaceholderReuseIdentifier,
            for: indexPath
        )
        placeholderCell.isHidden = true
        placeholderCell.contentView.alpha = 0
        placeholderCell.backgroundColor = .clear
        return placeholderCell
    }
}

extension TabOverviewCollection: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let tabMode = tabMode(for: collectionView),
              let tab = tabs(for: tabMode)[safe: indexPath.item],
              let tabCard = collectionView.cellForItem(at: indexPath) as? TabOverviewCard,
              !tabCard.isCloseButton(at: session.location(in: tabCard)) else {
            return []
        }
        
        return [UIDragItem(tab: tab)]
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        dragPreviewParametersForItemAt indexPath: IndexPath
    ) -> UIDragPreviewParameters? {
        let tabCard = collectionView.cellForItem(at: indexPath) as? TabOverviewCard
        return tabCard?.makeDragPreviewParameters()
    }
}

extension TabOverviewCollection: UICollectionViewDropDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard let tab = session.localDragSession?.items.first?.draggedTab,
              tab.mode == tabMode(for: collectionView)?.tabMode else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let tabMode = tabMode(for: collectionView),
              let item = coordinator.items.first,
              let tab = item.dragItem.draggedTab else {
            return
        }
        
        let tabCount = tabs(for: tabMode).count
        guard let sourceIndexPath = item.sourceIndexPath else {
            tabOverview?.dataSource?.moveTab(withID: tab.id, to: coordinator.destinationIndexPath?.item ?? tabCount)
            return
        }
        
        let destinationItem = min(coordinator.destinationIndexPath?.item ?? tabCount, tabCount - 1)
        let destinationIndexPath = IndexPath(item: destinationItem, section: 0)
        collectionView.performBatchUpdates {
            tabOverview?.dataSource?.moveTab(from: sourceIndexPath.item, to: destinationItem, mode: tabMode.tabMode)
            collectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }
        refreshTabIdentitySnapshot()
        let animator = coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
        let tabCard = collectionView.cellForItem(at: destinationIndexPath) as? TabOverviewCard
        tabCard?.settleDrop(with: animator, in: collectionView)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        dropPreviewParametersForItemAt indexPath: IndexPath
    ) -> UIDragPreviewParameters? {
        let tabCard = collectionView.cellForItem(at: indexPath) as? TabOverviewCard
        return tabCard?.makeDragPreviewParameters()
    }
}
