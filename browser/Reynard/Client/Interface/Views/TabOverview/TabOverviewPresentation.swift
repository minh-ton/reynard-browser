//
//  TabOverviewPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewPresentation {
    private unowned let controller: BrowserViewController
    
    private var currentOverviewProgress: CGFloat = 0
    private var tabOverviewDismissTargetIndex: Int?
    private var pendingTabSelectionFromOverview: Int?
    private var pendingOverviewPreviewImage: UIImage?
    
    private(set) var isVisible = false
    private(set) var isTransitionRunning = false
    
    init(controller: BrowserViewController) {
        self.controller = controller
    }
    
    func itemSize(for collectionView: UICollectionView) -> CGSize {
        let horizontalInsets = collectionView.adjustedContentInset.left + collectionView.adjustedContentInset.right
        let availableWidth = collectionView.bounds.width - horizontalInsets
        let tabViewAspectRatio = max(0.4, controller.tabPreviewAspectRatio())
        
        let targetWidth: CGFloat = controller.usesPadChrome ? 250 : 170
        let computedColumns = Int((availableWidth + controller.overviewSpacing) / (targetWidth + controller.overviewSpacing))
        let columns = max(2, computedColumns)
        
        let totalSpacing = CGFloat(columns - 1) * controller.overviewSpacing
        let itemWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
        let itemHeight = floor((itemWidth * tabViewAspectRatio) + 22)
        return CGSize(width: itemWidth, height: itemHeight)
    }
    
    func refreshForCurrentOrientation() {
        guard isVisible else {
            return
        }
        
        controller.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.collectionView.reloadData()
        controller.browserUI.tabOverviewCollection.collectionView.layoutIfNeeded()
    }
    
    func prepareDismissSelection(to index: Int, previewImage: UIImage?) {
        let selectedIndex = controller.tabManager.selectedTabIndex
        tabOverviewDismissTargetIndex = index
        pendingTabSelectionFromOverview = index == selectedIndex ? nil : index
        pendingOverviewPreviewImage = previewImage
    }
    
    func setVisible(_ visible: Bool, animated: Bool) {
        if isTransitionRunning {
            return
        }
        
        if visible == isVisible, currentOverviewProgress == (visible ? 1 : 0) {
            return
        }
        
        if animated {
            if controller.usesPadChrome {
                visible ? animatePadOverviewPresentation() : animatePadOverviewDismissal()
            } else {
                visible ? animatePhoneOverviewPresentation() : animatePhoneOverviewDismissal()
            }
            return
        }
        
        if visible {
            tabOverviewDismissTargetIndex = controller.tabManager.selectedTabIndex
            pendingTabSelectionFromOverview = nil
            pendingOverviewPreviewImage = nil
            controller.captureThumbnail(for: controller.tabManager.selectedTabIndex)
            controller.browserUI.tabOverviewCollection.collectionView.reloadData()
            controller.browserUI.tabOverview.containerView.isHidden = false
            controller.view.bringSubviewToFront(controller.browserUI.tabOverview.containerView)
            controller.view.endEditing(true)
            controller.setSearchFocused(false, animated: true)
        }
        
        let finalProgress: CGFloat = visible ? 1 : 0
        applyOverviewProgress(finalProgress)
        
        isVisible = visible
        if !visible {
            applyPendingOverviewTabSelectionIfNeeded()
            controller.browserUI.tabOverview.containerView.isHidden = true
            applyOverviewProgress(0)
        }
        controller.applyChromeLayout(animated: false)
        controller.browserUI.tabBar.refreshLayout(
            fallbackWidth: controller.view.bounds.width,
            tabCount: controller.tabManager.tabs.count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
    }
    
    func applyOverviewProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        currentOverviewProgress = clamped
        
        controller.browserUI.tabOverview.containerView.alpha = clamped
        
        let collectionOffset = (1 - clamped) * 26
        controller.browserUI.tabOverviewCollection.collectionView.transform = CGAffineTransform(translationX: 0, y: collectionOffset)
        
        let pageScale = 1 - (0.08 * clamped)
        controller.browserUI.geckoView.transform = CGAffineTransform(scaleX: pageScale, y: pageScale)
        
        if controller.usesPadChrome {
            controller.browserUI.topBar.barView.alpha = 1 - clamped
            controller.browserUI.topBar.safeAreaFillView.alpha = 1 - clamped
        } else {
            controller.browserUI.chromeContainer.containerView.alpha = 1 - clamped
            controller.browserUI.chromeContainer.containerView.transform = CGAffineTransform(translationX: 0, y: 24 * clamped)
        }
    }
    
    private func animatePhoneOverviewPresentation() {
        isTransitionRunning = true
        
        let selectedIndex = controller.tabManager.selectedTabIndex
        controller.captureThumbnail(for: selectedIndex)
        controller.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.collectionView.reloadData()
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 0
        controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        controller.view.bringSubviewToFront(controller.browserUI.tabOverview.containerView)
        controller.view.endEditing(true)
        controller.setSearchFocused(false, animated: false)
        controller.view.layoutIfNeeded()
        
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        tabOverviewDismissTargetIndex = selectedIndex
        controller.browserUI.tabOverviewCollection.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        controller.browserUI.tabOverviewCollection.collectionView.layoutIfNeeded()
        
        guard let selectedCell = selectedOverviewCell(at: selectedIndex),
              let targetFrame = selectedOverviewPreviewFrame(at: selectedIndex),
              let pageSnapshot = overviewPreviewSnapshotView(for: selectedIndex),
              let bottomSnapshot = controller.browserUI.toolbarView.snapshotView(afterScreenUpdates: true) else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        selectedCell.setTransitionHidden(true)
        controller.browserUI.tabOverview.containerView.alpha = 1
        
        pageSnapshot.frame = controller.browserUI.geckoView.frame
        pageSnapshot.layer.cornerRadius = 0
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        bottomSnapshot.frame = controller.browserUI.toolbarView.convert(controller.browserUI.toolbarView.bounds, to: controller.view)
        
        controller.view.addSubview(pageSnapshot)
        controller.view.addSubview(bottomSnapshot)
        
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.chromeContainer.containerView.isHidden = true
        
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut]) {
            pageSnapshot.frame = targetFrame
            pageSnapshot.layer.cornerRadius = 18
            bottomSnapshot.alpha = 0
            self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            bottomSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.browserUI.geckoView.isHidden = false
            self.isVisible = true
            self.currentOverviewProgress = 1
            self.controller.applyChromeLayout(animated: false)
            self.isTransitionRunning = false
        }
    }
    
    private func animatePhoneOverviewDismissal() {
        isTransitionRunning = true
        let overviewIndex = overviewAnimationIndex()
        
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 1
        controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
        controller.view.bringSubviewToFront(controller.browserUI.tabOverview.containerView)
        controller.view.layoutIfNeeded()
        
        let indexPath = IndexPath(item: overviewIndex, section: 0)
        controller.browserUI.tabOverviewCollection.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        controller.browserUI.tabOverviewCollection.collectionView.layoutIfNeeded()
        
        guard let selectedCell = selectedOverviewCell(at: overviewIndex),
              let sourceFrame = selectedOverviewPreviewFrame(at: overviewIndex),
              let bottomSnapshot = controller.browserUI.tabOverviewBottomBar.barView.snapshotView(afterScreenUpdates: false) else {
            isTransitionRunning = false
            applyOverviewProgress(0)
            isVisible = false
            controller.browserUI.tabOverview.containerView.isHidden = true
            applyPendingOverviewTabSelectionIfNeeded()
            controller.applyChromeLayout(animated: false)
            return
        }
        
        selectedCell.setTransitionHidden(true)
        
        let pageSnapshot = overviewPreviewSnapshotView(for: overviewIndex) ?? selectedCell.previewSnapshotView()
        guard let pageSnapshot else {
            isTransitionRunning = false
            applyOverviewProgress(0)
            isVisible = false
            controller.browserUI.tabOverview.containerView.isHidden = true
            applyPendingOverviewTabSelectionIfNeeded()
            controller.applyChromeLayout(animated: false)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = 18
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        bottomSnapshot.frame = controller.browserUI.tabOverviewBottomBar.barView.frame
        
        controller.view.addSubview(pageSnapshot)
        controller.view.addSubview(bottomSnapshot)
        
        applyPendingOverviewTabSelectionIfNeeded()
        isVisible = false
        currentOverviewProgress = 0
        controller.applyChromeLayout(animated: false)
        controller.browserUI.tabBar.refreshLayout(
            fallbackWidth: controller.view.bounds.width,
            tabCount: controller.tabManager.tabs.count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
        
        controller.browserUI.chromeContainer.containerView.alpha = 0
        controller.browserUI.chromeContainer.bottomSafeAreaFillView.alpha = 0
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.controller.dismissalContentFrame()
            pageSnapshot.layer.cornerRadius = 0
            bottomSnapshot.alpha = 0
            self.controller.browserUI.tabOverview.containerView.alpha = 0
            self.controller.browserUI.tabOverviewCollection.collectionView.alpha = 0
            self.controller.browserUI.chromeContainer.containerView.alpha = 1
            self.controller.browserUI.chromeContainer.bottomSafeAreaFillView.alpha = 1
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            bottomSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.browserUI.geckoView.isHidden = false
            self.controller.browserUI.tabOverviewCollection.collectionView.alpha = 1
            self.controller.browserUI.tabOverviewCollection.collectionView.transform = .identity
            self.controller.browserUI.tabOverview.containerView.isHidden = true
            self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            self.isTransitionRunning = false
        }
    }
    
    private func animatePadOverviewPresentation() {
        isTransitionRunning = true
        
        let selectedIndex = controller.tabManager.selectedTabIndex
        controller.captureThumbnail(for: selectedIndex)
        controller.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.collectionView.reloadData()
        let isPhoneTopPresentation = controller.usesBottomPhoneOverview
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 0
        if isPhoneTopPresentation {
            controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        } else {
            controller.browserUI.tabOverviewTopBar.barView.alpha = 0
        }
        controller.view.bringSubviewToFront(controller.browserUI.tabOverview.containerView)
        controller.view.endEditing(true)
        controller.view.layoutIfNeeded()
        
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        tabOverviewDismissTargetIndex = selectedIndex
        controller.browserUI.tabOverviewCollection.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        controller.browserUI.tabOverviewCollection.collectionView.layoutIfNeeded()
        
        guard let selectedCell = selectedOverviewCell(at: selectedIndex),
              let targetFrame = selectedOverviewPreviewFrame(at: selectedIndex),
              let pageSnapshot = overviewPreviewSnapshotView(for: selectedIndex) else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        selectedCell.setTransitionHidden(true)
        controller.browserUI.tabOverview.containerView.alpha = 1
        
        pageSnapshot.frame = controller.browserUI.geckoView.frame
        pageSnapshot.layer.cornerRadius = 0
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        controller.view.addSubview(pageSnapshot)
        controller.browserUI.geckoView.isHidden = true
        
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut]) {
            pageSnapshot.frame = targetFrame
            pageSnapshot.layer.cornerRadius = 18
            if isPhoneTopPresentation {
                self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            } else {
                self.controller.browserUI.tabOverviewTopBar.barView.alpha = 1
            }
            self.controller.browserUI.topBar.barView.alpha = 0
            self.controller.browserUI.topBar.safeAreaFillView.alpha = 0
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.browserUI.geckoView.isHidden = false
            self.isVisible = true
            self.currentOverviewProgress = 1
            self.controller.applyChromeLayout(animated: false)
            self.isTransitionRunning = false
        }
    }
    
    private func animatePadOverviewDismissal() {
        isTransitionRunning = true
        let overviewIndex = overviewAnimationIndex()
        
        let isPhoneTopDismissal = controller.usesBottomPhoneOverview
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 1
        if isPhoneTopDismissal {
            controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
        } else {
            controller.browserUI.tabOverviewTopBar.barView.alpha = 1
        }
        controller.view.bringSubviewToFront(controller.browserUI.tabOverview.containerView)
        controller.view.layoutIfNeeded()
        
        let indexPath = IndexPath(item: overviewIndex, section: 0)
        controller.browserUI.tabOverviewCollection.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        controller.browserUI.tabOverviewCollection.collectionView.layoutIfNeeded()
        
        guard let selectedCell = selectedOverviewCell(at: overviewIndex),
              let sourceFrame = selectedOverviewPreviewFrame(at: overviewIndex) else {
            isTransitionRunning = false
            applyOverviewProgress(0)
            isVisible = false
            controller.browserUI.tabOverview.containerView.isHidden = true
            applyPendingOverviewTabSelectionIfNeeded()
            controller.applyChromeLayout(animated: false)
            return
        }
        
        selectedCell.setTransitionHidden(true)
        
        let pageSnapshot = overviewPreviewSnapshotView(for: overviewIndex) ?? selectedCell.previewSnapshotView()
        guard let pageSnapshot else {
            isTransitionRunning = false
            applyOverviewProgress(0)
            isVisible = false
            controller.browserUI.tabOverview.containerView.isHidden = true
            applyPendingOverviewTabSelectionIfNeeded()
            controller.applyChromeLayout(animated: false)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = 18
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        controller.view.addSubview(pageSnapshot)
        
        applyPendingOverviewTabSelectionIfNeeded()
        isVisible = false
        currentOverviewProgress = 0
        controller.applyChromeLayout(animated: false)
        controller.browserUI.tabBar.refreshLayout(
            fallbackWidth: controller.view.bounds.width,
            tabCount: controller.tabManager.tabs.count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
        
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.chromeContainer.bottomSafeAreaFillView.alpha = 0
        controller.browserUI.topBar.barView.alpha = 0
        controller.browserUI.topBar.safeAreaFillView.alpha = 0
        controller.browserUI.tabBar.collectionView.alpha = 0
        
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.controller.dismissalContentFrame()
            pageSnapshot.layer.cornerRadius = 0
            self.controller.browserUI.tabOverview.containerView.alpha = 0
            self.controller.browserUI.tabOverviewCollection.collectionView.alpha = 0
            if isPhoneTopDismissal {
                self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
            } else {
                self.controller.browserUI.tabOverviewTopBar.barView.alpha = 0
            }
            self.controller.browserUI.chromeContainer.bottomSafeAreaFillView.alpha = 1
            self.controller.browserUI.topBar.barView.alpha = 1
            self.controller.browserUI.topBar.safeAreaFillView.alpha = 1
            self.controller.browserUI.tabBar.collectionView.alpha = 1
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.browserUI.geckoView.isHidden = false
            self.controller.browserUI.tabOverviewCollection.collectionView.alpha = 1
            self.controller.browserUI.tabOverviewCollection.collectionView.transform = .identity
            self.controller.browserUI.tabOverview.containerView.isHidden = true
            if isPhoneTopDismissal {
                self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            } else {
                self.controller.browserUI.tabOverviewTopBar.barView.alpha = 1
            }
            self.isTransitionRunning = false
        }
    }
    
    private func overviewPreviewSnapshotView(for index: Int) -> UIView? {
        let image = pendingOverviewPreviewImage ?? controller.tabManager.tabs[safe: index]?.thumbnail
        guard let image else {
            return nil
        }
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
        imageView.layer.cornerCurve = .continuous
        return imageView
    }
    
    private func overviewAnimationIndex() -> Int {
        let selectedIndex = controller.tabManager.selectedTabIndex
        let candidate = tabOverviewDismissTargetIndex ?? selectedIndex
        if controller.tabManager.tabs.indices.contains(candidate) {
            return candidate
        }
        return min(max(selectedIndex, 0), max(controller.tabManager.tabs.count - 1, 0))
    }
    
    private func applyPendingOverviewTabSelectionIfNeeded() {
        defer {
            pendingTabSelectionFromOverview = nil
            tabOverviewDismissTargetIndex = nil
            pendingOverviewPreviewImage = nil
        }
        
        let selectedIndex = controller.tabManager.selectedTabIndex
        guard let target = pendingTabSelectionFromOverview,
              target != selectedIndex,
              controller.tabManager.tabs.indices.contains(target) else {
            return
        }
        
        controller.selectTab(at: target, animated: false)
    }
    
    private func selectedOverviewCell(at index: Int) -> TabOverviewCard? {
        guard controller.tabManager.tabs.indices.contains(index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        return controller.browserUI.tabOverviewCollection.collectionView.cellForItem(at: indexPath) as? TabOverviewCard
    }
    
    private func selectedOverviewPreviewFrame(at index: Int) -> CGRect? {
        guard let cell = selectedOverviewCell(at: index) else {
            return nil
        }
        return cell.previewFrame(in: controller.view)
    }
}
