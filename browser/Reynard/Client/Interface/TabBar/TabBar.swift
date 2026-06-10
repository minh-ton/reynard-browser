//
//  TabBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabBar {
    typealias TabCollectionHandler = UICollectionViewDataSource & UICollectionViewDelegate & UICollectionViewDelegateFlowLayout
    
    struct LayoutMetrics {
        let width: CGFloat
        let mode: TabBarCell.LayoutMode
    }
    
    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        view.showsHorizontalScrollIndicator = false
        view.contentInset = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.dataSource = tabCollectionHandler
        view.delegate = tabCollectionHandler
        let reorderGesture = UILongPressGestureRecognizer(
            target: tabCollectionHandler as AnyObject,
            action: #selector(BrowserViewController.handleOverviewReorderLongPress(_:))
        )
        reorderGesture.minimumPressDuration = 0.35
        reorderGesture.delegate = tabCollectionHandler as? UIGestureRecognizerDelegate
        view.addGestureRecognizer(reorderGesture)
        view.register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseIdentifier)
        return view
    }()
    
    var heightConstraint: NSLayoutConstraint!
    
    private let tabCollectionHandler: TabCollectionHandler
    
    init(tabCollectionHandler: TabCollectionHandler) {
        self.tabCollectionHandler = tabCollectionHandler
    }
    
    func layoutMetrics(
        for index: Int,
        fallbackWidth: CGFloat,
        tabCount: Int,
        usesExpandedWidth: (Int) -> Bool
    ) -> LayoutMetrics {
        let horizontalInsets = collectionView.adjustedContentInset.left + collectionView.adjustedContentInset.right
        let baseWidth = collectionView.bounds.width > 1 ? collectionView.bounds.width : fallbackWidth
        let availableWidth = max(0, baseWidth - horizontalInsets)
        let safeTabCount = max(1, tabCount)
        let equalWidth = floor(availableWidth / CGFloat(safeTabCount))
        
        if equalWidth >= TabBarCell.expandedMinimumWidth {
            return LayoutMetrics(width: equalWidth, mode: .expanded)
        }
        
        let isExpanded = usesExpandedWidth(index)
        let expandedTabCount = max(1, (0..<safeTabCount).reduce(0) { count, tabIndex in
            count + (usesExpandedWidth(tabIndex) ? 1 : 0)
        })
        let unselectedCount = max(0, safeTabCount - expandedTabCount)
        
        let widthForUnselected: CGFloat
        let reachesCollapsedThreshold: Bool
        if unselectedCount == 0 {
            widthForUnselected = availableWidth
            reachesCollapsedThreshold = false
        } else {
            let remainingWidth = availableWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedTabCount))
            widthForUnselected = floor(remainingWidth / CGFloat(unselectedCount))
            reachesCollapsedThreshold = widthForUnselected <= TabBarCell.collapsedMinimumWidth
        }
        
        if isExpanded {
            return LayoutMetrics(width: TabBarCell.expandedMinimumWidth, mode: .expanded)
        }
        
        if reachesCollapsedThreshold {
            return LayoutMetrics(width: TabBarCell.collapsedMinimumWidth, mode: .faviconOnly)
        }
        
        return LayoutMetrics(width: max(0, widthForUnselected), mode: .expanded)
    }
    
    func refreshLayout(
        fallbackWidth: CGFloat,
        tabCount: Int,
        selectedIndex: Int,
        pendingExpandedIndex: Int?
    ) {
        let horizontalInsets = collectionView.adjustedContentInset.left + collectionView.adjustedContentInset.right
        let baseWidth = collectionView.bounds.width > 1 ? collectionView.bounds.width : fallbackWidth
        let tabBarWidth = max(0, baseWidth - horizontalInsets)
        
        let shouldScroll: Bool = {
            guard tabCount > 1 else {
                return false
            }
            
            let equalWidth = floor(tabBarWidth / CGFloat(tabCount))
            guard equalWidth < TabBarCell.expandedMinimumWidth else {
                return false
            }
            
            let hasPendingExpanded = pendingExpandedIndex != nil
            && pendingExpandedIndex != selectedIndex
            && (0..<tabCount).contains(pendingExpandedIndex ?? -1)
            let expandedCount = hasPendingExpanded ? 2 : 1
            let otherCount = tabCount - expandedCount
            guard otherCount > 0 else {
                return false
            }
            
            let remainingWidth = tabBarWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedCount))
            let otherWidth = floor(remainingWidth / CGFloat(otherCount))
            return otherWidth <= TabBarCell.collapsedMinimumWidth
        }()
        
        collectionView.isScrollEnabled = shouldScroll
        collectionView.collectionViewLayout.invalidateLayout()
        guard !collectionView.isHidden else {
            return
        }
        
        collectionView.layoutIfNeeded()
    }
}
