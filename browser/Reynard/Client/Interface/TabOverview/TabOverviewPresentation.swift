//
//  TabOverviewPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewPresentation {
    private enum UX {
        static let cardCollectionItemSpacing: CGFloat = 16
        static let cardMinimumPreviewAspectRatio: CGFloat = 0.4
        static let phoneCardTargetWidth: CGFloat = 170
        static let padCardTargetWidth: CGFloat = 250
        static let minimumTabCardColumnCount = 2
        static let cardMetadataHeight: CGFloat = 22
        static let hiddenCollectionVerticalOffset: CGFloat = 26
        static let presentedPageScaleReduction: CGFloat = 0.08
        static let hiddenPhoneToolbarTranslation: CGFloat = 24
        static let transitionCollectionInitialScale: CGFloat = 0.65
        static let presentationAnimationDuration: TimeInterval = 0.60
        static let presentationSpringDamping: CGFloat = 0.8
        static let dismissalAnimationDuration: TimeInterval = 0.45
        static let dismissalSpringDamping: CGFloat = 0.9
        static let reducedMotionFadeDuration: TimeInterval = 0.25
        static let transitionPreviewCornerRadius: CGFloat = 18
    }
    
    enum State {
        case dismissed
        case presenting
        case presented
        case dismissing
    }
    
    private unowned let tabOverview: TabOverview
    
    private var dataSource: TabOverviewDataSource {
        guard let dataSource = tabOverview.dataSource else {
            preconditionFailure("TabOverview requires a data source")
        }
        return dataSource
    }
    
    private var context: TabOverviewPresentationContext {
        guard let context = tabOverview.presentationContext else {
            preconditionFailure("TabOverview requires a presentation context")
        }
        return context
    }
    
    private var presentationProgress: CGFloat = 0
    private var dismissalTargetTabIndex: Int?
    private var dismissalTargetTabMode: TabMode?
    private var pendingSelectionTabIndex: Int?
    private var pendingSelectionTabMode: TabMode?
    private var pendingSelectionPreviewImage: UIImage?
    private var activePresentationTransition: ActivePresentationTransition?
    private var presentationToken = 0
    
    private(set) var state: State = .dismissed
    
    var isPresented: Bool {
        return state == .presented || state == .presenting
    }
    
    var isTransitionRunning: Bool {
        return state == .presenting || state == .dismissing
    }
    
    init(tabOverview: TabOverview) {
        self.tabOverview = tabOverview
    }
    
    // MARK: - Layout
    
    func cardSize(in collectionView: UICollectionView) -> CGSize {
        let horizontalInsets = collectionView.adjustedContentInset.left + collectionView.adjustedContentInset.right
        let availableWidth = collectionView.bounds.width - horizontalInsets
        let tabViewAspectRatio = max(UX.cardMinimumPreviewAspectRatio, tabOverview.previewAspectRatio)
        
        let targetWidth = context.browserLayout.chromeMode == .phone
        ? UX.phoneCardTargetWidth
        : UX.padCardTargetWidth
        let computedColumns = Int((availableWidth + UX.cardCollectionItemSpacing) / (targetWidth + UX.cardCollectionItemSpacing))
        let columns = max(UX.minimumTabCardColumnCount, computedColumns)
        
        let totalSpacing = CGFloat(columns - 1) * UX.cardCollectionItemSpacing
        let itemWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
        let itemHeight = floor((itemWidth * tabViewAspectRatio) + UX.cardMetadataHeight)
        return CGSize(width: itemWidth, height: itemHeight)
    }
    
    func refreshForCurrentOrientation() {
        guard isPresented else {
            return
        }
        
        for collectionView in tabOverview.collection.allCollectionViews {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
        }
        tabOverview.collection.restoreActiveTabCardCloseSwipeIfNeeded()
        tabOverview.collection.applyPresentationTransforms()
    }
    
    // MARK: - Selection
    
    func prepareDismissSelection(to index: Int, mode: TabMode, previewImage: UIImage?) {
        dismissalTargetTabIndex = index
        dismissalTargetTabMode = mode
        pendingSelectionTabIndex = index
        pendingSelectionTabMode = mode
        pendingSelectionPreviewImage = previewImage
    }
    
    // MARK: - Presentation
    
    func setPresented(_ visible: Bool, animated: Bool) {
        if isTransitionRunning {
            guard state == .presenting, !visible else {
                return
            }
            cancelPresentationForImmediateDismissal()
        }
        
        if visible == isPresented, presentationProgress == (visible ? 1 : 0) {
            return
        }
        
        if animated {
            if !visible, UIAccessibility.isReduceMotionEnabled {
                dismissWithFade()
            } else if context.browserLayout.chromeMode != .phone {
                visible ? presentOnPad() : dismissOnPad()
            } else {
                visible ? presentOnPhone() : dismissOnPhone()
            }
            return
        }
        
        if visible {
            state = .presenting
            let overviewMode: TabOverview.Mode = dataSource.selectedTabMode == .private ? .privateTabs : .regularTabs
            tabOverview.setMode(overviewMode, animated: false)
            dismissalTargetTabIndex = dataSource.selectedTabIndex
            pendingSelectionTabIndex = nil
            pendingSelectionTabMode = nil
            pendingSelectionPreviewImage = nil
            dataSource.captureThumbnail(forTabAt: dataSource.selectedTabIndex, mode: dataSource.selectedTabMode)
            tabOverview.reloadTabs()
            tabOverview.isHidden = false
            context.containerView.bringSubviewToFront(tabOverview)
            context.endEditing()
            context.setSearchFocused(false, animated: true)
            applyPresentationProgress(1)
            state = .presented
            context.updateLayout(animated: false, duration: 0)
            context.tabBar.updateLayout()
            return
        }
        
        applyPresentationProgress(0)
        commitPendingTabSelection()
        tabOverview.isHidden = true
        state = .dismissed
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        context.tabOverviewDidFinishDismissal()
    }
    
    // MARK: - Presentation Progress
    
    func applyPresentationProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        presentationProgress = clamped
        
        tabOverview.alpha = clamped
        
        let collectionOffset = (1 - clamped) * UX.hiddenCollectionVerticalOffset
        tabOverview.collection.setPresentationVerticalOffset(collectionOffset)
        
        let pageScale = 1 - (UX.presentedPageScaleReduction * clamped)
        context.contentView.setTransitionTransform(CGAffineTransform(scaleX: pageScale, y: pageScale))
        
        if context.browserLayout.chromeMode != .phone {
            context.browserChrome.setChromeTransition(topAlpha: 1 - clamped, bottomAlpha: 1, bottomTranslationY: 0)
        } else {
            context.browserChrome.setChromeTransition(
                topAlpha: 1,
                bottomAlpha: 1 - clamped,
                bottomTranslationY: UX.hiddenPhoneToolbarTranslation * clamped
            )
        }
    }
    
    private func finishPresentationWithoutAnimation(chromeSnapshot: UIView?) {
        chromeSnapshot?.removeFromSuperview()
        context.containerView.bringSubviewToFront(tabOverview)
        tabOverview.setActiveToolbarAlpha(1)
        applyPresentationProgress(1)
        context.browserChrome.setBottomToolbarHidden(true)
        context.updateLayout(animated: false, duration: 0)
        state = .presented
    }
    
    private func finishDismissalWithoutAnimation(commitSelection: Bool = true) {
        if commitSelection {
            commitPendingTabSelection()
        }
        state = .dismissed
        applyPresentationProgress(0)
        tabOverview.isHidden = true
        context.updateLayout(animated: false, duration: 0)
        context.tabOverviewDidFinishDismissal()
    }
    
    // MARK: - Phone Animations
    
    private func presentOnPhone() {
        state = .presenting
        presentationProgress = 1
        activePresentationTransition = nil
        presentationToken += 1
        
        let overviewMode: TabOverview.Mode = dataSource.selectedTabMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = dataSource.selectedTabIndex
        context.containerView.layoutIfNeeded()
        let bottomChromeView = context.browserChrome.bottomToolbarTransitionView()
        context.prepareTabOverviewPresentation()
        dataSource.captureThumbnail(forTabAt: selectedIndex, mode: dataSource.selectedTabMode)
        if let bottomChromeView {
            bottomChromeView.frame = context.browserChrome.bottomToolbarTransitionFrame(in: context.containerView)
            context.containerView.addSubview(bottomChromeView)
        }
        animatePhonePresentation(selectedIndex: selectedIndex, bottomChromeView: bottomChromeView)
    }
    
    private func animatePhonePresentation(selectedIndex: Int, bottomChromeView: UIView?) {
        tabOverview.applyLayout(toolbarPosition: context.browserLayout.tabOverviewToolbarPosition, animated: false)
        tabOverview.invalidateCollectionLayouts()
        tabOverview.reloadTabs()
        tabOverview.isHidden = false
        tabOverview.alpha = 0
        tabOverview.bottomToolbar.alpha = 0
        context.containerView.insertSubview(tabOverview, belowSubview: context.contentView)
        context.endEditing()
        context.setSearchFocused(false, animated: false)
        context.containerView.layoutIfNeeded()
        
        dismissalTargetTabIndex = selectedIndex
        let selectedCollection = tabOverview.currentCollectionView()
        if let selectedItem = tabOverview.itemIndex(forTabAt: selectedIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        if UIAccessibility.isReduceMotionEnabled {
            presentWithFade(chromeSnapshot: bottomChromeView)
            return
        }
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: selectedIndex),
              let bottomChromeView else {
            finishPresentationWithoutAnimation(chromeSnapshot: bottomChromeView)
            return
        }
        
        guard let previewImage = selectedCell.previewImage else {
            finishPresentationWithoutAnimation(chromeSnapshot: bottomChromeView)
            return
        }
        let transitionView = selectedCell.makeTransitionSnapshot()
        let pageSnapshot = makePageSnapshot(image: previewImage)
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: context.containerView)
        let closeButtonTransitionView = selectedCell.makeCloseButtonTransitionSnapshot(
            in: context.containerView,
            containerFrame: finalContentFrame
        )
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: context.containerView)
        let contentFrame = context.contentView.frame(in: context.containerView)
        guard let thumbnailGeometry = context.contentView.thumbnailGeometry(in: context.containerView) else {
            finishPresentationWithoutAnimation(chromeSnapshot: bottomChromeView)
            return
        }
        let fullImageFrame = thumbnailGeometry.fullFrame
        let visibleCropRect = thumbnailGeometry.cropRect
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        bottomChromeView.frame = context.browserChrome.bottomToolbarTransitionFrame(in: context.containerView)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        closeButtonTransitionView.transform = transitionView.transform
        configurePageSnapshot(
            pageSnapshot,
            containerFrame: fullImageFrame,
            clipFrame: fullImageFrame,
            imageFrame: aspectFillFrame(
                for: previewImage,
                cropRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
                in: fullImageFrame
            ),
            cornerRadius: 0
        )
        context.containerView.insertSubview(transitionView, belowSubview: context.contentView)
        context.containerView.insertSubview(pageSnapshot, aboveSubview: transitionView)
        context.containerView.insertSubview(closeButtonTransitionView, aboveSubview: pageSnapshot)
        
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setBottomToolbarHidden(true)
        
        let activePresentationTransition = ActivePresentationTransition(
            selectedTabCard: selectedCell,
            selectedCollectionView: selectedCollection,
            cardSnapshotView: transitionView,
            chromeSnapshotView: bottomChromeView,
            originalCollectionTransform: standardCollectionTransform
        )
        activePresentationTransition.pageSnapshotView = pageSnapshot
        activePresentationTransition.closeButtonSnapshotView = closeButtonTransitionView
        self.activePresentationTransition = activePresentationTransition
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut, .allowUserInteraction]) {
            transitionView.transform = .identity
            closeButtonTransitionView.transform = .identity
            self.configurePageSnapshot(
                pageSnapshot,
                containerFrame: fullImageFrame,
                clipFrame: finalPreviewFrame,
                imageFrame: self.aspectFillFrame(
                    for: previewImage,
                    cropRect: visibleCropRect,
                    in: finalPreviewFrame
                ),
                cornerRadius: UX.transitionPreviewCornerRadius
            )
            bottomChromeView.alpha = 0
            self.tabOverview.bottomToolbar.alpha = 1
            selectedCollection.transform = standardCollectionTransform
        } completion: { _ in
            self.completePresentationTransition(activePresentationTransition)
        }
    }
    
    private func dismissOnPhone() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.bottomToolbar.alpha = 1
        context.containerView.bringSubviewToFront(tabOverview)
        context.contentView.setTransitionTransform(.identity)
        context.containerView.layoutIfNeeded()
        
        let selectedCollection = tabOverview.currentCollectionView()
        selectedCollection.layoutIfNeeded()
        
        guard let selectedCell = selectedTabCard(at: overviewIndex),
              let sourceFrame = selectedTabCardPreviewFrame(at: overviewIndex),
              let collectionSnapshot = makeCollectionSnapshot(selectedCollection, hidingPreviewOf: selectedCell),
              let bottomChromeView = tabOverview.bottomToolbar.snapshotView(afterScreenUpdates: false) else {
            finishDismissalWithoutAnimation()
            return
        }
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex)
        guard let pageSnapshot else {
            finishDismissalWithoutAnimation()
            return
        }
        
        commitPendingTabSelection()
        context.updateLayout(animated: false, duration: 0)
        context.containerView.layoutIfNeeded()
        
        guard let thumbnailGeometry = context.contentView.thumbnailGeometry(in: context.containerView) else {
            finishDismissalWithoutAnimation(commitSelection: false)
            return
        }
        let fullImageFrame = thumbnailGeometry.fullFrame
        let visibleCropRect = thumbnailGeometry.cropRect
        
        configurePageSnapshot(
            pageSnapshot,
            containerFrame: fullImageFrame,
            clipFrame: sourceFrame,
            imageFrame: aspectFillFrame(
                for: pageSnapshot.image,
                cropRect: visibleCropRect,
                in: sourceFrame
            ),
            cornerRadius: UX.transitionPreviewCornerRadius
        )
        bottomChromeView.frame = tabOverview.bottomToolbar.frame
        
        context.containerView.addSubview(collectionSnapshot)
        context.containerView.addSubview(pageSnapshot)
        context.containerView.addSubview(bottomChromeView)
        selectedCollection.alpha = 0
        
        state = .dismissing
        presentationProgress = 0
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        
        context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 0, bottomTranslationY: 0)
        context.contentView.setTransitionHidden(true)
        tabOverview.bottomToolbar.alpha = 0
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            self.configurePageSnapshot(
                pageSnapshot,
                containerFrame: fullImageFrame,
                clipFrame: fullImageFrame,
                imageFrame: self.aspectFillFrame(
                    for: pageSnapshot.image,
                    cropRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
                    in: fullImageFrame
                ),
                cornerRadius: 0
            )
            bottomChromeView.alpha = 0
            self.tabOverview.alpha = 0
            collectionSnapshot.alpha = 0
            collectionSnapshot.transform = CGAffineTransform(
                scaleX: UX.transitionCollectionInitialScale,
                y: UX.transitionCollectionInitialScale
            )
            self.context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
        } completion: { _ in
            collectionSnapshot.removeFromSuperview()
            pageSnapshot.removeFromSuperview()
            bottomChromeView.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.context.contentView.setTransitionHidden(false)
            selectedCollection.alpha = 1
            self.tabOverview.collection.setPresentationVerticalOffset(0)
            self.tabOverview.isHidden = true
            self.tabOverview.bottomToolbar.alpha = 1
            self.state = .dismissed
            self.context.tabOverviewDidFinishDismissal()
        }
    }
    
    // MARK: - Pad Animations
    
    private func presentOnPad() {
        state = .presenting
        presentationProgress = 1
        activePresentationTransition = nil
        presentationToken += 1
        
        let overviewMode: TabOverview.Mode = dataSource.selectedTabMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = dataSource.selectedTabIndex
        context.containerView.layoutIfNeeded()
        let topChromeView = context.browserChrome.topToolbarTransitionView()
        context.prepareTabOverviewPresentation()
        dataSource.captureThumbnail(forTabAt: selectedIndex, mode: dataSource.selectedTabMode)
        if let topChromeView {
            topChromeView.frame = context.browserChrome.topToolbarTransitionFrame(in: context.containerView)
            context.containerView.addSubview(topChromeView)
        }
        animatePadPresentation(selectedIndex: selectedIndex, topChromeView: topChromeView)
    }
    
    private func animatePadPresentation(selectedIndex: Int, topChromeView: UIView?) {
        tabOverview.applyLayout(toolbarPosition: context.browserLayout.tabOverviewToolbarPosition, animated: false)
        tabOverview.invalidateCollectionLayouts()
        tabOverview.reloadTabs()
        tabOverview.isHidden = false
        tabOverview.alpha = 0
        tabOverview.setActiveToolbarAlpha(0)
        context.containerView.insertSubview(tabOverview, belowSubview: context.contentView)
        context.endEditing()
        context.containerView.layoutIfNeeded()
        
        dismissalTargetTabIndex = selectedIndex
        let selectedCollection = tabOverview.currentCollectionView()
        if let selectedItem = tabOverview.itemIndex(forTabAt: selectedIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        if UIAccessibility.isReduceMotionEnabled {
            presentWithFade(chromeSnapshot: topChromeView)
            return
        }
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: selectedIndex) else {
            finishPresentationWithoutAnimation(chromeSnapshot: topChromeView)
            return
        }
        
        guard let previewImage = selectedCell.previewImage else {
            finishPresentationWithoutAnimation(chromeSnapshot: topChromeView)
            return
        }
        let transitionView = selectedCell.makeTransitionSnapshot()
        let pageSnapshot = makePageSnapshot(image: previewImage)
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: context.containerView)
        let closeButtonTransitionView = selectedCell.makeCloseButtonTransitionSnapshot(
            in: context.containerView,
            containerFrame: finalContentFrame
        )
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: context.containerView)
        let contentFrame = context.contentView.frame(in: context.containerView)
        guard let thumbnailGeometry = context.contentView.thumbnailGeometry(in: context.containerView) else {
            finishPresentationWithoutAnimation(chromeSnapshot: topChromeView)
            return
        }
        let fullImageFrame = thumbnailGeometry.fullFrame
        let visibleCropRect = thumbnailGeometry.cropRect
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        topChromeView?.frame = context.browserChrome.topToolbarTransitionFrame(in: context.containerView)
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        closeButtonTransitionView.transform = transitionView.transform
        configurePageSnapshot(
            pageSnapshot,
            containerFrame: fullImageFrame,
            clipFrame: fullImageFrame,
            imageFrame: aspectFillFrame(
                for: previewImage,
                cropRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
                in: fullImageFrame
            ),
            cornerRadius: 0
        )
        context.containerView.insertSubview(transitionView, belowSubview: context.contentView)
        context.containerView.insertSubview(pageSnapshot, aboveSubview: transitionView)
        context.containerView.insertSubview(closeButtonTransitionView, aboveSubview: pageSnapshot)
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setBottomToolbarHidden(true)
        
        let activePresentationTransition = ActivePresentationTransition(
            selectedTabCard: selectedCell,
            selectedCollectionView: selectedCollection,
            cardSnapshotView: transitionView,
            chromeSnapshotView: topChromeView,
            originalCollectionTransform: standardCollectionTransform
        )
        activePresentationTransition.pageSnapshotView = pageSnapshot
        activePresentationTransition.closeButtonSnapshotView = closeButtonTransitionView
        self.activePresentationTransition = activePresentationTransition
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut, .allowUserInteraction]) {
            transitionView.transform = .identity
            closeButtonTransitionView.transform = .identity
            self.configurePageSnapshot(
                pageSnapshot,
                containerFrame: fullImageFrame,
                clipFrame: finalPreviewFrame,
                imageFrame: self.aspectFillFrame(
                    for: previewImage,
                    cropRect: visibleCropRect,
                    in: finalPreviewFrame
                ),
                cornerRadius: UX.transitionPreviewCornerRadius
            )
            topChromeView?.alpha = 0
            self.tabOverview.setActiveToolbarAlpha(1)
            selectedCollection.transform = standardCollectionTransform
            self.context.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 1, bottomTranslationY: 0)
            self.context.tabBar.setPresentationAlpha(0)
        } completion: { _ in
            self.completePresentationTransition(activePresentationTransition)
        }
    }
    
    private func dismissOnPad() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.setActiveToolbarAlpha(1)
        context.containerView.bringSubviewToFront(tabOverview)
        context.contentView.setTransitionTransform(.identity)
        context.containerView.layoutIfNeeded()
        
        let selectedCollection = tabOverview.currentCollectionView()
        if let selectedItem = tabOverview.itemIndex(forTabAt: overviewIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        guard let selectedCell = selectedTabCard(at: overviewIndex),
              let sourceFrame = selectedTabCardPreviewFrame(at: overviewIndex),
              let collectionSnapshot = makeCollectionSnapshot(selectedCollection, hidingPreviewOf: selectedCell) else {
            finishDismissalWithoutAnimation()
            return
        }
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex)
        guard let pageSnapshot else {
            finishDismissalWithoutAnimation()
            return
        }
        
        commitPendingTabSelection()
        context.updateLayout(animated: false, duration: 0)
        context.containerView.layoutIfNeeded()
        
        guard let thumbnailGeometry = context.contentView.thumbnailGeometry(in: context.containerView) else {
            finishDismissalWithoutAnimation(commitSelection: false)
            return
        }
        let fullImageFrame = thumbnailGeometry.fullFrame
        let visibleCropRect = thumbnailGeometry.cropRect
        
        configurePageSnapshot(
            pageSnapshot,
            containerFrame: fullImageFrame,
            clipFrame: sourceFrame,
            imageFrame: aspectFillFrame(
                for: pageSnapshot.image,
                cropRect: visibleCropRect,
                in: sourceFrame
            ),
            cornerRadius: UX.transitionPreviewCornerRadius
        )
        context.containerView.addSubview(collectionSnapshot)
        context.containerView.addSubview(pageSnapshot)
        selectedCollection.alpha = 0
        
        state = .dismissing
        presentationProgress = 0
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 0, bottomTranslationY: 0)
        context.tabBar.setPresentationAlpha(0)
        context.containerView.bringSubviewToFront(context.tabBar)
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            self.configurePageSnapshot(
                pageSnapshot,
                containerFrame: fullImageFrame,
                clipFrame: fullImageFrame,
                imageFrame: self.aspectFillFrame(
                    for: pageSnapshot.image,
                    cropRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
                    in: fullImageFrame
                ),
                cornerRadius: 0
            )
            self.tabOverview.alpha = 0
            collectionSnapshot.alpha = 0
            collectionSnapshot.transform = CGAffineTransform(
                scaleX: UX.transitionCollectionInitialScale,
                y: UX.transitionCollectionInitialScale
            )
            self.tabOverview.setActiveToolbarAlpha(0)
            self.context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
            self.context.tabBar.setPresentationAlpha(1)
        } completion: { _ in
            collectionSnapshot.removeFromSuperview()
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.context.contentView.setTransitionHidden(false)
            selectedCollection.alpha = 1
            self.tabOverview.collection.setPresentationVerticalOffset(0)
            self.tabOverview.isHidden = true
            self.tabOverview.setActiveToolbarAlpha(1)
            self.state = .dismissed
            self.context.tabOverviewDidFinishDismissal()
        }
    }
    
    private func presentWithFade(chromeSnapshot: UIView?) {
        let token = presentationToken
        context.containerView.bringSubviewToFront(tabOverview)
        tabOverview.setActiveToolbarAlpha(1)
        
        UIView.animate(withDuration: UX.reducedMotionFadeDuration) {
            self.tabOverview.alpha = 1
        } completion: { _ in
            chromeSnapshot?.removeFromSuperview()
            guard self.presentationToken == token else { return }
            
            self.context.updateLayout(animated: false, duration: 0)
            self.state = .presented
        }
    }
    
    private func dismissWithFade() {
        state = .dismissing
        presentationProgress = 0
        commitPendingTabSelection()
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        context.contentView.setTransitionTransform(.identity)
        context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
        context.tabBar.setPresentationAlpha(1)
        context.containerView.bringSubviewToFront(tabOverview)
        
        UIView.animate(withDuration: UX.reducedMotionFadeDuration) {
            self.tabOverview.alpha = 0
        } completion: { _ in
            self.tabOverview.isHidden = true
            self.state = .dismissed
            self.context.tabOverviewDidFinishDismissal()
        }
    }
    
    // MARK: - Transition Helpers
    
    private func tabs(for mode: TabMode) -> [Tab] {
        return mode == .private ? dataSource.privateTabs : dataSource.regularTabs
    }
    
    private func makeDismissalPreviewSnapshot(for index: Int) -> TabOverviewPageSnapshotView? {
        let mode = dismissalTargetTabMode ?? dataSource.selectedTabMode
        let tabs = tabs(for: mode)
        let image = pendingSelectionPreviewImage ?? tabs[safe: index]?.thumbnail
        guard let image else {
            return nil
        }
        
        return makePageSnapshot(image: image)
    }
    
    private func makePageSnapshot(image: UIImage) -> TabOverviewPageSnapshotView {
        return TabOverviewPageSnapshotView(image: image)
    }
    
    private func makeCollectionSnapshot(
        _ collectionView: UICollectionView,
        hidingPreviewOf selectedCell: TabOverviewCard
    ) -> UIView? {
        selectedCell.setPreviewSurfaceHidden(true)
        defer { selectedCell.setPreviewSurfaceHidden(false) }
        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: true) else {
            return nil
        }
        snapshot.frame = collectionView.convert(collectionView.bounds, to: context.containerView)
        return snapshot
    }
    
    private func configurePageSnapshot(
        _ snapshot: TabOverviewPageSnapshotView,
        containerFrame: CGRect,
        clipFrame: CGRect,
        imageFrame: CGRect,
        cornerRadius: CGFloat
    ) {
        snapshot.frame = containerFrame
        snapshot.setFrames(
            clipFrame: clipFrame.offsetBy(dx: -containerFrame.minX, dy: -containerFrame.minY),
            imageFrame: imageFrame.offsetBy(dx: -clipFrame.minX, dy: -clipFrame.minY)
        )
        snapshot.setPreviewStyle(cornerRadius: cornerRadius)
    }
    
    private func aspectFillFrame(
        for image: UIImage,
        cropRect: CGRect,
        in containerFrame: CGRect
    ) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0,
              imageSize.height > 0,
              cropRect.width > 0,
              cropRect.height > 0,
              containerFrame.width > 0,
              containerFrame.height > 0 else {
            return containerFrame
        }
        
        let cropSize = CGSize(
            width: imageSize.width * cropRect.width,
            height: imageSize.height * cropRect.height
        )
        let scale = max(
            containerFrame.width / cropSize.width,
            containerFrame.height / cropSize.height
        )
        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let scaledCropSize = CGSize(
            width: cropSize.width * scale,
            height: cropSize.height * scale
        )
        let cropOrigin = CGPoint(
            x: containerFrame.midX - (scaledCropSize.width / 2),
            y: containerFrame.midY - (scaledCropSize.height / 2)
        )
        return CGRect(
            x: cropOrigin.x - (cropRect.minX * scaledSize.width),
            y: cropOrigin.y - (cropRect.minY * scaledSize.height),
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
    
    private func bringBrowserChromeToFrontForDismissal() {
        context.containerView.bringSubviewToFront(context.browserChrome)
    }
    
    private func cancelPresentationForImmediateDismissal() {
        presentationToken += 1
        if let activePresentationTransition {
            finishPresentationTransition(activePresentationTransition)
            self.activePresentationTransition = nil
        }
        
        tabOverview.layer.removeAllAnimations()
        context.contentView.layer.removeAllAnimations()
        context.browserChrome.layer.removeAllAnimations()
        for collectionView in tabOverview.collection.allCollectionViews {
            collectionView.layer.removeAllAnimations()
            collectionView.alpha = 1
        }
        
        context.containerView.bringSubviewToFront(tabOverview)
        context.contentView.setTransitionHidden(false)
        context.browserChrome.setBottomToolbarHidden(false)
        presentationProgress = 1
        tabOverview.alpha = 1
        tabOverview.collection.setPresentationVerticalOffset(0)
        context.contentView.setTransitionTransform(.identity)
        tabOverview.setActiveToolbarAlpha(1)
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        state = .presented
    }
    
    func finishPresentationForScrolling(in collectionView: UICollectionView) {
        guard let transition = activePresentationTransition,
              transition.selectedCollectionView === collectionView else {
            return
        }
        completePresentationTransition(transition)
    }
    
    private func completePresentationTransition(_ transition: ActivePresentationTransition) {
        guard activePresentationTransition === transition else {
            return
        }
        finishPresentationTransition(transition)
        activePresentationTransition = nil
        
        context.containerView.bringSubviewToFront(tabOverview)
        context.contentView.setTransitionHidden(false)
        context.browserChrome.setBottomToolbarHidden(false)
        context.updateLayout(animated: false, duration: 0)
        state = .presented
    }
    
    private func finishPresentationTransition(_ transition: ActivePresentationTransition) {
        transition.cardSnapshotView?.layer.removeAllAnimations()
        transition.closeButtonSnapshotView?.layer.removeAllAnimations()
        transition.pageSnapshotView?.layer.removeAllAnimations()
        transition.chromeSnapshotView?.layer.removeAllAnimations()
        transition.selectedCollectionView?.layer.removeAllAnimations()
        transition.chromeSnapshotView?.removeFromSuperview()
        transition.cardSnapshotView?.removeFromSuperview()
        transition.closeButtonSnapshotView?.removeFromSuperview()
        transition.pageSnapshotView?.removeFromSuperview()
        transition.selectedTabCard?.setTransitionState(.visible)
        transition.selectedCollectionView?.transform = transition.originalCollectionTransform
    }
    
    private func webpagePreviewTransitionTransform(contentFrame: CGRect, previewFrame: CGRect, sourceFrame: CGRect) -> CGAffineTransform {
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
    
    private func dismissalAnimationTabIndex() -> Int {
        let mode = dismissalTargetTabMode ?? dataSource.selectedTabMode
        let tabs = tabs(for: mode)
        let selectedIndex = mode == dataSource.selectedTabMode ? dataSource.selectedTabIndex : 0
        let candidate = dismissalTargetTabIndex ?? selectedIndex
        if tabs.indices.contains(candidate) {
            return candidate
        }
        return min(max(selectedIndex, 0), max(tabs.count - 1, 0))
    }
    
    private func commitPendingTabSelection() {
        defer {
            pendingSelectionTabIndex = nil
            dismissalTargetTabIndex = nil
            dismissalTargetTabMode = nil
            pendingSelectionTabMode = nil
            pendingSelectionPreviewImage = nil
        }
        
        guard let target = pendingSelectionTabIndex,
              let mode = pendingSelectionTabMode else {
            return
        }
        let targetTabs = tabs(for: mode)
        guard targetTabs.indices.contains(target) else {
            return
        }
        
        dataSource.selectTab(at: target, mode: mode)
    }
    
    private func selectedTabCard(at index: Int) -> TabOverviewCard? {
        let tabMode = dismissalTargetTabMode ?? dataSource.selectedTabMode
        let tabs = tabs(for: tabMode)
        guard tabs.indices.contains(index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        let collectionView = tabOverview.collection.collectionView(for: TabOverview.Mode(tabMode: tabMode))
        return collectionView.cellForItem(at: indexPath) as? TabOverviewCard
    }
    
    private func selectedTabCardPreviewFrame(at index: Int) -> CGRect? {
        guard let cell = selectedTabCard(at: index) else {
            return nil
        }
        return cell.webpagePreviewRegionFrame(in: context.containerView)
    }
}

private final class TabOverviewPageSnapshotView: UIView {
    private enum UX {
        static let borderWidth: CGFloat = 0.5
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 8
        static let shadowOffset = CGSize(width: 0, height: 3)
    }
    
    let image: UIImage
    private let shadowView: UIView
    private let clippingView: UIView
    private let imageView: UIImageView
    
    init(image: UIImage) {
        self.image = image
        shadowView = UIView()
        clippingView = UIView()
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        clipsToBounds = false
        isUserInteractionEnabled = false
        shadowView.backgroundColor = .systemBackground
        shadowView.layer.cornerCurve = .continuous
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0
        shadowView.layer.shadowRadius = UX.shadowRadius
        shadowView.layer.shadowOffset = UX.shadowOffset
        clippingView.clipsToBounds = true
        clippingView.layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor
        imageView.contentMode = .scaleToFill
        addSubview(shadowView)
        addSubview(clippingView)
        clippingView.addSubview(imageView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setFrames(clipFrame: CGRect, imageFrame: CGRect) {
        shadowView.frame = clipFrame
        clippingView.frame = clipFrame
        imageView.frame = imageFrame
    }
    
    func setPreviewStyle(cornerRadius: CGFloat) {
        let displaysCardStyle = cornerRadius > 0
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.layer.shadowOpacity = displaysCardStyle ? UX.shadowOpacity : 0
        clippingView.layer.cornerRadius = cornerRadius
        clippingView.layer.cornerCurve = .continuous
        clippingView.layer.borderWidth = displaysCardStyle ? UX.borderWidth : 0
    }
}

private final class ActivePresentationTransition {
    weak var selectedTabCard: TabOverviewCard?
    weak var selectedCollectionView: UICollectionView?
    weak var cardSnapshotView: UIView?
    weak var closeButtonSnapshotView: UIView?
    weak var pageSnapshotView: UIView?
    weak var chromeSnapshotView: UIView?
    let originalCollectionTransform: CGAffineTransform
    
    init(
        selectedTabCard: TabOverviewCard,
        selectedCollectionView: UICollectionView,
        cardSnapshotView: UIView,
        chromeSnapshotView: UIView?,
        originalCollectionTransform: CGAffineTransform
    ) {
        self.selectedTabCard = selectedTabCard
        self.selectedCollectionView = selectedCollectionView
        self.cardSnapshotView = cardSnapshotView
        self.chromeSnapshotView = chromeSnapshotView
        self.originalCollectionTransform = originalCollectionTransform
    }
}
