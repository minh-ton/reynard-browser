//
//  OverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

protocol ContentOverlayCoordinatorHost: AnyObject {
    var overlayParentViewController: UIViewController { get }
    var contentView: ContentView { get }
    var browserChrome: BrowserChrome { get }
}

final class OverlayCoordinator {
    enum Page: Hashable {
        case homepage
        case search
    }
    
    enum Host {
        case embedded
        case detached
    }
    
    private struct Entry {
        let page: Page
        let host: Host
        let viewController: UIViewController
        let prepare: () -> Void
    }
    
    private weak var host: ContentOverlayCoordinatorHost?
    private var activeEntry: Entry?
    private var previousEntry: Entry?
    
    init(host: ContentOverlayCoordinatorHost) {
        self.host = host
    }
    
    // MARK: - State Queries
    
    func isPresented(_ page: Page) -> Bool {
        return activeEntry?.page == page
    }
    
    func host(for page: Page) -> Host? {
        guard activeEntry?.page == page else {
            return nil
        }
        
        return activeEntry?.host
    }
    
    // MARK: - Presentation
    
    func present(
        _ viewController: UIViewController,
        for page: Page,
        on host: Host,
        animated: Bool,
        prepare: @escaping () -> Void = {}
    ) {
        let entry = Entry(page: page, host: host, viewController: viewController, prepare: prepare)
        if activeEntry?.page == page {
            activate(entry, replacing: activeEntry, animated: animated)
            return
        }
        
        previousEntry = activeEntry
        activate(entry, replacing: activeEntry, animated: animated)
    }
    
    func dismiss(
        _ page: Page,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let activeEntry, activeEntry.page == page else {
            completion?()
            return
        }
        
        let nextEntry = previousEntry
        self.activeEntry = nextEntry
        previousEntry = nil
        
        guard let nextEntry else {
            hide(activeEntry.host, animated: animated, completion: completion)
            return
        }
        
        activate(nextEntry, replacing: activeEntry, animated: animated) {
            self.removeController(for: page, from: activeEntry.host)
            completion?()
        }
    }
    
    // MARK: - Host Coordination
    
    private func activate(
        _ entry: Entry,
        replacing currentEntry: Entry?,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        let presentEntry = {
            entry.prepare()
            self.setController(entry.viewController, for: entry.page, on: entry.host)
            self.show(entry.page, on: entry.host, animated: animated, completion: completion)
            self.activeEntry = entry
        }
        
        guard let currentEntry, currentEntry.host != entry.host else {
            presentEntry()
            return
        }
        
        hide(currentEntry.host, animated: false, completion: presentEntry)
    }
    
    private func hide(_ host: Host, animated: Bool, completion: (() -> Void)?) {
        guard let overlayHost = self.host else {
            completion?()
            return
        }
        
        switch host {
        case .embedded:
            overlayHost.contentView.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        case .detached:
            overlayHost.browserChrome.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        }
    }
    
    private func setController(_ viewController: UIViewController, for page: Page, on host: Host) {
        guard let overlayHost = self.host else {
            return
        }
        
        switch host {
        case .embedded:
            overlayHost.contentView.setOverlayController(
                viewController,
                for: embeddedPage(for: page),
                in: overlayHost.overlayParentViewController
            )
        case .detached:
            overlayHost.browserChrome.setOverlayController(
                viewController,
                for: detachedPage(for: page),
                in: overlayHost.overlayParentViewController
            )
        }
    }
    
    private func removeController(for page: Page, from host: Host) {
        guard let overlayHost = self.host else {
            return
        }
        
        switch host {
        case .embedded:
            overlayHost.contentView.removeOverlayController(for: embeddedPage(for: page))
        case .detached:
            overlayHost.browserChrome.removeOverlayController(for: detachedPage(for: page))
        }
    }
    
    private func show(
        _ page: Page,
        on host: Host,
        animated: Bool,
        completion: (() -> Void)?
    ) {
        guard let overlayHost = self.host else {
            completion?()
            return
        }
        
        switch host {
        case .embedded:
            overlayHost.contentView.setOverlayPresentation(
                .visible(embeddedPage(for: page)),
                animated: animated,
                completion: completion
            )
        case .detached:
            overlayHost.browserChrome.setOverlayPresentation(
                .visible(detachedPage(for: page)),
                animated: animated,
                completion: completion
            )
        }
    }
    
    // MARK: - Page Mapping
    
    private func embeddedPage(for page: Page) -> OverlayContentView.Page {
        switch page {
        case .homepage: return .homepage
        case .search: return .search
        }
    }
    
    private func detachedPage(for page: Page) -> ChromeOverlayContentView.Page {
        switch page {
        case .homepage: return .homepage
        case .search: return .search
        }
    }
}
