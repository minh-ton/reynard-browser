//
//  TabOverviewPresentation.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewPresentation {
    // MARK: - UX

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

    // MARK: - State

    enum State {
        case dismissed
        case presenting
        case presented
        case dismissing
    }

    private unowned let tabOverview: TabOverview

    private var browser: BrowserViewController {
        guard let browser = tabOverview.browserViewController else {
            preconditionFailure("TabOverview requires a browser view controller")
        }
        return browser
    }
    
    private var presentationProgress: CGFloat = 0
    private var dismissalTargetTabIndex: Int?
    private var dismissalTargetTabMode: TabMode?
    private var pendingSelectionTabIndex: Int?
    private var pendingSelectionTabMode: TabMode?
    private var pendingSelectionPreviewImage: UIImage?
    
    private(set) var state: State = .dismissed

    var isPresented: Bool {
        state == .presented || state == .presenting
    }

    var isTransitionRunning: Bool {
        state == .presenting || state == .dismissing
    }
    
    // MARK: - Lifecycle

    init(tabOverview: TabOverview) {
        self.tabOverview = tabOverview
    }
    
    // MARK: - Layout

    func cardSize(in collectionView: UICollectionView) -> CGSize {
        let horizontalInsets = collectionView.adjustedContentInset.left + collectionView.adjustedContentInset.right
        let availableWidth = collectionView.bounds.width - horizontalInsets
        let tabViewAspectRatio = max(UX.cardMinimumPreviewAspectRatio, browser.tabPreviewAspectRatio())
        
        let targetWidth = browser.browserLayout.browserChromeMode == .phone
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
        let selectedIndex = browser.tabManager.selectedTabMode == mode ? browser.tabManager.selectedTabIndex : nil
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
            if browser.browserLayout.browserChromeMode != .phone {
                visible ? presentOnPad() : dismissOnPad()
            } else {
                visible ? presentOnPhone() : dismissOnPhone()
            }
            return
        }
        
        if visible {
            let overviewMode: TabOverview.Mode = browser.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
            tabOverview.setMode(overviewMode, animated: false)
            dismissalTargetTabIndex = browser.tabManager.selectedTabIndex
            pendingSelectionTabIndex = nil
            pendingSelectionTabMode = nil
            pendingSelectionPreviewImage = nil
            browser.captureThumbnail(for: browser.tabManager.selectedTabIndex)
            tabOverview.reloadTabs()
            tabOverview.isHidden = false
            browser.view.bringSubviewToFront(tabOverview)
            browser.view.endEditing(true)
            browser.searchOverlayCoordinator.setFocused(false, animated: true)
        }
        
        let finalProgress: CGFloat = visible ? 1 : 0
        applyPresentationProgress(finalProgress)
        
        state = visible ? .presented : .dismissed
        if !visible {
            commitPendingTabSelection()
            tabOverview.isHidden = true
            applyPresentationProgress(0)
        }
        browser.updateBrowserLayout(animated: false, duration: 0)
        browser.tabBar.updateLayout()
    }

    // MARK: - Presentation Progress

    func applyPresentationProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        presentationProgress = clamped
        
        tabOverview.alpha = clamped
        
        let collectionOffset = (1 - clamped) * UX.hiddenCollectionVerticalOffset
        tabOverview.collection.setPresentationVerticalOffset(collectionOffset)
        
        let pageScale = 1 - (UX.presentedPageScaleReduction * clamped)
        browser.contentView.setTransitionTransform(CGAffineTransform(scaleX: pageScale, y: pageScale))
        
        if browser.browserLayout.browserChromeMode != .phone {
            browser.browserChrome.setChromeTransition(topAlpha: 1 - clamped, bottomAlpha: 1, bottomTranslationY: 0)
        } else {
            browser.browserChrome.setChromeTransition(
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
        
        let overviewMode: TabOverview.Mode = browser.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = browser.tabManager.selectedTabIndex
        browser.view.layoutIfNeeded()
        let bottomSnapshot = browser.browserChrome.bottomToolbarSnapshot()
        browser.updateBrowserLayout(animated: false, duration: 0)
        browser.captureThumbnail(for: selectedIndex)
        tabOverview.invalidateCollectionLayouts()
        tabOverview.reloadTabs()
        tabOverview.isHidden = false
        tabOverview.alpha = 0
        tabOverview.bottomToolbar.alpha = 0
        browser.view.insertSubview(tabOverview, belowSubview: browser.contentView)
        browser.view.endEditing(true)
        browser.searchOverlayCoordinator.setFocused(false, animated: false)
        browser.view.layoutIfNeeded()
        
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
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        guard let transitionView = selectedCell.makeTransitionSnapshot() else {
            state = .presented
            applyPresentationProgress(1)
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: browser.view)
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: browser.view)
        let contentFrame = browser.contentView.frame
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        bottomSnapshot.frame = browser.browserChrome.bottomToolbarFrame(in: browser.view)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        browser.view.insertSubview(transitionView, belowSubview: browser.contentView)
        browser.view.addSubview(bottomSnapshot)
        
        browser.contentView.setTransitionHidden(true)
        browser.browserChrome.setBottomToolbarHidden(true)
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            bottomSnapshot.alpha = 0
            self.tabOverview.bottomToolbar.alpha = 1
            selectedCollection.transform = standardCollectionTransform
        } completion: { _ in
            bottomSnapshot.removeFromSuperview()
            transitionView.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.browser.view.bringSubviewToFront(self.tabOverview)
            self.browser.contentView.setTransitionHidden(false)
            self.browser.updateBrowserLayout(animated: false, duration: 0)
            self.state = .presented
        }
    }
    
    private func dismissOnPhone() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.bottomToolbar.alpha = 1
        browser.view.bringSubviewToFront(tabOverview)
        browser.view.layoutIfNeeded()
        
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
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex) ?? selectedCell.makeWebpagePreviewRegionSnapshot()
        guard let pageSnapshot else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = UX.transitionPreviewCornerRadius
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        bottomSnapshot.frame = tabOverview.bottomToolbar.frame
        
        browser.view.addSubview(pageSnapshot)
        browser.view.addSubview(bottomSnapshot)
        
        commitPendingTabSelection()
        state = .dismissing
        presentationProgress = 0
        browser.updateBrowserLayout(animated: false, duration: 0)
        browser.tabBar.updateLayout()
        
        browser.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 0, bottomTranslationY: 0)
        browser.contentView.setTransitionHidden(true)
        tabOverview.bottomToolbar.alpha = 0
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.browser.contentView.frame
            pageSnapshot.layer.cornerRadius = 0
            bottomSnapshot.alpha = 0
            self.tabOverview.alpha = 0
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
            self.browser.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            bottomSnapshot.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            selectedCollection.transform = standardCollectionTransform
            
            self.browser.contentView.setTransitionHidden(false)
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
        
        let overviewMode: TabOverview.Mode = browser.tabManager.selectedTabMode == .private ? .privateTabs : .regularTabs
        tabOverview.setMode(overviewMode, animated: false)
        let selectedIndex = browser.tabManager.selectedTabIndex
        browser.updateBrowserLayout(animated: false, duration: 0)
        browser.captureThumbnail(for: selectedIndex)
        tabOverview.invalidateCollectionLayouts()
        tabOverview.reloadTabs()
        tabOverview.isHidden = false
        tabOverview.alpha = 0
        tabOverview.setActiveToolbarAlpha(0)
        browser.view.insertSubview(tabOverview, belowSubview: browser.contentView)
        browser.view.endEditing(true)
        browser.view.layoutIfNeeded()
        
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
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        guard let transitionView = selectedCell.makeTransitionSnapshot() else {
            state = .presented
            applyPresentationProgress(1)
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        let finalContentFrame = selectedCell.transitionSnapshotFrame(in: browser.view)
        let finalPreviewFrame = selectedCell.webpagePreviewImageFrame(in: browser.view)
        let contentFrame = browser.contentView.frame
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        tabOverview.alpha = 1
        selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
        
        transitionView.frame = finalContentFrame
        transitionView.transform = webpagePreviewTransitionTransform(
            contentFrame: finalContentFrame,
            previewFrame: finalPreviewFrame,
            sourceFrame: contentFrame
        )
        browser.view.insertSubview(transitionView, belowSubview: browser.contentView)
        browser.contentView.setTransitionHidden(true)
        browser.browserChrome.setBottomToolbarHidden(true)
        
        UIView.animate(withDuration: UX.presentationAnimationDuration, delay: 0, usingSpringWithDamping: UX.presentationSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            transitionView.transform = .identity
            self.tabOverview.setActiveToolbarAlpha(1)
            selectedCollection.transform = standardCollectionTransform
            self.browser.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 1, bottomTranslationY: 0)
        } completion: { _ in
            transitionView.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            
            self.browser.view.bringSubviewToFront(self.tabOverview)
            self.browser.contentView.setTransitionHidden(false)
            self.browser.updateBrowserLayout(animated: false, duration: 0)
            self.state = .presented
        }
    }
    
    private func dismissOnPad() {
        state = .dismissing
        let overviewIndex = dismissalAnimationTabIndex()
        
        tabOverview.isHidden = false
        tabOverview.alpha = 1
        tabOverview.setActiveToolbarAlpha(1)
        browser.view.bringSubviewToFront(tabOverview)
        browser.view.layoutIfNeeded()
        
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
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        selectedCell.setTransitionState(.hiddenForAnimation)
        
        let pageSnapshot = makeDismissalPreviewSnapshot(for: overviewIndex) ?? selectedCell.makeWebpagePreviewRegionSnapshot()
        guard let pageSnapshot else {
            state = .dismissed
            applyPresentationProgress(0)
            tabOverview.isHidden = true
            commitPendingTabSelection()
            browser.updateBrowserLayout(animated: false, duration: 0)
            return
        }
        
        pageSnapshot.frame = sourceFrame
        pageSnapshot.layer.cornerRadius = UX.transitionPreviewCornerRadius
        pageSnapshot.layer.cornerCurve = .continuous
        pageSnapshot.layer.masksToBounds = true
        
        browser.view.addSubview(pageSnapshot)
        
        commitPendingTabSelection()
        state = .dismissing
        presentationProgress = 0
        browser.updateBrowserLayout(animated: false, duration: 0)
        browser.tabBar.updateLayout()
        
        browser.contentView.setTransitionHidden(true)
        browser.browserChrome.setChromeTransition(topAlpha: 0, bottomAlpha: 0, bottomTranslationY: 0)
        browser.tabBar.setPresentationAlpha(0)
        bringBrowserChromeToFrontForDismissal()
        
        UIView.animate(withDuration: UX.dismissalAnimationDuration, delay: 0, usingSpringWithDamping: UX.dismissalSpringDamping, initialSpringVelocity: 1, options: [.curveEaseInOut]) {
            pageSnapshot.frame = self.browser.contentView.frame
            pageSnapshot.layer.cornerRadius = 0
            self.tabOverview.alpha = 0
            for collectionView in self.tabOverview.collection.allCollectionViews {
                collectionView.alpha = 0
            }
            selectedCollection.transform = standardCollectionTransform.scaledBy(x: UX.transitionCollectionInitialScale, y: UX.transitionCollectionInitialScale)
            self.tabOverview.setActiveToolbarAlpha(0)
            self.browser.browserChrome.setChromeTransition(topAlpha: 1, bottomAlpha: 1, bottomTranslationY: 0)
            self.browser.tabBar.setPresentationAlpha(1)
        } completion: { _ in
            pageSnapshot.removeFromSuperview()
            selectedCell.setTransitionState(.visible)
            selectedCollection.transform = standardCollectionTransform
            
            self.browser.contentView.setTransitionHidden(false)
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
        mode == .private ? browser.tabManager.privateTabs : browser.tabManager.regularTabs
    }

    private func makeDismissalPreviewSnapshot(for index: Int) -> UIView? {
        let mode = dismissalTargetTabMode ?? browser.tabManager.selectedTabMode
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
        browser.view.bringSubviewToFront(browser.browserChrome)
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
        let mode = dismissalTargetTabMode ?? browser.tabManager.selectedTabMode
        let tabs = tabs(for: mode)
        let selectedIndex = mode == browser.tabManager.selectedTabMode ? browser.tabManager.selectedTabIndex : 0
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
        
        let selectedIndex = pendingSelectionTabMode == browser.tabManager.selectedTabMode ? browser.tabManager.selectedTabIndex : nil
        guard let target = pendingSelectionTabIndex,
              target != selectedIndex,
              let mode = pendingSelectionTabMode else {
            return
        }
        let targetTabs = tabs(for: mode)
        guard targetTabs.indices.contains(target) else {
            return
        }
        
        browser.tabManager.selectTab(at: target, mode: mode)
    }
    
    private func selectedTabCard(at index: Int) -> TabOverviewCard? {
        let tabMode = dismissalTargetTabMode ?? browser.tabManager.selectedTabMode
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
        return cell.webpagePreviewRegionFrame(in: browser.view)
    }
}
