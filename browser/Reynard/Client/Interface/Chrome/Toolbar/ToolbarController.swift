//
//  ToolbarController.swift
//  Reynard
//
//  Created by Minh Ton on 4/8/26.
//

import UIKit

final class ToolbarController {
    enum LockReason: Hashable {
        case addressBarTransition
        case addressBarEditing
        case historyNavigation
        case pageNavigation
        case homepageOverlay
        case searchOverlay
        case tabOverview
        case viewPresentation
        case addonPopover
    }
    
    private enum UX {
        static let toolbarScrollFactor: CGFloat = 0.8
        static let maximumTransitionSpeed: CGFloat = 600
        static let snapDelay: TimeInterval = 0.1
        static let snapDuration: TimeInterval = 0.3
    }
    
    private unowned let browserChrome: BrowserChrome
    private unowned let tabBar: TabBar
    private unowned let contentView: ContentView
    private unowned let rootView: UIView
    
    private var chromeMode: BrowserChromeMode = .phone
    private var transitionOffset: CGFloat = 0
    private var textCenteringDistance: CGFloat = 0
    private var maxToolbarOffset: CGFloat = 0
    private var maxTopToolbarOffset: CGFloat = 0
    private var scrollPosition: CGFloat = 0
    private var snapOrigin: CGFloat = 0
    private var targetOffset: CGFloat = 0
    private var snapStartTime: CFTimeInterval?
    private var lastAnimationTime: CFTimeInterval = 0
    private var pendingSnap: DispatchWorkItem?
    private var animationDisplayLink: CADisplayLink?
    private var isBottomToolbarCollapsed = false
    private var lockReasons = Set<LockReason>()
    
    // MARK: - Lifecycle
    
    init(
        browserChrome: BrowserChrome,
        tabBar: TabBar,
        contentView: ContentView,
        rootView: UIView
    ) {
        self.browserChrome = browserChrome
        self.tabBar = tabBar
        self.contentView = contentView
        self.rootView = rootView
        
        browserChrome.onToolbarExpansionRequested = { [weak self] in
            self?.contentView.resetScrollTracking()
            self?.reset()
        }
        
        let historySwipeHandler = contentView.onHistorySwipeBegan
        contentView.onHistorySwipeBegan = { [weak self] in
            self?.lock(for: .historyNavigation)
            historySwipeHandler?()
        }
        
        contentView.onHistorySwipeEnded = { [weak self] in
            self?.unlock(for: .historyNavigation)
        }
        
        contentView.onVerticalScroll = { [weak self] scrollDelta, position in
            self?.handleScroll(delta: scrollDelta, position: position)
        }
    }
    
    deinit {
        cancelAnimation()
    }
    
    // MARK: - Layout
    
    func updateLayout(
        chromeMode: BrowserChromeMode,
        isToolbarEnabled: Bool,
        extendsContentBehindToolbar: Bool
    ) {
        let offsetLimits = toolbarOffsetLimits(for: chromeMode)
        let canHideToolbar = isToolbarEnabled
        && Prefs.AppearanceSettings.scrollToHideToolbarEnabled
        let minimizedHeight = browserChrome.minimizedToolbarHeight(for: chromeMode)
        let retainedTopHeight = chromeMode == .phone ? 0 : minimizedHeight
        let maxToolbarOffset = canHideToolbar ? max(0, offsetLimits.total - minimizedHeight) : 0
        let maxTopToolbarOffset = canHideToolbar ? max(0, offsetLimits.top - retainedTopHeight) : 0
        
        let webContentBottomOffset = isToolbarEnabled && !canHideToolbar && !extendsContentBehindToolbar
        ? offsetLimits.top - offsetLimits.total
        : 0
        
        if self.chromeMode != chromeMode
            || abs(maxToolbarOffset - self.maxToolbarOffset) > 0.5
            || abs(maxTopToolbarOffset - self.maxTopToolbarOffset) > 0.5 {
            reset(animated: false)
            self.chromeMode = chromeMode
            self.maxToolbarOffset = maxToolbarOffset
            self.maxTopToolbarOffset = maxTopToolbarOffset
        }
        contentView.setToolbarLimits(
            maxHeight: canHideToolbar ? offsetLimits.total : 0,
            contentTopInset: canHideToolbar ? offsetLimits.top : 0,
            contentBottomInset: canHideToolbar && chromeMode == .phone ? minimizedHeight : 0,
            webContentBottomOffset: webContentBottomOffset
        )
    }
    
    private func toolbarOffsetLimits(
        for chromeMode: BrowserChromeMode
    ) -> (total: CGFloat, top: CGFloat) {
        let topToolbarHeight = browserChrome.topToolbarTransitionFrame(in: rootView).height
        let bottomToolbarHeight = browserChrome.bottomToolbarTransitionFrame(in: rootView).height
        switch chromeMode {
        case .phone:
            return (bottomToolbarHeight, 0)
        case .compact:
            return (topToolbarHeight + bottomToolbarHeight, topToolbarHeight)
        case .pad:
            let topChromeHeight = topToolbarHeight + (tabBar.visibility != .hidden ? tabBar.bounds.height : 0)
            return (topChromeHeight, topChromeHeight)
        }
    }
    
    private var maxTransitionOffset: CGFloat {
        let tabBarHeight = chromeMode == .pad && tabBar.visibility != .hidden ? tabBar.bounds.height : 0
        return maxToolbarOffset > 0 ? max(maxToolbarOffset, tabBarHeight + textCenteringDistance) : 0
    }
    
    private func setTransitionOffset(_ requestedOffset: CGFloat, refresh: Bool = false, animatesContent: Bool = true) {
        let clampedOffset = min(max(0, requestedOffset), maxTransitionOffset)
        guard refresh || clampedOffset != transitionOffset else {
            return
        }
        transitionOffset = clampedOffset
        let tabBarHeight = chromeMode == .pad && tabBar.visibility != .hidden ? tabBar.bounds.height : 0
        // After the tabs hide, centering and toolbar collapse share the same progress.
        let collapseProgress = max(0, transitionOffset - tabBarHeight) / max(maxTransitionOffset - tabBarHeight, 1)
        let tabBarCollapseOffset = min(transitionOffset, tabBarHeight)
        let topToolbarOffset = max(0, maxTopToolbarOffset - tabBarHeight) * collapseProgress
        let topContentOffset = topToolbarOffset + tabBarCollapseOffset
        var bottomToolbarOffset = (maxToolbarOffset - maxTopToolbarOffset) * collapseProgress
        if isBottomToolbarCollapsed && chromeMode != .pad {
            bottomToolbarOffset = browserChrome.bottomToolbarTransitionFrame(in: rootView).height
        }
        browserChrome.setToolbarTransition(
            topOffset: -topToolbarOffset,
            bottomOffset: bottomToolbarOffset,
            tabBarCollapseOffset: tabBarCollapseOffset,
            collapseProgress: isBottomToolbarCollapsed && chromeMode == .phone ? 0 : collapseProgress,
            isBottomToolbarCollapsed: isBottomToolbarCollapsed,
            animatesContent: animatesContent
        )
        tabBar.setCollapseOffset(tabBarCollapseOffset)
        let tabBarOffset = chromeMode == .pad ? topToolbarOffset : 0
        tabBar.transform = CGAffineTransform(translationX: 0, y: -tabBarOffset)
        contentView.applyToolbarOffsets(
            top: topContentOffset,
            bottom: bottomToolbarOffset,
            refresh: refresh
        )
    }
    
    // MARK: - Locking
    
    func lock(for reason: LockReason) {
        guard lockReasons.insert(reason).inserted else { return }
        reset()
    }
    
    func unlock(for reason: LockReason) {
        lockReasons.remove(reason)
    }
    
    // MARK: - Scroll Handling
    
    private func handleScroll(delta: CGFloat, position: CGFloat) {
        scrollPosition = max(0, position)
        guard Prefs.AppearanceSettings.scrollToHideToolbarEnabled,
              maxToolbarOffset > 0,
              lockReasons.isEmpty else {
            return
        }
        
        // Resume from the visible position when scrolling takes over or changes direction.
        if animationDisplayLink == nil || snapStartTime != nil || delta * (targetOffset - transitionOffset) < 0 {
            targetOffset = transitionOffset
        }
        snapStartTime = nil
        
        if transitionOffset == 0 {
            textCenteringDistance = browserChrome.toolbarTextCenteringDistance
        }
        
        var maximumOffset = maxTransitionOffset
        if scrollPosition < maxTopToolbarOffset {
            maximumOffset *= scrollPosition / maxTopToolbarOffset
        }
        targetOffset = min(max(targetOffset + delta * UX.toolbarScrollFactor, 0), maximumOffset)
        startAnimation()
        scheduleSnap()
    }
    
    // MARK: - Animation And Snapping
    
    private func scheduleSnap() {
        pendingSnap?.cancel()
        let snap = DispatchWorkItem { [weak self] in
            self?.beginSnap()
        }
        pendingSnap = snap
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.snapDelay, execute: snap)
    }
    
    private func beginSnap(to destination: CGFloat? = nil) {
        pendingSnap = nil
        snapOrigin = transitionOffset
        let shouldExpand = scrollPosition < maxTopToolbarOffset || targetOffset < maxTransitionOffset / 2
        targetOffset = destination ?? (shouldExpand ? 0 : maxTransitionOffset)
        guard snapOrigin != targetOffset else {
            setTransitionOffset(targetOffset, refresh: true)
            return
        }
        snapStartTime = CACurrentMediaTime()
        startAnimation()
    }
    
    private func startAnimation() {
        guard animationDisplayLink == nil, transitionOffset != targetOffset else { return }
        lastAnimationTime = CACurrentMediaTime()
        let displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink.add(to: .main, forMode: .common)
        animationDisplayLink = displayLink
    }
    
    @objc private func updateAnimation() {
        let time = CACurrentMediaTime()
        let maximumStep = UX.maximumTransitionSpeed * CGFloat(time - lastAnimationTime)
        lastAnimationTime = time
        var requestedOffset = targetOffset
        if let snapStartTime {
            let progress = min(CGFloat((time - snapStartTime) / UX.snapDuration), 1)
            let easedProgress = 1 - pow(1 - progress, 2)
            requestedOffset = snapOrigin + (targetOffset - snapOrigin) * easedProgress
        }
        let step = min(max(requestedOffset - transitionOffset, -maximumStep), maximumStep)
        setTransitionOffset(transitionOffset + step)
        if transitionOffset == targetOffset {
            animationDisplayLink?.invalidate()
            animationDisplayLink = nil
            snapStartTime = nil
        }
    }
    
    private func cancelAnimation() {
        pendingSnap?.cancel()
        pendingSnap = nil
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        snapStartTime = nil
    }
    
    // MARK: - Reset
    
    func collapseBottomToolbar() {
        cancelAnimation()
        isBottomToolbarCollapsed = true
        setTransitionOffset(transitionOffset, refresh: true, animatesContent: false)
    }
    
    func restoreBottomToolbar() {
        cancelAnimation()
        isBottomToolbarCollapsed = false
        setTransitionOffset(transitionOffset, refresh: true, animatesContent: false)
    }
    
    func collapse(animated: Bool = true) {
        cancelAnimation()
        isBottomToolbarCollapsed = false
        if transitionOffset == 0 {
            textCenteringDistance = browserChrome.toolbarTextCenteringDistance
        }
        guard animated else {
            setTransitionOffset(maxTransitionOffset, refresh: true, animatesContent: false)
            return
        }
        beginSnap(to: maxTransitionOffset)
    }
    
    func reset(animated: Bool = true) {
        cancelAnimation()
        isBottomToolbarCollapsed = false
        guard animated else {
            setTransitionOffset(0, refresh: true, animatesContent: false)
            return
        }
        beginSnap(to: 0)
    }
}
