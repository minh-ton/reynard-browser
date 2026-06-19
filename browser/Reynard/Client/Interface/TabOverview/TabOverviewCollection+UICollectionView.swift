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
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        !isInsertionPlaceholder(in: collectionView, at: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isInsertionPlaceholder(in: collectionView, at: indexPath) {
            return insertionPlaceholderCell(in: collectionView, at: indexPath)
        }
        
        guard let tabMode = tabMode(for: collectionView),
              tabs(for: tabMode).indices.contains(indexPath.item),
              let tabCard = collectionView.dequeueReusableCell(
                withReuseIdentifier: TabOverviewCard.reuseIdentifier,
                for: indexPath
              ) as? TabOverviewCard else {
            return UICollectionViewCell()
        }
        
        tabCard.isHidden = false
        tabCard.configure(with: tabs(for: tabMode)[indexPath.item])
        tabCard.onClose = { [weak self, weak collectionView, weak tabCard] in
            guard let self,
                  let collectionView,
                  let tabCard,
                  let currentIndexPath = collectionView.indexPath(for: tabCard),
                  let currentTabMode = self.tabMode(for: collectionView),
                  let tabOverview = self.tabOverview else {
                return
            }
            tabOverview.delegate?.tabOverviewDidRequestClearPendingTabExpansion(tabOverview)
            tabOverview.dataSource?.closeTab(at: currentIndexPath.item, mode: currentTabMode.tabMode)
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
        tabOverview.reloadTabs()
        tabOverview.delegate?.tabOverviewDidRequestDismiss(tabOverview, animated: true)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        moveItemAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard let tabMode = tabMode(for: collectionView) else { return }
        tabOverview?.dataSource?.moveTab(
            from: sourceIndexPath.item,
            to: destinationIndexPath.item,
            mode: tabMode.tabMode
        )
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
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressGesture = gestureRecognizer as? UILongPressGestureRecognizer,
              let collectionView = longPressGesture.view as? UICollectionView,
              let indexPath = collectionView.indexPathForItem(at: longPressGesture.location(in: collectionView)),
              let tabCard = collectionView.cellForItem(at: indexPath) as? TabOverviewCard else {
            return false
        }
        let locationInCard = collectionView.convert(longPressGesture.location(in: collectionView), to: tabCard)
        return !tabCard.isCloseButton(at: locationInCard)
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
