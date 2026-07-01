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
    var homepageTabActions: ContextMenuTabActions { get }
    
    // Homepage section actions
    func openURLFromHomepage(_ url: URL, disposition: TabOpenDisposition)
    func shareURLFromHomepage(_ url: URL)
    func openSettingsFromHomepage()
    func restoreClosedTabFromHomepage(id: UUID) -> Bool
    
    func endHomepageEditing()
    func updateHomepageLayout(animated: Bool, duration: TimeInterval)
}

final class HomepageOverlayCoordinator {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.2
    }
    
    private weak var delegate: HomepageOverlayCoordinatorDelegate?
    private let overlayCoordinator: OverlayCoordinator
    private let homepageViewController: HomepageViewController
    private let homepageThumbnailRenderer: HomepageThumbnailRenderer
    private var presentationIntent: HomepagePresentationIntent = .inactive
    
    private struct HomepagePresentation: Equatable {
        let host: OverlayCoordinator.Host
        let contentMode: HomepageContentMode
        let showsBackground: Bool
    }
    
    // MARK: - Lifecycle
    
    init(delegate: HomepageOverlayCoordinatorDelegate, overlayCoordinator: OverlayCoordinator) {
        self.delegate = delegate
        self.overlayCoordinator = overlayCoordinator
        homepageViewController = HomepageViewController()
        homepageThumbnailRenderer = HomepageThumbnailRenderer(homepageViewController: homepageViewController)
        homepageViewController.homepageDelegate = self
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    // MARK: - State
    
    func updatePresentation(animated: Bool) {
        guard let presentation = homepagePresentation else {
            dismiss(animated: animated)
            return
        }
        
        presentHomepage(presentation, animated: animated)
    }
    
    func updatePresentedLayout() {
        guard let presentation = homepagePresentation,
              overlayCoordinator.contains(.homepage, on: presentation.host) else {
            return
        }
        
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
        homepageViewController.setContentMode(presentation.contentMode)
        homepageViewController.setShowsBackground(presentation.showsBackground)
        configureOverlay(for: presentation)
    }
    
    func tabOverviewWillPresent() {
        if let tab = delegate?.homepageSelectedTab,
           (showsHomepageForBlankTabs || tab.state.showsStartupHomepage),
           isBlankTab(tab) {
            return
        }
        
        dismiss(animated: false)
    }
    
    func resetPresentationSession() {
        presentationIntent = .inactive
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
    }
    
    // MARK: - Thumbnails
    
    func needsHomepageThumbnail(for tab: Tab) -> Bool {
        return (showsHomepageForBlankTabs || tab.state.showsStartupHomepage) && isBlankTab(tab)
    }
    
    func prepareHomepageForNewTab(mode: TabMode) {
        guard let delegate,
              showsHomepageForBlankTabs else {
            return
        }
        
        homepageThumbnailRenderer.prepareForCapture(
            contentMode: embeddedContentMode(layout: delegate.homepageLayout),
            isPrivateBrowsing: mode == .private
        )
    }
    
    func captureHomepageThumbnail(_ tab: Tab, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        guard let delegate else {
            completion(nil)
            return
        }
        
        homepageThumbnailRenderer.capture(
            size: size,
            contentMode: embeddedContentMode(layout: delegate.homepageLayout),
            isPrivateBrowsing: tab.isPrivate,
            completion: completion
        )
    }
    
    func previewImage(for tab: Tab, size: CGSize) -> UIImage? {
        guard let delegate,
              needsHomepageThumbnail(for: tab) else {
            return nil
        }

        return homepageThumbnailRenderer.snapshot(
            size: size,
            contentMode: embeddedContentMode(layout: delegate.homepageLayout),
            isPrivateBrowsing: tab.isPrivate
        )
    }

    // MARK: - Presentation
    
    private func presentHomepage(_ presentation: HomepagePresentation, animated: Bool) {
        overlayCoordinator.dismiss(.homepage, on: otherHost(from: presentation.host), animated: false)
        
        guard !overlayCoordinator.contains(.homepage, on: presentation.host),
              !overlayCoordinator.isPresented(.search, on: presentation.host) else {
            homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
            homepageViewController.setContentMode(presentation.contentMode)
            homepageViewController.setShowsBackground(presentation.showsBackground)
            homepageViewController.prepareForPresentation(resetNavigation: false)
            configureOverlay(for: presentation)
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
            self?.homepageViewController.setShowsBackground(presentation.showsBackground)
            self?.homepageViewController.prepareForPresentation(resetNavigation: true)
            self?.configureOverlay(for: presentation)
        }
    }
    
    private func dismiss(animated: Bool) {
        overlayCoordinator.dismiss(.homepage, on: .embedded, animated: animated)
        overlayCoordinator.dismiss(.homepage, on: .detached, animated: animated)
    }
    
    private func configureOverlay(for presentation: HomepagePresentation) {
        guard presentation.host == .detached,
              let delegate else {
            return
        }
        
        delegate.homepageChrome.setOverlayHeightMode(.default)
        delegate.homepageChrome.setOverlayAvailableContentHeight(delegate.homepageContentView.bounds.height)
    }
    
    // MARK: - Presentation Resolution
    
    private var homepagePresentation: HomepagePresentation? {
        guard let delegate,
              !delegate.isHomepageShowingFullscreenMedia else {
            return nil
        }
        
        if let tab = delegate.homepageSelectedTab,
           (showsHomepageForBlankTabs || tab.state.showsStartupHomepage),
           isBlankTab(tab) {
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: delegate.homepageLayout),
                showsBackground: true
            )
        }
        
        guard !delegate.isHomepageTabOverviewPresented else {
            return nil
        }
        
        guard presentationIntent == .addressBarFocus else {
            return nil
        }
        
        return presentationForFocusedAddressBar(
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
    
    private func isBlankURL(_ urlString: String?) -> Bool {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            return true
        }
        
        return urlString.lowercased().hasPrefix("about:blank")
    }
    
    private func presentationForFocusedAddressBar(
        layout: BrowserLayout,
        gridWidth: HomepageGridWidth
    ) -> HomepagePresentation? {
        if layout.interfaceIdiom == .pad,
           gridWidth == .fourColumn {
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: layout),
                showsBackground: false
            )
        }
        
        switch (layout.interfaceIdiom, layout.chromeMode, layout.orientation) {
        case (.phone, _, .portrait), (.pad, .compact, _):
            return HomepagePresentation(
                host: .embedded,
                contentMode: embeddedContentMode(layout: layout),
                showsBackground: false
            )
        case (.phone, _, .landscape), (.pad, .pad, _):
            return HomepagePresentation(
                host: .detached,
                contentMode: HomepageContentMode.detached(layout: layout),
                showsBackground: false
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
    
}

private enum HomepagePresentationIntent {
    case inactive
    case addressBarFocus
}

// MARK: - Address Bar Search Delegate

extension HomepageOverlayCoordinator: AddressBarSearchDelegate {
    func addressBarDidSubmit(_ searchTerm: String) {}
    
    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        if overlayCoordinator.endAddressBarScrollDismissal(for: .homepage) {
            presentationIntent = .inactive
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
        presentationIntent = isSelectedTabBlankPage ? .inactive : .addressBarFocus
        updatePresentation(animated: true)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if overlayCoordinator.consumeAddressBarScrollDismissal(for: .homepage) {
            delegate?.updateHomepageLayout(animated: false, duration: UX.layoutAnimationDuration)
            return
        }
        
        presentationIntent = .inactive
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
    func homepageViewController(_ controller: HomepageViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.homepageChrome.setAddressBarEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        delegate?.openURLFromHomepage(url, disposition: disposition)
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageViewController(_ controller: HomepageViewController, didRequestShareURL url: URL) {
        delegate?.shareURLFromHomepage(url)
    }
    
    func homepageViewController(_ controller: HomepageViewController, didRequestHideFromSuggestions siteID: Int64) {
        HistoryStore.shared.hideFromSuggestions(siteID: siteID)
    }
    
    func homepageViewController(_ controller: HomepageViewController, didSelectRecentlyClosedTab id: UUID) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.homepageChrome.setAddressBarEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        guard delegate?.restoreClosedTabFromHomepage(id: id) == true else {
            return
        }
        
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageViewControllerDidSelectSettings(_ controller: HomepageViewController) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        delegate?.homepageChrome.setAddressBarEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        delegate?.openSettingsFromHomepage()
        delegate?.endHomepageEditing()
    }
    
    func homepageViewControllerDidStartScrolling() {
        guard overlayCoordinator.beginAddressBarScrollDismissal(for: .homepage) else {
            return
        }
        
        delegate?.updateHomepageLayout(animated: false, duration: UX.layoutAnimationDuration)
    }
}
