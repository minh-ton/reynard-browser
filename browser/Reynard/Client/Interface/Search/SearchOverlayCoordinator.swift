//
//  SearchOverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

protocol AddressBarSearchDelegate: AnyObject {
    func addressBarDidSubmit(_ searchTerm: String)
    func addressBarDidTapDismiss(_ addressBar: AddressBar)
    func addressBarDidBeginEditing(_ addressBar: AddressBar)
    func addressBarDidEndEditing(_ addressBar: AddressBar)
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool)
}

protocol SearchOverlayCoordinatorDelegate: AnyObject {
    var searchLayout: BrowserLayout { get }
    var searchChrome: BrowserChrome { get }
    var searchContentView: ContentView { get }
    var searchSelectedTabMode: TabMode { get }
    var searchSelectedTabID: UUID? { get }
    var searchActiveTabs: [Tab] { get }
    var isSearchAddressBarEditing: Bool { get }
    var isSearchAddressBarShowingAutocomplete: Bool { get }
    
    func refreshSearchAddressBar()
    func updateSearchLayout(animated: Bool, duration: TimeInterval)
    func browseSearchTerm(_ term: String)
    func selectSearchTab(at index: Int, mode: TabMode)
    func endSearchEditing()
}

final class SearchOverlayCoordinator {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.2
    }
    
    private weak var delegate: SearchOverlayCoordinatorDelegate?
    private let overlayCoordinator: OverlayCoordinator
    private let searchViewController: SearchViewController
    private var query = ""
    private var pendingScrollDismissal = false
    private var restoresSuggestionsOnFocus = false
    
    private(set) var isFocused = false
    private var isScrollDismissed = false
    
    // MARK: - Lifecycle
    
    init(delegate: SearchOverlayCoordinatorDelegate, overlayCoordinator: OverlayCoordinator) {
        self.delegate = delegate
        self.overlayCoordinator = overlayCoordinator
        searchViewController = SearchViewController()
        searchViewController.delegate = self
        searchViewController.overlayContentHeightDidChange = { [weak self] contentHeight in
            self?.updateDetachedContentHeight(contentHeight)
        }
    }
    
    private var isVisible: Bool {
        return overlayCoordinator.isPresented(.search)
    }
    
    var preservesAddressBarText: Bool {
        return isScrollDismissed && isVisible
    }
    
    var chromeState: BrowserChrome.SearchState {
        guard isFocused else { return .inactive }
        guard preservesAddressBarText else { return .focused }
        return delegate?.searchLayout.overlayHost == .detached
        ? .scrollingDetachedSuggestions
        : .scrollingEmbeddedSuggestions
    }
    
    private func clearSuggestions() {
        query = ""
        searchViewController.clearSuggestions()
    }
    
    // MARK: - Address Bar Events
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        delegate?.refreshSearchAddressBar()
        isScrollDismissed = false
        updateLayoutIfNeeded()
        if restoresSuggestionsOnFocus {
            restoresSuggestionsOnFocus = false
            showIfNeeded()
        } else {
            clearSuggestions()
        }
        setFocused(true, animated: true)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText query: String, previousText: String, isDelete: Bool) {
        guard let delegate else {
            return
        }
        
        delegate.searchChrome.recordAddressBarEdit(previousText: previousText, currentText: query, isDelete: isDelete)
        guard !query.isEmpty else {
            overlayCoordinator.dismiss(.search, animated: true) { [weak self] in
                self?.clearSuggestions()
            }
            return
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            self.query = query
            overlayCoordinator.dismiss(.search, animated: true)
            searchViewController.updateQuery(
                query,
                activeTabMode: delegate.searchSelectedTabMode,
                excludingTabID: delegate.searchSelectedTabID
            )
            return
        }
        
        self.query = query
        showIfNeeded()
        searchViewController.updateQuery(
            query,
            activeTabMode: delegate.searchSelectedTabMode,
            excludingTabID: delegate.searchSelectedTabID
        )
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if pendingScrollDismissal {
            pendingScrollDismissal = false
            restoresSuggestionsOnFocus = true
            isScrollDismissed = true
            delegate?.searchChrome.setAddressBarEditingState(.composing)
            delegate?.searchChrome.setPreservesAddressBarAutocompleteAfterResign(true)
            updateLayoutIfNeeded()
            delegate?.updateSearchLayout(animated: false, duration: UX.layoutAnimationDuration)
            return
        }
        
        delegate?.refreshSearchAddressBar()
        overlayCoordinator.dismiss(.search, animated: true) { [weak self] in
            self?.clearSuggestions()
        }
        if delegate?.isSearchAddressBarEditing != true {
            setFocused(false, animated: true)
        }
    }
    
    // MARK: - Presentation
    
    private func showIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isVisible else {
            return
        }
        
        show(animated: true)
    }
    
    private func hideNow() {
        overlayCoordinator.dismiss(.search, animated: false)
    }
    
    func updateLayoutIfNeeded() {
        guard isVisible else {
            return
        }
        
        guard let targetHost = delegate?.searchLayout.overlayHost else {
            return
        }
        guard overlayCoordinator.host(for: .search) != targetHost else {
            configureOverlay()
            return
        }
        
        hideNow()
        show(animated: false)
    }
    
    // MARK: - Search Session
    
    func endSearchSession() {
        restoresSuggestionsOnFocus = false
        isScrollDismissed = false
        delegate?.searchChrome.setAddressBarEditingState(.inactive)
        delegate?.searchChrome.setPreservesAddressBarAutocompleteAfterResign(false)
        overlayCoordinator.dismiss(.search, animated: true) {
            self.clearSuggestions()
        }
        if delegate?.isSearchAddressBarEditing != true {
            setFocused(false, animated: true)
        }
        delegate?.refreshSearchAddressBar()
    }
    
    // MARK: - Layout
    
    private func show(animated: Bool) {
        guard let targetHost = delegate?.searchLayout.overlayHost else {
            return
        }
        overlayCoordinator.present(
            searchViewController,
            for: .search,
            on: targetHost,
            animated: animated
        ) { [weak self] in
            self?.configureOverlay()
        }
    }
    
    private func configureOverlay() {
        guard let delegate else {
            return
        }
        
        searchViewController.setChromeMode(delegate.searchLayout.chromeMode)
        delegate.searchChrome.setOverlayHeightMode(.content)
        delegate.searchChrome.setOverlayAvailableContentHeight(delegate.searchContentView.bounds.height)
    }
    
    private func updateDetachedContentHeight(_ contentHeight: CGFloat) {
        guard overlayCoordinator.host(for: .search) == .detached else {
            return
        }
        
        delegate?.searchChrome.setOverlayContentHeight(contentHeight)
    }
    
    func setFocused(_ focused: Bool, animated: Bool) {
        isFocused = focused
        if focused {
            delegate?.searchContentView.resetFocusedInputRelocation()
        }
        delegate?.updateSearchLayout(animated: animated, duration: UX.layoutAnimationDuration)
    }
    
    func tabOverviewWillPresent() {
        if delegate?.searchLayout.overlayHost == .detached {
            hideNow()
        }
    }
    
    private func switchToTab(id: UUID) {
        guard let delegate,
              let index = delegate.searchActiveTabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        delegate.selectSearchTab(at: index, mode: delegate.searchSelectedTabMode)
    }
}

extension SearchOverlayCoordinator: AddressBarSearchDelegate, SearchViewControllerDelegate {
    func addressBarDidSubmit(_ searchTerm: String) {
        delegate?.browseSearchTerm(searchTerm)
        delegate?.endSearchEditing()
    }
    
    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        if preservesAddressBarText {
            endSearchSession()
            return
        }
        
        delegate?.searchChrome.clearAddressBarAutocomplete()
        delegate?.endSearchEditing()
    }
    
    func searchViewControllerDidStartScrolling(_ controller: SearchViewController) {
        guard delegate?.isSearchAddressBarEditing == true else {
            return
        }
        
        pendingScrollDismissal = true
        delegate?.searchChrome.setPreservesAddressBarAutocompleteAfterResign(
            delegate?.isSearchAddressBarShowingAutocomplete == true
        )
        delegate?.searchChrome.resignAddressBarFirstResponder()
    }
    
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, result: UserDataSearchResult?) {
        if isScrollDismissed {
            endSearchSession()
        }
        
        if let result,
           result.source == .tab,
           let tabID = result.tabID {
            delegate?.endSearchEditing()
            switchToTab(id: tabID)
            return
        }
        
        delegate?.browseSearchTerm(suggestion)
        delegate?.endSearchEditing()
    }
    
    func searchViewController(_ controller: SearchViewController, didUpdateAutocompleteFor query: String, result: UserDataSearchResult?) {
        delegate?.searchChrome.applyAddressBarAutocomplete(query: query, result: result)
    }
}
