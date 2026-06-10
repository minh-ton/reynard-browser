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
    private var tabOverviewDismissTargetMode: TabMode?
    private var pendingTabSelectionFromOverview: Int?
    private var pendingTabSelectionMode: TabMode?
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
        
        for collectionView in controller.browserUI.tabOverviewCollection.allCollectionViews {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
        }
        controller.browserUI.tabOverviewCollection.applyTransforms()
    }
    
    func prepareDismissSelection(to index: Int, mode: TabMode, previewImage: UIImage?) {
        let selectedIndex = controller.tabManager.selectedTabMode == mode ? controller.tabManager.selectedTabIndex : nil
        tabOverviewDismissTargetIndex = index
        tabOverviewDismissTargetMode = mode
        pendingTabSelectionFromOverview = index == selectedIndex ? nil : index
        pendingTabSelectionMode = mode
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
            let overviewMode: TabOverviewCollection.Mode = controller.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
            controller.browserUI.tabOverviewBarButtons.modeControl.selectedSegmentIndex = overviewMode.rawValue
            controller.browserUI.tabOverviewCollection.setMode(overviewMode, in: controller.browserUI.tabOverview.containerView, animated: false)
            tabOverviewDismissTargetIndex = controller.tabManager.selectedTabIndex
            pendingTabSelectionFromOverview = nil
            pendingTabSelectionMode = nil
            pendingOverviewPreviewImage = nil
            controller.captureThumbnail(for: controller.tabManager.selectedTabIndex)
            controller.browserUI.tabOverviewBarButtons.setTabCount(controller.regularTabCount())
            controller.browserUI.tabOverviewCollection.tabsCollection.reloadData()
            controller.browserUI.tabOverviewCollection.privateTabsCollection.reloadData()
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
            tabCount: (controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs).count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
    }
    
    func applyOverviewProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        currentOverviewProgress = clamped
        
        controller.browserUI.tabOverview.containerView.alpha = clamped
        
        let collectionOffset = (1 - clamped) * 26
        controller.browserUI.tabOverviewCollection.applyVerticalOffset(collectionOffset)
        
        let pageScale = 1 - (0.08 * clamped)
        controller.browserUI.geckoView.transform = CGAffineTransform(scaleX: pageScale, y: pageScale)
        
        if controller.usesPadChrome {
            controller.browserUI.topBar.barView.alpha = 1 - clamped
            controller.browserUI.topBar.safeAreaFillView.alpha = 1 - clamped
        } else {
            controller.browserUI.bottomContainer.containerView.alpha = 1 - clamped
            controller.browserUI.bottomContainer.containerView.transform = CGAffineTransform(translationX: 0, y: 24 * clamped)
        }
    }
    
    private func animatePhoneOverviewPresentation() {
        isTransitionRunning = true
        isVisible = true
        currentOverviewProgress = 1
        
        let overviewMode: TabOverviewCollection.Mode = controller.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
        controller.browserUI.tabOverviewBarButtons.modeControl.selectedSegmentIndex = overviewMode.rawValue
        controller.browserUI.tabOverviewCollection.setMode(overviewMode, in: controller.browserUI.tabOverview.containerView, animated: false)
        let selectedIndex = controller.tabManager.selectedTabIndex
        controller.view.layoutIfNeeded()
        let bottomSnapshot = controller.browserUI.bottomToolbar.snapshotView(afterScreenUpdates: false)
        controller.applyChromeLayout(animated: false)
        controller.captureThumbnail(for: selectedIndex)
        controller.browserUI.tabOverviewCollection.tabsCollection.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.privateTabsCollection.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.tabsCollection.reloadData()
        controller.browserUI.tabOverviewCollection.privateTabsCollection.reloadData()
        controller.browserUI.tabOverviewBarButtons.setTabCount(controller.regularTabCount())
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 0
        controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        controller.view.insertSubview(controller.browserUI.tabOverview.containerView, belowSubview: controller.browserUI.geckoView)
        controller.view.endEditing(true)
        controller.setSearchFocused(false, animated: false)
        controller.view.layoutIfNeeded()
        
        tabOverviewDismissTargetIndex = selectedIndex
        let selectedCollection = controller.currentOverviewCollectionView()
        if let selectedItem = controller.overviewItemIndex(forTabAt: selectedIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedOverviewCell(at: selectedIndex),
              let bottomSnapshot else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        guard let transitionView = selectedCell.transitionSnapshotView() else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        let finalContentFrame = selectedCell.transitionContentFrame(in: controller.view)
        let finalPreviewFrame = selectedCell.transitionPreviewImageFrame(in: controller.view)
        let geckoFrame = controller.browserUI.geckoView.convert(controller.browserUI.geckoView.bounds, to: controller.view)
        
        selectedCell.setTransitionHidden(true)
        controller.browserUI.tabOverview.containerView.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: 0.65, y: 0.65)
        
        bottomSnapshot.frame = controller.browserUI.bottomToolbar.convert(controller.browserUI.bottomToolbar.bounds, to: controller.view)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = transitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: geckoFrame
        )
        controller.view.insertSubview(transitionView, belowSubview: controller.browserUI.geckoView)
        controller.view.addSubview(bottomSnapshot)
        
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.bottomContainer.containerView.isHidden = true
        controller.browserUI.bottomContainer.bottomSafeAreaFillView.isHidden = true
        
        UIView.animate(withDuration: 0.60, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            bottomSnapshot.alpha = 0
            self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            selectedCollection.transform = standardCollectionTransform
        } completion: { _ in
            bottomSnapshot.removeFromSuperview()
            transitionView.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.view.bringSubviewToFront(self.controller.browserUI.tabOverview.containerView)
            self.controller.browserUI.geckoView.isHidden = false
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
        
        let selectedCollection = controller.currentOverviewCollectionView()
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
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
            tabCount: (controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs).count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
        
        controller.browserUI.bottomContainer.containerView.alpha = 0
        controller.browserUI.bottomContainer.bottomSafeAreaFillView.alpha = 0
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.controller.dismissalContentFrame()
            pageSnapshot.layer.cornerRadius = 0
            bottomSnapshot.alpha = 0
            self.controller.browserUI.tabOverview.containerView.alpha = 0
            for collectionView in self.controller.browserUI.tabOverviewCollection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: 0.65, y: 0.65)
            self.controller.browserUI.bottomContainer.containerView.alpha = 1
            self.controller.browserUI.bottomContainer.bottomSafeAreaFillView.alpha = 1
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            bottomSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            selectedCollection.transform = standardCollectionTransform
            
            self.controller.browserUI.geckoView.isHidden = false
            for collectionView in self.controller.browserUI.tabOverviewCollection.allCollectionViews {
                collectionView.alpha = 1
            }
            self.controller.browserUI.tabOverviewCollection.applyVerticalOffset(0)
            self.controller.browserUI.tabOverview.containerView.isHidden = true
            self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            self.isTransitionRunning = false
        }
    }
    
    private func animatePadOverviewPresentation() {
        isTransitionRunning = true
        isVisible = true
        currentOverviewProgress = 1
        
        let overviewMode: TabOverviewCollection.Mode = controller.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
        controller.browserUI.tabOverviewBarButtons.modeControl.selectedSegmentIndex = overviewMode.rawValue
        controller.browserUI.tabOverviewCollection.setMode(overviewMode, in: controller.browserUI.tabOverview.containerView, animated: false)
        let selectedIndex = controller.tabManager.selectedTabIndex
        controller.applyChromeLayout(animated: false)
        controller.captureThumbnail(for: selectedIndex)
        controller.browserUI.tabOverviewCollection.tabsCollection.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.privateTabsCollection.collectionViewLayout.invalidateLayout()
        controller.browserUI.tabOverviewCollection.tabsCollection.reloadData()
        controller.browserUI.tabOverviewCollection.privateTabsCollection.reloadData()
        controller.browserUI.tabOverviewBarButtons.setTabCount(controller.regularTabCount())
        let isPhoneTopPresentation = controller.usesBottomPhoneOverview
        controller.browserUI.tabOverview.containerView.isHidden = false
        controller.browserUI.tabOverview.containerView.alpha = 0
        if isPhoneTopPresentation {
            controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
        } else {
            controller.browserUI.tabOverviewTopBar.barView.alpha = 0
        }
        controller.view.insertSubview(controller.browserUI.tabOverview.containerView, belowSubview: controller.browserUI.geckoView)
        controller.view.endEditing(true)
        controller.view.layoutIfNeeded()
        
        tabOverviewDismissTargetIndex = selectedIndex
        let selectedCollection = controller.currentOverviewCollectionView()
        if let selectedItem = controller.overviewItemIndex(forTabAt: selectedIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedOverviewCell(at: selectedIndex) else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        guard let transitionView = selectedCell.transitionSnapshotView() else {
            isTransitionRunning = false
            applyOverviewProgress(1)
            isVisible = true
            controller.applyChromeLayout(animated: false)
            return
        }
        
        let finalContentFrame = selectedCell.transitionContentFrame(in: controller.view)
        let finalPreviewFrame = selectedCell.transitionPreviewImageFrame(in: controller.view)
        let geckoFrame = controller.browserUI.geckoView.convert(controller.browserUI.geckoView.bounds, to: controller.view)
        
        selectedCell.setTransitionHidden(true)
        controller.browserUI.tabOverview.containerView.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: 0.65, y: 0.65)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = transitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: geckoFrame
        )
        controller.view.insertSubview(transitionView, belowSubview: controller.browserUI.geckoView)
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.bottomContainer.containerView.isHidden = true
        controller.browserUI.bottomContainer.bottomSafeAreaFillView.isHidden = true
        
        UIView.animate(withDuration: 0.60, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            if isPhoneTopPresentation {
                self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 1
            } else {
                self.controller.browserUI.tabOverviewTopBar.barView.alpha = 1
            }
            selectedCollection.transform = standardCollectionTransform
            self.controller.browserUI.topBar.barView.alpha = 0
            self.controller.browserUI.topBar.safeAreaFillView.alpha = 0
        } completion: { _ in
            transitionView.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            
            self.controller.view.bringSubviewToFront(self.controller.browserUI.tabOverview.containerView)
            self.controller.browserUI.geckoView.isHidden = false
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
        
        let selectedCollection = controller.currentOverviewCollectionView()
        if let selectedItem = controller.overviewItemIndex(forTabAt: overviewIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
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
            tabCount: (controller.tabManager.selectedTabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs).count,
            selectedIndex: controller.tabManager.selectedTabIndex,
            pendingExpandedIndex: controller.pendingExpandedTabBarIndex
        )
        
        controller.browserUI.geckoView.isHidden = true
        controller.browserUI.bottomContainer.bottomSafeAreaFillView.alpha = 0
        controller.browserUI.topBar.barView.alpha = 0
        controller.browserUI.topBar.safeAreaFillView.alpha = 0
        controller.browserUI.tabBar.collectionView.alpha = 0
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.controller.dismissalContentFrame()
            pageSnapshot.layer.cornerRadius = 0
            self.controller.browserUI.tabOverview.containerView.alpha = 0
            for collectionView in self.controller.browserUI.tabOverviewCollection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: 0.65, y: 0.65)
            if isPhoneTopDismissal {
                self.controller.browserUI.tabOverviewBottomBar.barView.alpha = 0
            } else {
                self.controller.browserUI.tabOverviewTopBar.barView.alpha = 0
            }
            self.controller.browserUI.bottomContainer.bottomSafeAreaFillView.alpha = 1
            self.controller.browserUI.topBar.barView.alpha = 1
            self.controller.browserUI.topBar.safeAreaFillView.alpha = 1
            self.controller.browserUI.tabBar.collectionView.alpha = 1
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionHidden(false)
            selectedCollection.transform = standardCollectionTransform
            
            self.controller.browserUI.geckoView.isHidden = false
            for collectionView in self.controller.browserUI.tabOverviewCollection.allCollectionViews {
                collectionView.alpha = 1
            }
            self.controller.browserUI.tabOverviewCollection.applyVerticalOffset(0)
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
        let mode = tabOverviewDismissTargetMode ?? controller.tabManager.selectedTabMode
        let tabs = mode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        let image = pendingOverviewPreviewImage ?? tabs[safe: index]?.thumbnail
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
    
    private func bringBrowserChromeToFrontForDismissal() {
        controller.view.bringSubviewToFront(controller.browserUI.bottomContainer.bottomSafeAreaFillView)
        controller.view.bringSubviewToFront(controller.browserUI.bottomContainer.containerView)
        controller.view.bringSubviewToFront(controller.browserUI.topBar.safeAreaFillView)
        controller.view.bringSubviewToFront(controller.browserUI.topBar.barView)
    }
    
    private func transitionTransform(contentFrame: CGRect, previewFrame: CGRect, sourceFrame: CGRect) -> CGAffineTransform {
        guard previewFrame.width > 0, previewFrame.height > 0 else {
            return .identity
        }
        
        let scaleX = sourceFrame.width / previewFrame.width
        let scaleY = sourceFrame.height / previewFrame.height
        let contentCenter = CGPoint(x: contentFrame.midX, y: contentFrame.midY)
        let scaledPreviewCenter = CGPoint(
            x: contentCenter.x + ((previewFrame.midX - contentCenter.x) * scaleX),
            y: contentCenter.y + ((previewFrame.midY - contentCenter.y) * scaleY)
        )
        
        return CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: sourceFrame.midX - scaledPreviewCenter.x, ty: sourceFrame.midY - scaledPreviewCenter.y)
    }
    
    private func overviewAnimationIndex() -> Int {
        let mode = tabOverviewDismissTargetMode ?? controller.tabManager.selectedTabMode
        let tabs = mode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        let selectedIndex = mode == controller.tabManager.selectedTabMode ? controller.tabManager.selectedTabIndex : 0
        let candidate = tabOverviewDismissTargetIndex ?? selectedIndex
        if tabs.indices.contains(candidate) {
            return candidate
        }
        return min(max(selectedIndex, 0), max(tabs.count - 1, 0))
    }
    
    private func applyPendingOverviewTabSelectionIfNeeded() {
        defer {
            pendingTabSelectionFromOverview = nil
            tabOverviewDismissTargetIndex = nil
            tabOverviewDismissTargetMode = nil
            pendingTabSelectionMode = nil
            pendingOverviewPreviewImage = nil
        }
        
        let selectedIndex = pendingTabSelectionMode == controller.tabManager.selectedTabMode ? controller.tabManager.selectedTabIndex : nil
        guard let target = pendingTabSelectionFromOverview,
              target != selectedIndex,
              let mode = pendingTabSelectionMode else {
            return
        }
        let targetTabs = mode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        guard targetTabs.indices.contains(target) else {
            return
        }
        
        controller.pendingSelectionAnimation = false
        controller.tabManager.selectTab(at: target, mode: mode)
    }
    
    private func selectedOverviewCell(at index: Int) -> TabOverviewCard? {
        let tabMode = tabOverviewDismissTargetMode ?? controller.tabManager.selectedTabMode
        let tabs = tabMode == .private ? controller.tabManager.privateTabs : controller.tabManager.regularTabs
        guard tabs.indices.contains(index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        let collectionView = tabMode == .private ? controller.browserUI.tabOverviewCollection.privateTabsCollection : controller.browserUI.tabOverviewCollection.tabsCollection
        return collectionView.cellForItem(at: indexPath) as? TabOverviewCard
    }
    
    private func selectedOverviewPreviewFrame(at index: Int) -> CGRect? {
        guard let cell = selectedOverviewCell(at: index) else {
            return nil
        }
        return cell.previewFrame(in: controller.view)
    }
}
