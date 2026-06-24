//
//  HomepageOverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

protocol HomepageOverlayCoordinatorDelegate: AnyObject {
    var homepageLayout: BrowserLayout { get }
    var homepageGridWidth: HomepageGridWidth { get }
    var homepageSelectedTab: Tab? { get }
    var isHomepageTabOverviewPresented: Bool { get }
    var isHomepageShowingFullscreenMedia: Bool { get }
    var homepageChrome: BrowserChrome { get }
    var homepageContentView: ContentView { get }
    
    func browseHomepageFavorite(_ favorite: BookmarkSnapshot)
    func endHomepageEditing()
    func updateHomepageLayout(animated: Bool, duration: TimeInterval)
    func browseHomepagePerformanceGuide()
    func openHomepagePerformanceSettings()
}

final class HomepageOverlayCoordinator {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.2
    }
    
    private weak var delegate: HomepageOverlayCoordinatorDelegate?
    private let overlayCoordinator: OverlayCoordinator
    private let homepageViewController: HomepageViewController
    private var presentationIntent: HomepagePresentationIntent = .inactive
    private var snapshotCache: HomepageSnapshotCache?
    private var snapshotWarmupState: SnapshotWarmupState = .idle
    
    private struct HomepagePresentation: Equatable {
        let host: OverlayCoordinator.Host
        let contentMode: HomepageContentMode
    }
    
    // MARK: - Lifecycle
    
    init(delegate: HomepageOverlayCoordinatorDelegate, overlayCoordinator: OverlayCoordinator) {
        self.delegate = delegate
        self.overlayCoordinator = overlayCoordinator
        homepageViewController = HomepageViewController()
        configureHomepageViewController()
        observeBookmarks()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - State
    
    func updatePresentation(animated: Bool) {
        guard let target = resolvedPresentation else {
            dismiss(animated: animated)
            return
        }
        
        presentHomepage(target, animated: animated)
    }
    
    func updatePresentedLayout() {
        guard let target = resolvedPresentation,
              overlayCoordinator.contains(.homepage, on: target.host) else {
            return
        }
        
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
        homepageViewController.setContentMode(target.contentMode)
        configureOverlay(for: target)
        warmSnapshotCacheIfNeeded()
    }
    
    func tabOverviewWillPresent() {
        guard !showsHomepageForBlankTabs || !isSelectedTabBlankPage else {
            return
        }
        
        dismiss(animated: false)
    }
    
    func resetPresentationSession() {
        presentationIntent = .inactive
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
    }
    
    // MARK: - Configuration
    
    private func configureHomepageViewController() {
        homepageViewController.homepageDelegate = self
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    // MARK: - Snapshot
    
    private func renderSnapshot(size: CGSize, isPrivateBrowsing: Bool) -> UIImage? {
        guard let delegate,
              size.width > 1,
              size.height > 1 else {
            return nil
        }
        
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let contentMode = embeddedContentMode(layout: delegate.homepageLayout)
        let userInterfaceStyle = homepageViewController.traitCollection.userInterfaceStyle
        if let snapshotCache,
           snapshotCache.matches(
            pixelSize: pixelSize,
            contentMode: contentMode,
            isPrivateBrowsing: isPrivateBrowsing,
            userInterfaceStyle: userInterfaceStyle
           ) {
            return snapshotCache.image
        }
        
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
        guard let image = homepageViewController.renderSnapshot(size: size, contentMode: contentMode) else {
            return nil
        }
        
        snapshotCache = HomepageSnapshotCache(
            pixelSize: pixelSize,
            contentMode: contentMode,
            isPrivateBrowsing: isPrivateBrowsing,
            userInterfaceStyle: userInterfaceStyle,
            image: image
        )
        return image
    }
    
    private func warmSnapshotCacheIfNeeded() {
        guard snapshotWarmupState == .idle,
              resolvedSnapshotSize != nil,
              isSelectedTabBlankPage else {
            return
        }
        
        snapshotWarmupState = .scheduled
        DispatchQueue.main.async { [weak self] in
            self?.warmSnapshotCache()
        }
    }
    
    private func warmSnapshotCache() {
        snapshotWarmupState = .idle
        guard isSelectedTabBlankPage,
              let size = resolvedSnapshotSize else {
            return
        }
        
        _ = renderSnapshot(size: size, isPrivateBrowsing: isPrivateBrowsing)
    }
    
    private var resolvedSnapshotSize: CGSize? {
        guard let size = delegate?.homepageContentView.bounds.size,
              size.width > 1,
              size.height > 1 else {
            return nil
        }
        
        return size
    }
    
    func snapshotForBlankTab(_ tab: Tab, size: CGSize) -> UIImage? {
        guard showsHomepageForBlankTabs,
              isBlankTab(tab) else {
            return nil
        }
        
        return renderSnapshot(size: size, isPrivateBrowsing: tab.isPrivate)
    }
    
    // MARK: - Presentation
    
    private func presentHomepage(_ presentation: HomepagePresentation, animated: Bool) {
        overlayCoordinator.dismiss(.homepage, on: otherHost(from: presentation.host), animated: false)
        
        guard !overlayCoordinator.contains(.homepage, on: presentation.host),
              !overlayCoordinator.isPresented(.search, on: presentation.host) else {
            homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
            homepageViewController.setContentMode(presentation.contentMode)
            homepageViewController.prepareForPresentation(resetNavigation: false)
            configureOverlay(for: presentation)
            warmSnapshotCacheIfNeeded()
            return
        }
        
        overlayCoordinator.present(
            homepageViewController,
            for: .homepage,
            on: presentation.host,
            animated: animated
        ) { [weak self] in
            self?.homepageViewController.setPrivateBrowsing(self?.isPrivateBrowsing == true)
            self?.homepageViewController.setContentMode(presentation.contentMode)
            self?.homepageViewController.prepareForPresentation(resetNavigation: true)
            self?.configureOverlay(for: presentation)
            self?.warmSnapshotCacheIfNeeded()
        }
    }
    
    private func dismiss(animated: Bool) {
        overlayCoordinator.dismiss(.homepage, on: .embedded, animated: animated)
        overlayCoordinator.dismiss(.homepage, on: .detached, animated: animated)
    }
    
    private func configureOverlay(for target: HomepagePresentation) {
        guard target.host == .detached,
              let delegate else {
            return
        }
        
        delegate.homepageChrome.setOverlayHeightMode(.default)
        delegate.homepageChrome.setOverlayAvailableContentHeight(delegate.homepageContentView.bounds.height)
    }
    
    // MARK: - Target Resolution
    
    private var resolvedPresentation: HomepagePresentation? {
        guard let delegate,
              !delegate.isHomepageShowingFullscreenMedia else {
            return nil
        }
        
        if showsHomepageForBlankTabs && isSelectedTabBlankPage {
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: delegate.homepageLayout)
            )
        }
        
        guard !delegate.isHomepageTabOverviewPresented else {
            return nil
        }
        
        guard presentationIntent == .addressBarFocus else {
            return nil
        }
        
        return presentationTargetForFocusedAddressBar(
            layout: delegate.homepageLayout,
            gridWidth: delegate.homepageGridWidth
        )
    }
    
    private var isSelectedTabBlankPage: Bool {
        guard let tab = delegate?.homepageSelectedTab else {
            return false
        }
        
        return isBlankTab(tab)
    }
    
    private var isPrivateBrowsing: Bool {
        return delegate?.homepageSelectedTab?.isPrivate == true
    }
    
    private var showsHomepageForBlankTabs: Bool {
        return Prefs.NewTabSettings.newTabDisplayOption == .homepage
    }
    
    private func isBlankTab(_ tab: Tab) -> Bool {
        if case let .pending(value) = tab.state.displayState {
            return isBlankURL(value)
        }
        
        return isBlankURL(tab.url)
    }
    
    private func isBlankURL(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return true
        }
        
        return value.lowercased().hasPrefix("about:blank")
    }
    
    private func presentationTargetForFocusedAddressBar(
        layout: BrowserLayout,
        gridWidth: HomepageGridWidth
    ) -> HomepagePresentation? {
        if layout.interfaceIdiom == .pad,
           gridWidth == .fourColumn {
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: layout)
            )
        }
        
        switch (layout.interfaceIdiom, layout.chromeMode, layout.orientation) {
        case (.phone, _, .portrait), (.pad, .compact, _):
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: layout)
            )
        case (.phone, _, .landscape), (.pad, .pad, _):
            return HomepagePresentation(
                host: .detached,
                contentMode: HomepageContentMode.detached(layout: layout)
            )
        default:
            return nil
        }
    }
    
    private func embeddedContentMode(layout: BrowserLayout) -> HomepageContentMode {
        guard let delegate else {
            return HomepageContentMode.embedded(layout: layout)
        }
        
        return HomepageContentMode.embedded(
            layout: layout,
            gridWidth: delegate.homepageGridWidth
        )
    }
    
    private func otherHost(from host: OverlayCoordinator.Host) -> OverlayCoordinator.Host {
        switch host {
        case .embedded:
            return .detached
        case .detached:
            return .embedded
        }
    }
    
    // MARK: - Bookmarks
    
    private func observeBookmarks() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarkStoreDidChange,
            object: nil
        )
    }
    
    @objc private func bookmarksDidChange() {
        snapshotCache = nil
    }
}

private enum HomepagePresentationIntent {
    case inactive
    case persistentBlankTab
    case addressBarFocus
}

private enum SnapshotWarmupState {
    case idle
    case scheduled
}

// MARK: - Address Bar Search Delegate

extension HomepageOverlayCoordinator: AddressBarSearchDelegate {
    func addressBarDidSubmit(_ searchTerm: String) {}
    
    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        if overlayCoordinator.endAddressBarScrollDismissal(for: .homepage) {
            presentationIntent = isSelectedTabBlankPage ? .persistentBlankTab : .inactive
            delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
            updatePresentation(animated: true)
            return
        }
        
        presentationIntent = .inactive
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        updatePresentation(animated: true)
    }
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        presentationIntent = isSelectedTabBlankPage ? .persistentBlankTab : .addressBarFocus
        updatePresentation(animated: true)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if overlayCoordinator.consumeAddressBarScrollDismissal(for: .homepage) {
            delegate?.updateHomepageLayout(animated: false, duration: UX.layoutAnimationDuration)
            return
        }
        
        presentationIntent = isSelectedTabBlankPage ? .persistentBlankTab : .inactive
        updatePresentation(animated: true)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updatePresentation(animated: true)
            return
        }
    }
}

// MARK: - Homepage View Controller Delegate

extension HomepageOverlayCoordinator: HomepageViewControllerDelegate {
    func homepageViewControllerDidSelectFavorite(_ favorite: BookmarkSnapshot) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.browseHomepageFavorite(favorite)
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageViewControllerDidSelectPerformanceGuide(_ controller: HomepageViewController) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.browseHomepagePerformanceGuide()
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageViewControllerDidSelectPerformanceSettings(_ controller: HomepageViewController) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.openHomepagePerformanceSettings()
        delegate?.endHomepageEditing()
    }
    
    func homepageViewControllerDidStartScrolling() {
        guard overlayCoordinator.beginAddressBarScrollDismissal(for: .homepage) else {
            return
        }
        
        delegate?.updateHomepageLayout(animated: false, duration: UX.layoutAnimationDuration)
    }
}
