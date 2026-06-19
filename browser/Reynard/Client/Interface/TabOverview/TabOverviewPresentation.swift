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
        tabOverview.collection.applyPresentationTransforms()
    }
    
    // MARK: - Selection
    
    func prepareDismissSelection(to index: Int, mode: TabMode, previewImage: UIImage?) {
        let selectedIndex = dataSource.selectedMode == mode ? dataSource.selectedIndex : nil
        dismissalTargetTabIndex = index
        dismissalTargetTabMode = mode
        pendingSelectionTabIndex = index == selectedIndex ? nil : index
        pendingSelectionTabMode = mode
        pendingSelectionPreviewImage = previewImage
    }
    
    // MARK: - Presentation
    
    func setPresented(_ visible: Bool, animated: Bool) {
        if isTransitionRunning {
            return
        }
        
        if visible == isPresented, presentationProgress == (visible ? 1 : 0) {
            return
        }
        
        if animated {
            if context.browserLayout.chromeMode != .phone {
                visible ? presentOnPad() : dismissOnPad()
            } else {
                visible ? presentOnPhone() : dismissOnPhone()
            }
            return
        }
        
        if visible {
            let overviewMode: TabOverview.Mode = dataSource.selectedMode == .private ? .privateTabs : .regularTabs
            tabOverview.setMode(overviewMode, animated: false)
            dismissalTargetTabIndex = dataSource.selectedIndex
            pendingSelectionTabIndex = nil
            pendingSelectionTabMode = nil
            pendingSelectionPreviewImage = nil
            dataSource.captureThumbnailForVisibleTab(at: dataSource.selectedIndex)
            tabOverview.reloadTabs()
            tabOverview.isHidden = false
            context.containerView.bringSubviewToFront(tabOverview)
            context.endEditing()
            context.setSearchFocused(false, animated: true)
        }
        
        let finalProgress: CGFloat = visible ? 1 : 0
        applyPresentationProgress(finalProgress)
        
        state = visible ? .presented : .dismissed
        if !visible {
            commitPendingTabSelection()
            tabOverview.isHidden = true
            applyPresentationProgress(0)
        }
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
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
    
    // MARK: - Phone Animations
    
    private func presentOnPhone() {
        state = .presenting
        presentationProgress = 1
        
        let overviewMode: TabOverview.Mode = dataSource.selectedMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = dataSource.selectedIndex
        context.containerView.layoutIfNeeded()
        let bottomSnapshot = context.browserChrome.bottomToolbarSnapshot()
        context.updateLayout(animated: false, duration: 0)
        dataSource.captureThumbnailForVisibleTab(at: selectedIndex)
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
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: selectedIndex),
              let bottomSnapshot else {
            state = .presented
            applyPresentationProgress(1)
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        guard let transitionView = selectedCell.makeTransitionSnapshot() else {
            state = .presented
            applyPresentationProgress(1)
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: context.containerView)
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: context.containerView)
        let contentFrame = context.contentView.frame
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        bottomSnapshot.frame = context.browserChrome.bottomToolbarFrame(in: context.containerView)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        context.containerView.insertSubview(transitionView, belowSubview: context.contentView)
        context.containerView.addSubview(bottomSnapshot)
        
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setBottomToolbarHidden(true)
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            bottomSnapshot.alpha = 0
            self.tabOverview.bottomToolbar.alpha = 1
            selectedCollection.transform = standardCollectionTransform
        } completion: { _ in
            bottomSnapshot.removeFromSuperview()
            transitionView.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.context.containerView.bringSubviewToFront(self.tabOverview)
            self.context.contentView.setTransitionHidden(false)
            self.context.updateLayout(animated: false, duration: 0)
            self.state = .presented
        }
    }
    
    private func dismissOnPhone() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.bottomToolbar.alpha = 1
        context.containerView.bringSubviewToFront(tabOverview)
        context.containerView.layoutIfNeeded()
        
        let selectedCollection = tabOverview.currentCollectionView()
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: overviewIndex),
              let sourceFrame = selectedTabCardPreviewFrame(at: overviewIndex),
              let bottomSnapshot = tabOverview.bottomToolbar.snapshotView(afterScreenUpdates: false) else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex) ?? selectedCell.makeWebpagePreviewRegionSnapshot()
        guard let pageSnapshot else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = UX.transitionPreviewCornerRadius
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        bottomSnapshot.frame = tabOverview.bottomToolbar.frame
        
        context.containerView.addSubview(pageSnapshot)
        context.containerView.addSubview(bottomSnapshot)
        
        commitPendingTabSelection()
        state = .dismissing
        presentationProgress = 0
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        
        context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 0, bottomTranslationY: 0)
        context.contentView.setTransitionHidden(true)
        tabOverview.bottomToolbar.alpha = 0
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.context.contentView.frame
            pageSnapshot.layer.cornerRadius = 0
            bottomSnapshot.alpha = 0
            self.tabOverview.alpha = 0
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
            self.context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            bottomSnapshot.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            selectedCollection.transform = standardCollectionTransform
            
            self.context.contentView.setTransitionHidden(false)
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 1
            }
            self.tabOverview.collection.setPresentationVerticalOffset(0)
            self.tabOverview.isHidden = true
            self.tabOverview.bottomToolbar.alpha = 1
            self.state = .dismissed
        }
    }
    
    // MARK: - Pad Animations
    
    private func presentOnPad() {
        state = .presenting
        presentationProgress = 1
        
        let overviewMode: TabOverview.Mode = dataSource.selectedMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = dataSource.selectedIndex
        context.updateLayout(animated: false, duration: 0)
        dataSource.captureThumbnailForVisibleTab(at: selectedIndex)
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
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: selectedIndex) else {
            state = .presented
            applyPresentationProgress(1)
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        guard let transitionView = selectedCell.makeTransitionSnapshot() else {
            state = .presented
            applyPresentationProgress(1)
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: context.containerView)
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: context.containerView)
        let contentFrame = context.contentView.frame
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        context.containerView.insertSubview(transitionView, belowSubview: context.contentView)
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setBottomToolbarHidden(true)
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            self.tabOverview.setActiveToolbarAlpha(1)
            selectedCollection.transform = standardCollectionTransform
            self.context.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 1, bottomTranslationY: 0)
        } completion: { _ in
            transitionView.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.context.containerView.bringSubviewToFront(self.tabOverview)
            self.context.contentView.setTransitionHidden(false)
            self.context.updateLayout(animated: false, duration: 0)
            self.state = .presented
        }
    }
    
    private func dismissOnPad() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.setActiveToolbarAlpha(1)
        context.containerView.bringSubviewToFront(tabOverview)
        context.containerView.layoutIfNeeded()
        
        let selectedCollection = tabOverview.currentCollectionView()
        if let selectedItem = tabOverview.itemIndex(forTabAt: overviewIndex) {
            selectedCollection.scrollToItem(at: IndexPath(item: selectedItem, section: 0), at: .centeredVertically, animated: false)
        }
        selectedCollection.layoutIfNeeded()
        
        let standardCollectionTransform = selectedCollection.transform
        
        guard let selectedCell = selectedTabCard(at: overviewIndex),
              let sourceFrame = selectedTabCardPreviewFrame(at: overviewIndex) else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex) ?? selectedCell.makeWebpagePreviewRegionSnapshot()
        guard let pageSnapshot else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            context.updateLayout(animated: false, duration: 0)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = UX.transitionPreviewCornerRadius
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        context.containerView.addSubview(pageSnapshot)
        
        commitPendingTabSelection()
        state = .dismissing
        presentationProgress = 0
        context.updateLayout(animated: false, duration: 0)
        context.tabBar.updateLayout()
        
        context.contentView.setTransitionHidden(true)
        context.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 0, bottomTranslationY: 0)
        context.tabBar.setPresentationAlpha(0)
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.context.contentView.frame
            pageSnapshot.layer.cornerRadius = 0
            self.tabOverview.alpha = 0
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
            self.tabOverview.setActiveToolbarAlpha(0)
            self.context.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
            self.context.tabBar.setPresentationAlpha(1)
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            selectedCollection.transform = standardCollectionTransform
            
            self.context.contentView.setTransitionHidden(false)
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 1
            }
            self.tabOverview.collection.setPresentationVerticalOffset(0)
            self.tabOverview.isHidden = true
            self.tabOverview.setActiveToolbarAlpha(1)
            self.state = .dismissed
        }
    }
    
    // MARK: - Transition Helpers
    
    private func tabs(for mode: TabMode) -> [Tab] {
        return mode == .private ? dataSource.privateTabs : dataSource.regularTabs
    }
    
    private func makeDismissalPreviewSnapshot(for index: Int) -> UIView? {
        let mode = dismissalTargetTabMode ?? dataSource.selectedMode
        let tabs = tabs(for: mode)
        let image = pendingSelectionPreviewImage ?? tabs[safe: index]?.thumbnail
        guard let image else {
            return nil
        }
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = UX.transitionPreviewCornerRadius
        imageView.layer.cornerCurve = .continuous
        return imageView
    }
    
    private func bringBrowserChromeToFrontForDismissal() {
        context.containerView.bringSubviewToFront(context.browserChrome)
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
        let mode = dismissalTargetTabMode ?? dataSource.selectedMode
        let tabs = tabs(for: mode)
        let selectedIndex = mode == dataSource.selectedMode ? dataSource.selectedIndex : 0
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
        
        let selectedIndex = pendingSelectionTabMode == dataSource.selectedMode ? dataSource.selectedIndex : nil
        guard let target = pendingSelectionTabIndex,
              target != selectedIndex,
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
        let tabMode = dismissalTargetTabMode ?? dataSource.selectedMode
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
