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
    var isHomepageTabOverviewPresented: Bool { get }
    var isHomepageShowingFullscreenMedia: Bool { get }
    
    // Homepage section actions
    func openURLFromHomepage(_ url: URL, disposition: TabOpenDisposition)
    func shareURLFromHomepage(_ url: URL, sourceView: UIView)
    func openSettingsFromHomepage()
    
    func endHomepageEditing()
    func updateHomepageLayout(animated: Bool, duration: TimeInterval)
}

final class HomepageOverlayCoordinator {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.2
    }
    
    private weak var delegate: HomepageOverlayCoordinatorDelegate?
    private let overlayCoordinator: OverlayCoordinator
    private unowned let toolbarController: ToolbarController
    private unowned let browserChrome: BrowserChrome
    private unowned let contentView: ContentView
    private unowned let tabManager: TabManager
    private let homepageViewController: HomepageViewController
    private var presentationIntent: HomepagePresentationIntent = .inactive
    
    private struct HomepagePresentation: Equatable {
        let host: OverlayCoordinator.Host
        let contentMode: HomepageContentMode
        let showsBackground: Bool
    }
    
    // MARK: - Lifecycle
    
    init(
        delegate: HomepageOverlayCoordinatorDelegate,
        overlayCoordinator: OverlayCoordinator,
        toolbarController: ToolbarController,
        browserChrome: BrowserChrome,
        contentView: ContentView,
        tabManager: TabManager
    ) {
        self.delegate = delegate
        self.overlayCoordinator = overlayCoordinator
        self.toolbarController = toolbarController
        self.browserChrome = browserChrome
        self.contentView = contentView
        self.tabManager = tabManager
        homepageViewController = HomepageViewController()
        homepageViewController.homepageDelegate = self
        homepageViewController.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    // MARK: - State
    
    func isHomepageTab(_ tab: Tab) -> Bool {
        guard tab.state.loadError == nil,
              showsHomepageForBlankTabs || tab.state.showsStartupHomepage else {
            return false
        }
        
        return isBlankTab(tab)
    }
    
    func updatePresentation(animated: Bool) {
        let showsHomepage = tabManager.selectedTab.map(isHomepageTab) == true
        contentView.setWebVisibility(showsHomepage ? .hidden : .visible)
        
        guard let presentation = homepagePresentation else {
            dismiss(animated: animated)
            return
        }
        
        toolbarController.lock(for: .homepageOverlay)
        presentHomepage(presentation, animated: animated)
    }
    
    func updateVisibleContentInsets() {
        guard let presentation = homepagePresentation,
              presentation.host == .embedded,
              overlayCoordinator.contains(.homepage, on: presentation.host) else {
            return
        }
        
        homepageViewController.setVisibleContentInsets(visibleContentInsets(in: contentView))
    }
    
    func tabOverviewWillPresent() {
        if let tab = tabManager.selectedTab,
           isHomepageTab(tab) {
            return
        }
        
        dismiss(animated: false)
    }
    
    func resetPresentationSession() {
        presentationIntent = .inactive
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        toolbarController.unlock(for: .homepageOverlay)
    }
    
    // MARK: - Thumbnails
    
    func makeThumbnail(for tab: Tab) -> UIImage? {
        guard let delegate,
              let geometry = contentView.thumbnailCaptureGeometry else {
            return nil
        }
        
        homepageViewController.setPrivateBrowsing(tab.isPrivate)
        homepageViewController.setContentMode(embeddedContentMode(layout: delegate.homepageLayout))
        homepageViewController.setShowsBackground(true)
        return homepageViewController.makeThumbnail(size: geometry.size, visibleRect: geometry.visibleRect)
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
        var dismissalsRemaining = 2
        let finishDismissal = { [weak self] in
            dismissalsRemaining -= 1
            guard dismissalsRemaining == 0 else {
                return
            }
            self?.toolbarController.unlock(for: .homepageOverlay)
        }
        overlayCoordinator.dismiss(
            .homepage,
            on: .embedded,
            animated: animated,
            completion: finishDismissal
        )
        overlayCoordinator.dismiss(
            .homepage,
            on: .detached,
            animated: animated,
            completion: finishDismissal
        )
    }
    
    private func configureOverlay(for presentation: HomepagePresentation) {
        guard presentation.host == .detached else {
            contentView.superview?.layoutIfNeeded()
            homepageViewController.setVisibleContentInsets(visibleContentInsets(in: contentView))
            return
        }
        
        homepageViewController.setVisibleContentInsets(.zero)
        browserChrome.setOverlayHeightMode(.default)
        browserChrome.setOverlayAvailableContentHeight(contentView.bounds.height)
    }
    
    private func visibleContentInsets(in contentView: UIView) -> UIEdgeInsets {
        let visibleFrame = contentView.convert(contentView.bounds, to: homepageViewController.view)
        let homepageBounds = homepageViewController.view.bounds
        return UIEdgeInsets(
            top: max(0, visibleFrame.minY - homepageBounds.minY),
            left: 0,
            bottom: max(0, homepageBounds.maxY - visibleFrame.maxY),
            right: 0
        )
    }
    
    // MARK: - Presentation Resolution
    
    private var homepagePresentation: HomepagePresentation? {
        guard let delegate,
              !delegate.isHomepageShowingFullscreenMedia else {
            return nil
        }
        
        if let tab = tabManager.selectedTab,
           isHomepageTab(tab) {
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
        guard let tab = tabManager.selectedTab else {
            return false
        }
        
        return isBlankTab(tab)
    }
    
    private var isPrivateBrowsing: Bool {
        return tabManager.selectedTab?.isPrivate == true
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

// MARK: - Homepage Section Delegate

extension HomepageOverlayCoordinator: HomepageSectionDelegate {
    func homepageSection(_ viewController: UIViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        browserChrome.addressBar.setEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        delegate?.openURLFromHomepage(url, disposition: disposition)
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageSection(
        _ viewController: UIViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    ) {
        delegate?.shareURLFromHomepage(
            url,
            sourceView: sourceView
        )
    }
    
    func homepageSection(_ viewController: UIViewController, didRequestHideFromSuggestions siteID: Int64) {
        HistoryStore.shared.hideFromSuggestions(siteID: siteID)
    }
    
    func homepageSection(_ viewController: UIViewController, didSelectRecentlyClosedTab id: UUID) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        browserChrome.addressBar.setEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        guard tabManager.restoreRecentlyClosedTab(id: id) else {
            return
        }
        
        delegate?.endHomepageEditing()
        presentationIntent = .inactive
        dismiss(animated: true)
    }
    
    func homepageSectionDidSelectSettings(_ viewController: UIViewController) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .homepage)
        browserChrome.addressBar.setEditingState(.inactive)
        delegate?.updateHomepageLayout(animated: true, duration: UX.layoutAnimationDuration)
        delegate?.openSettingsFromHomepage()
        delegate?.endHomepageEditing()
    }
    
    func homepageSection(_ viewController: UIViewController, didSelectFolder folder: BookmarkFolderSnapshot) {
        homepageViewController.showFolder(folder)
    }
    
    func homepageDidStartScrolling() {
        guard overlayCoordinator.beginAddressBarScrollDismissal(for: .homepage) else {
            return
        }
        
        delegate?.updateHomepageLayout(animated: false, duration: UX.layoutAnimationDuration)
    }
}
