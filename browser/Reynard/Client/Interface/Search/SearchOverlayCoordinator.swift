//
//  SearchOverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

protocol SearchOverlayCoordinatorDelegate: AnyObject {
    var searchLayout: BrowserLayout { get }
    var searchWidthMode: SearchWidthMode { get }
    
    func refreshSearchAddressBar()
    func updateSearchLayout(animated: Bool, duration: TimeInterval)
    func endSearchEditing()
}

final class SearchOverlayCoordinator {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.2
    }
    
    private weak var delegate: SearchOverlayCoordinatorDelegate?
    private let overlayCoordinator: OverlayCoordinator
    private unowned let toolbarController: ToolbarController
    private unowned let browserChrome: BrowserChrome
    private unowned let contentView: ContentView
    private unowned let tabManager: TabManager
    private let searchViewController: SearchViewController
    private var query = ""
    private var restoresSuggestionsOnFocus = false
    private var searchTransitionID = 0
    
    private(set) var isFocused = false
    
    var canNavigateSuggestions: Bool {
        return isVisible && searchViewController.hasSuggestions
    }
    
    // MARK: - Lifecycle
    
    init(
        delegate: SearchOverlayCoordinatorDelegate,
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
        searchViewController = SearchViewController()
        searchViewController.delegate = self
        searchViewController.overlayContentHeightDidChange = { [weak self] contentHeight in
            self?.updateDetachedContentHeight(contentHeight)
        }
    }
    
    private var isVisible: Bool {
        guard let host = searchContentMode?.overlayHost else {
            return false
        }
        
        return overlayCoordinator.isPresented(.search, on: host)
    }
    
    private var searchContentMode: SearchContentMode? {
        guard let layout = delegate?.searchLayout else {
            return nil
        }
        
        return SearchContentMode.current(
            layout: layout,
            widthMode: delegate?.searchWidthMode ?? .standard
        )
    }
    
    private var searchableOpenTabs: [UserDataSearch.OpenTab] {
        return tabManager.activeTabs
            .filter { $0 !== tabManager.selectedTab }
            .map { UserDataSearch.OpenTab(id: $0.id, title: $0.title, url: $0.url) }
    }
    
    var preservesAddressBarText: Bool {
        return overlayCoordinator.isAddressBarScrollDismissed(for: .search) && isVisible
    }
    
    var chromeState: BrowserChrome.SearchState {
        guard isFocused else { return .inactive }
        if let scrollDismissalState = overlayCoordinator.chromeStateForAddressBarScrollDismissal(for: .search, layout: delegate?.searchLayout ?? .initial(interfaceIdiom: .phone)) {
            return scrollDismissalState
        }
        return .focused
    }
    
    private func clearSuggestions() {
        query = ""
        searchViewController.clearSuggestions()
    }
    
    // MARK: - Address Bar Events
    
    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        delegate?.refreshSearchAddressBar()
        overlayCoordinator.clearAddressBarScrollDismissal(for: .search)
        updatePresentedLayout()
        if restoresSuggestionsOnFocus {
            restoresSuggestionsOnFocus = false
            presentSearchIfNeeded()
        } else {
            clearSuggestions()
        }
        setFocused(true, animated: true)
    }
    
    func addressBar(_ addressBar: AddressBar, didChangeText query: String, previousText: String, isDelete: Bool) {
        browserChrome.addressBar.recordEditForAutocomplete(previousText: previousText, currentText: query, isDelete: isDelete)
        guard shouldShowSearchSuggestions(in: tabManager.selectedTabMode) else {
            self.query = query
            dismissSearch(animated: true) { [weak self] in
                self?.searchViewController.clearSuggestions()
            }
            return
        }
        
        guard !query.isEmpty else {
            dismissSearch(animated: true) { [weak self] in
                self?.clearSuggestions()
            }
            return
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            self.query = query
            dismissSearch(animated: true)
            searchViewController.updateQuery(query, openTabs: searchableOpenTabs)
            return
        }
        
        self.query = query
        presentSearchIfNeeded()
        searchViewController.updateQuery(query, openTabs: searchableOpenTabs)
    }
    
    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if overlayCoordinator.consumeAddressBarScrollDismissal(for: .search) {
            restoresSuggestionsOnFocus = true
            updatePresentedLayout()
            delegate?.updateSearchLayout(animated: false, duration: UX.layoutAnimationDuration)
            return
        }
        
        delegate?.refreshSearchAddressBar()
        dismissSearch(animated: true) { [weak self] in
            self?.clearSuggestions()
        }
        if !browserChrome.addressBar.isEditingText {
            setFocused(false, animated: true)
        }
    }
    
    // MARK: - Presentation
    
    private func presentSearchIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              shouldShowSearchSuggestions(in: tabManager.selectedTabMode),
              !isVisible else {
            return
        }
        
        presentSearch(animated: true)
    }
    
    private func dismissSearch(animated: Bool, completion: (() -> Void)? = nil) {
        searchTransitionID += 1
        let transitionID = searchTransitionID
        overlayCoordinator.dismiss(.search, animated: animated) { [weak self] in
            guard let self,
                  self.searchTransitionID == transitionID else {
                completion?()
                return
            }
            self.toolbarController.unlock(for: .searchOverlay)
            completion?()
        }
    }
    
    func updatePresentedLayout() {
        guard isVisible else {
            return
        }
        
        guard let targetHost = searchContentMode?.overlayHost else {
            return
        }
        guard !overlayCoordinator.isPresented(.search, on: targetHost) else {
            configureOverlay()
            return
        }
        
        dismissSearch(animated: false)
        presentSearch(animated: false)
    }
    
    // MARK: - Search Session
    
    func endSearchSession() {
        restoresSuggestionsOnFocus = false
        overlayCoordinator.clearAddressBarScrollDismissal(for: .search)
        browserChrome.addressBar.setEditingState(.inactive)
        delegate?.updateSearchLayout(animated: true, duration: UX.layoutAnimationDuration)
        dismissSearch(animated: true) {
            self.clearSuggestions()
        }
        if !browserChrome.addressBar.isEditingText {
            setFocused(false, animated: true)
        }
        delegate?.refreshSearchAddressBar()
        delegate?.endSearchEditing()
    }
    
    func moveSuggestionSelection(by offset: Int) {
        guard isVisible else {
            return
        }
        searchViewController.moveSuggestionSelection(by: offset)
    }
    
    func submitSelectedSuggestion() -> Bool {
        guard isVisible else {
            return false
        }
        return searchViewController.submitSelectedSuggestion()
    }
    
    // MARK: - Layout
    
    private func presentSearch(animated: Bool) {
        guard shouldShowSearchSuggestions(in: tabManager.selectedTabMode) else {
            return
        }
        
        guard let targetHost = searchContentMode?.overlayHost else {
            return
        }
        searchTransitionID += 1
        toolbarController.lock(for: .searchOverlay)
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
        browserChrome.setOverlayHeightMode(.content)
        browserChrome.setOverlayAvailableContentHeight(contentView.bounds.height)
    }
    
    private func updateDetachedContentHeight(_ contentHeight: CGFloat) {
        guard overlayCoordinator.isPresented(.search, on: .detached) else {
            return
        }
        
        browserChrome.setOverlayContentHeight(contentHeight)
    }
    
    func setFocused(_ focused: Bool, animated: Bool) {
        isFocused = focused
        if focused {
            contentView.resetFocusedInputRelocation()
        }
        delegate?.updateSearchLayout(animated: animated, duration: UX.layoutAnimationDuration)
    }
    
    func tabOverviewWillPresent() {
        if searchContentMode?.overlayHost == .detached {
            dismissSearch(animated: false)
        }
    }
    
    func resetPresentationSession() {
        query = ""
        restoresSuggestionsOnFocus = false
        isFocused = false
        searchTransitionID += 1
        toolbarController.unlock(for: .searchOverlay)
        overlayCoordinator.clearAddressBarScrollDismissal(for: .search)
        searchViewController.clearSuggestions()
    }
    
    private func switchToTab(id: UUID) {
        guard let tab = tabManager.activeTabs.first(where: { $0.id == id }) else {
            return
        }
        
        tabManager.selectTab(tab)
    }
    
    private func shouldShowSearchSuggestions(in tabMode: TabMode) -> Bool {
        guard Prefs.SearchSettings.showSearchSuggestions else {
            return false
        }
        
        return tabMode != .private || Prefs.SearchSettings.showSearchSuggestionsInPrivateBrowsing
    }
}

extension SearchOverlayCoordinator: AddressBarSearchDelegate, SearchViewControllerDelegate {
    func addressBarDidSubmit(_ searchTerm: String) {
        overlayCoordinator.clearAddressBarScrollDismissal(for: .search)
        tabManager.browse(to: searchTerm)
        delegate?.endSearchEditing()
    }
    
    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        if overlayCoordinator.endAddressBarScrollDismissal(for: .search) {
            endSearchSession()
            return
        }
        
        if preservesAddressBarText {
            endSearchSession()
            return
        }
        
        browserChrome.addressBar.clearAutocomplete()
        delegate?.endSearchEditing()
    }
    
    func searchViewControllerDidStartScrolling(_ controller: SearchViewController) {
        overlayCoordinator.beginAddressBarScrollDismissal(for: .search)
    }
    
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, result: UserDataSearchResult?) {
        if overlayCoordinator.isAddressBarScrollDismissed(for: .search) {
            endSearchSession()
        }
        
        if let result,
           result.source == .tab,
           let tabID = result.tabID {
            switchToTab(id: tabID)
            delegate?.endSearchEditing()
            return
        }
        
        tabManager.browse(to: suggestion)
        delegate?.endSearchEditing()
    }
    
    func searchViewController(_ controller: SearchViewController, didUpdateAutocompleteFor query: String, result: UserDataSearchResult?, topDomain: String?) {
        browserChrome.addressBar.applySearchAutocomplete(
            query: query,
            result: result,
            topDomain: topDomain
        )
    }
}
