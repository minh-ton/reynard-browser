//
//  OverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class OverlayCoordinator {
    enum Page: Hashable {
        case homepage
        case search
    }
    
    enum Host: Hashable {
        case embedded
        case detached
    }
    
    private struct Entry {
        let page: Page
        let host: Host
        let viewController: UIViewController
        let prepare: () -> Void
    }
    
    private enum AddressBarScrollDismissalState {
        case pending(Page)
        case dismissed(Page)
        
        var page: Page {
            switch self {
            case let .pending(page), let .dismissed(page):
                return page
            }
        }
    }
    
    private unowned let parentViewController: UIViewController
    private unowned let contentView: ContentView
    private unowned let browserChrome: BrowserChrome
    private var activeEntries: [Host: Entry] = [:]
    private var previousEntries: [Host: Entry] = [:]
    private var addressBarScrollDismissal: AddressBarScrollDismissalState?
    
    init(
        parentViewController: UIViewController,
        contentView: ContentView,
        browserChrome: BrowserChrome
    ) {
        self.parentViewController = parentViewController
        self.contentView = contentView
        self.browserChrome = browserChrome
    }
    
    // MARK: - State Queries
    
    func isPresented(_ page: Page, on host: Host) -> Bool {
        return activeEntries[host]?.page == page
    }
    
    func contains(_ page: Page, on host: Host) -> Bool {
        return activeEntries[host]?.page == page || previousEntries[host]?.page == page
    }
    
    // MARK: - Address Bar Scroll Dismissal
    
    func isAddressBarScrollDismissed(for page: Page) -> Bool {
        guard case let .dismissed(dismissedPage) = addressBarScrollDismissal,
              dismissedPage == page else {
            return false
        }
        
        return true
    }
    
    func chromeStateForAddressBarScrollDismissal(layout: BrowserLayout) -> BrowserChrome.SearchState? {
        guard addressBarScrollDismissal != nil else {
            return nil
        }
        
        return chromeState(for: layout)
    }
    
    func chromeStateForAddressBarScrollDismissal(for page: Page, layout: BrowserLayout) -> BrowserChrome.SearchState? {
        guard addressBarScrollDismissal?.page == page else {
            return nil
        }
        
        return chromeState(for: layout)
    }
    
    @discardableResult
    func beginAddressBarScrollDismissal(for page: Page) -> Bool {
        guard browserChrome.addressBar.isEditingText else {
            return false
        }
        
        addressBarScrollDismissal = .pending(page)
        browserChrome.addressBar.setPreservesAutocompleteAfterResign(
            browserChrome.addressBar.isShowingAutocomplete
        )
        _ = browserChrome.addressBar.resignFirstResponder()
        return true
    }
    
    @discardableResult
    func consumeAddressBarScrollDismissal(for page: Page) -> Bool {
        guard case let .pending(pendingPage) = addressBarScrollDismissal,
              pendingPage == page else {
            return false
        }
        
        addressBarScrollDismissal = .dismissed(page)
        browserChrome.addressBar.setEditingState(.composing)
        browserChrome.addressBar.setPreservesAutocompleteAfterResign(true)
        return true
    }
    
    func clearAddressBarScrollDismissal(for page: Page) {
        guard addressBarScrollDismissal?.page == page else {
            return
        }
        
        addressBarScrollDismissal = nil
        browserChrome.addressBar.setPreservesAutocompleteAfterResign(false)
    }
    
    @discardableResult
    func endAddressBarScrollDismissal(for page: Page) -> Bool {
        guard addressBarScrollDismissal?.page == page else {
            return false
        }
        
        addressBarScrollDismissal = nil
        browserChrome.addressBar.setEditingState(.inactive)
        browserChrome.addressBar.setPreservesAutocompleteAfterResign(false)
        return true
    }
    
    private func chromeState(for layout: BrowserLayout) -> BrowserChrome.SearchState {
        return layout.overlayHost == .detached
        ? .scrollingDetachedSuggestions
        : .scrollingEmbeddedSuggestions
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
        activate(entry, replacing: activeEntries[host], animated: animated)
    }
    
    func dismiss(
        _ page: Page,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let entryHost = activeEntries.first(where: { $0.value.page == page })?.key,
              let activeEntry = activeEntries[entryHost] else {
            if let coveredHost = previousEntries.first(where: { $0.value.page == page })?.key {
                previousEntries[coveredHost] = nil
                removeController(for: page, from: coveredHost)
            }
            completion?()
            return
        }
        
        let nextEntry = previousEntries[entryHost]
        activeEntries[entryHost] = nextEntry
        previousEntries[entryHost] = nil
        
        guard let nextEntry else {
            hide(activeEntry.host, animated: animated, completion: completion)
            return
        }
        
        activate(nextEntry, replacing: activeEntry, animated: animated, storesPreviousEntry: false) {
            self.removeController(for: page, from: activeEntry.host)
            completion?()
        }
    }
    
    func dismiss(
        _ page: Page,
        on host: Host,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let activeEntry = activeEntries[host],
              activeEntry.page == page else {
            if previousEntries[host]?.page == page {
                previousEntries[host] = nil
                removeController(for: page, from: host)
            }
            completion?()
            return
        }
        
        let nextEntry = previousEntries[host]
        activeEntries[host] = nextEntry
        previousEntries[host] = nil
        
        guard let nextEntry else {
            hide(host, animated: animated, completion: completion)
            return
        }
        
        activate(nextEntry, replacing: activeEntry, animated: animated, storesPreviousEntry: false) {
            self.removeController(for: page, from: host)
            completion?()
        }
    }
    
    func discardAll(animated: Bool) {
        activeEntries.removeAll()
        previousEntries.removeAll()
        addressBarScrollDismissal = nil
        hide(.embedded, animated: animated, completion: nil)
        hide(.detached, animated: animated, completion: nil)
    }
    
    // MARK: - Host Coordination
    
    private func activate(
        _ entry: Entry,
        replacing currentEntry: Entry?,
        animated: Bool,
        storesPreviousEntry: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        let presentEntry = {
            self.setController(entry.viewController, for: entry.page, on: entry.host)
            self.layout(entry.host)
            entry.prepare()
            self.layout(entry.host)
            self.show(entry.page, on: entry.host, animated: animated, completion: completion)
            if storesPreviousEntry && currentEntry?.page != entry.page {
                self.previousEntries[entry.host] = currentEntry
            }
            self.activeEntries[entry.host] = entry
        }
        
        guard let currentEntry, currentEntry.host != entry.host else {
            presentEntry()
            return
        }
        
        hide(currentEntry.host, animated: false, completion: presentEntry)
    }
    
    private func hide(_ host: Host, animated: Bool, completion: (() -> Void)?) {
        switch host {
        case .embedded:
            contentView.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        case .detached:
            browserChrome.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        }
    }
    
    private func layout(_ host: Host) {
        UIView.performWithoutAnimation {
            switch host {
            case .embedded:
                contentView.layoutOverlayIfNeeded()
            case .detached:
                browserChrome.layoutIfNeeded()
            }
        }
    }
    
    private func setController(_ viewController: UIViewController, for page: Page, on host: Host) {
        switch host {
        case .embedded:
            contentView.setOverlayController(
                viewController,
                for: embeddedPage(for: page),
                in: parentViewController
            )
        case .detached:
            browserChrome.setOverlayController(
                viewController,
                for: detachedPage(for: page),
                in: parentViewController
            )
        }
    }
    
    private func removeController(for page: Page, from host: Host) {
        switch host {
        case .embedded:
            contentView.removeOverlayController(for: embeddedPage(for: page))
        case .detached:
            browserChrome.removeOverlayController(for: detachedPage(for: page))
        }
    }
    
    private func show(
        _ page: Page,
        on host: Host,
        animated: Bool,
        completion: (() -> Void)?
    ) {
        switch host {
        case .embedded:
            contentView.setOverlayPresentation(
                .visible(embeddedPage(for: page)),
                animated: animated,
                completion: completion
            )
        case .detached:
            browserChrome.setOverlayPresentation(
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
