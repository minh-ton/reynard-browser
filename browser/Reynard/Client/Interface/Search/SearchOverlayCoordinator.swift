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

final class SearchOverlayCoordinator {
    // MARK: - State

    private unowned let controller: BrowserViewController
    private let overlayCoordinator: OverlayCoordinator
    private let searchViewController: SearchViewController
    private var query = ""
    private var pendingScrollDismissal = false
    private var restoresSuggestionsOnFocus = false

    private(set) var isFocused = false
    private var isScrollDismissed = false

    // MARK: - Lifecycle

    init(controller: BrowserViewController, overlayCoordinator: OverlayCoordinator) {
        self.controller = controller
        self.overlayCoordinator = overlayCoordinator
        searchViewController = SearchViewController()
        searchViewController.delegate = self
        searchViewController.overlayContentHeightDidChange = { [weak self] contentHeight in
            self?.updateDetachedContentHeight(contentHeight)
        }
    }

    private var isVisible: Bool {
        overlayCoordinator.isPresented(.search)
    }

    var preservesAddressBarText: Bool {
        isScrollDismissed && isVisible
    }

    var chromeState: BrowserChrome.SearchState {
        guard isFocused else { return .inactive }
        guard preservesAddressBarText else { return .focused }
        return usesDetachedOverlay ? .scrollingDetachedSuggestions : .scrollingEmbeddedSuggestions
    }

    // MARK: - Suggestions

    private func clearSuggestions() {
        query = ""
        searchViewController.clearSuggestions()
    }

    // MARK: - Address Bar Events

    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        controller.refreshAddressBar()
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
        controller.browserUI.browserChrome.recordAddressBarEdit(previousText: previousText, currentText: query, isDelete: isDelete)
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
                activeTabMode: controller.tabManager.selectedTabMode,
                excludingTabID: controller.tabManager.selectedTab?.id
            )
            return
        }

        self.query = query
        showIfNeeded()
        searchViewController.updateQuery(
            query,
            activeTabMode: controller.tabManager.selectedTabMode,
            excludingTabID: controller.tabManager.selectedTab?.id
        )
    }

    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        if pendingScrollDismissal {
            pendingScrollDismissal = false
            restoresSuggestionsOnFocus = true
            isScrollDismissed = true
            controller.browserUI.browserChrome.setAddressBarEditingState(.composing)
            controller.browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(true)
            updateLayoutIfNeeded()
            controller.browserUI.applyChromeLayout(animated: false)
            return
        }

        controller.refreshAddressBar()
        overlayCoordinator.dismiss(.search, animated: true) { [weak self] in
            self?.clearSuggestions()
        }
        if !controller.browserUI.browserChrome.isAddressBarEditing {
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

        let targetHost = resolvedHost
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
        controller.browserUI.browserChrome.setAddressBarEditingState(.inactive)
        controller.browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(false)
        overlayCoordinator.dismiss(.search, animated: true) {
            self.clearSuggestions()
        }
        if !controller.browserUI.browserChrome.isAddressBarEditing {
            setFocused(false, animated: true)
        }
        controller.refreshAddressBar()
    }

    // MARK: - Layout

    private var resolvedHost: OverlayCoordinator.Host {
        usesDetachedOverlay ? .detached : .embedded
    }

    private var usesDetachedOverlay: Bool {
        guard !controller.usesCompactPadChrome else { return false }
        if controller.isPad { return true }
        if let orientation = controller.view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }
        return controller.view.bounds.width > controller.view.bounds.height
    }

    private var currentChromeMode: ChromeMode {
        controller.usesCompactPadChrome ? .compact : (controller.usesPadChrome ? .pad : .phone)
    }

    private func show(animated: Bool) {
        let targetHost = resolvedHost
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
        searchViewController.setChromeMode(currentChromeMode)
        controller.browserUI.browserChrome.setOverlayHeightMode(.content)
        controller.browserUI.browserChrome.setOverlayAvailableContentHeight(controller.browserUI.contentView.bounds.height)
    }

    private func updateDetachedContentHeight(_ contentHeight: CGFloat) {
        guard overlayCoordinator.host(for: .search) == .detached else {
            return
        }

        controller.browserUI.browserChrome.setOverlayContentHeight(contentHeight)
    }

    func setFocused(_ focused: Bool, animated: Bool) {
        isFocused = focused
        if focused {
            controller.browserUI.resetFocusedInputRelocation()
        }
        controller.browserUI.applyChromeLayout(animated: animated, duration: 0.2)
    }

    func tabOverviewWillPresent() {
        if usesDetachedOverlay {
            hideNow()
        }
    }

    private func switchToTab(id: UUID) {
        let activeTabs = controller.tabManager.selectedTabMode == .private
            ? controller.tabManager.privateTabs
            : controller.tabManager.regularTabs
        guard let index = activeTabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        controller.selectTab(at: index, animated: true)
    }
}

extension SearchOverlayCoordinator: AddressBarSearchDelegate, SearchViewControllerDelegate {
    func addressBarDidSubmit(_ searchTerm: String) {
        controller.browse(to: searchTerm)
        controller.view.endEditing(true)
    }

    func addressBarDidTapDismiss(_ addressBar: AddressBar) {
        if preservesAddressBarText {
            endSearchSession()
            return
        }

        controller.browserUI.browserChrome.clearAddressBarAutocomplete()
        controller.view.endEditing(true)
    }

    func searchViewControllerDidStartScrolling(_ controller: SearchViewController) {
        guard self.controller.browserUI.browserChrome.isAddressBarEditing else {
            return
        }

        pendingScrollDismissal = true
        self.controller.browserUI.browserChrome.setPreservesAddressBarAutocompleteAfterResign(
            self.controller.browserUI.browserChrome.isShowingAddressBarAutocomplete
        )
        self.controller.browserUI.browserChrome.resignAddressBarFirstResponder()
    }

    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, result: UserDataSearchResult?) {
        if isScrollDismissed {
            endSearchSession()
        }

        self.controller.view.endEditing(true)
        if let result,
           result.source == .tab,
           let tabID = result.tabID {
            switchToTab(id: tabID)
            return
        }

        self.controller.browse(to: suggestion)
    }

    func searchViewController(_ controller: SearchViewController, didUpdateAutocompleteFor query: String, result: UserDataSearchResult?) {
        self.controller.browserUI.browserChrome.applyAddressBarAutocomplete(query: query, result: result)
    }
}
