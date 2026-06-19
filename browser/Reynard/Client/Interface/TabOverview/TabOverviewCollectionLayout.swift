//
//  TabOverviewCollectionLayout.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewCollectionLayout: UICollectionViewFlowLayout {
    private enum UX {
        static let insertedTabCardInitialScale: CGFloat = 0.85
    }
    
    private var insertedCardIndexPaths = Set<IndexPath>()
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        insertedCardIndexPaths = Set(updateItems.compactMap { updateItem in
            updateItem.updateAction == .insert ? updateItem.indexPathAfterUpdate : nil
        })
    }
    
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        ?? layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if insertedCardIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
            attributes?.transform = CGAffineTransform(
                scaleX: UX.insertedTabCardInitialScale,
                y: UX.insertedTabCardInitialScale
            )
        }
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedCardIndexPaths.removeAll()
    }
}
