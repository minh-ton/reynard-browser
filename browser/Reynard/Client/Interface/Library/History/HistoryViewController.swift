//  HistoryViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class HistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private enum UX {
        static let estimatedRowHeight: CGFloat = 72
        static let sectionHeaderTopPadding: CGFloat = 0
        static let groupedSectionHeaderHeight: CGFloat = 34
        static let headerClearButtonTrailingInset: CGFloat = 20
    }
    
    private enum Fetch {
        static let pageSize = 100
        static let prefetchThreshold = 8
        static let searchLimit = 50
    }
    
    private enum FetchState {
        case idle
        case loading
    }
    
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search History"
        searchBar.delegate = self
        return searchBar
    }()
    
    private lazy var clearHistoryButton = LibraryActionButton(
        target: self,
        iconName: "reynard.clock.badge.xmark",
        action: #selector(showClearHistory)
    )
    private lazy var clearHistoryActionItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(named: "reynard.clock.badge.xmark"),
            style: .plain,
            target: self,
            action: #selector(showClearHistory)
        )
        item.tag = LibraryActionButton.historyNavigationActionTag
        return item
    }()
    private var showsNavigationClearAction: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        
        return false
    }
    
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGroupedBackground
        view.dataSource = self
        view.delegate = self
        view.rowHeight = UITableView.automaticDimension
        view.estimatedRowHeight = UX.estimatedRowHeight
        view.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = UX.sectionHeaderTopPadding
        }
        view.register(HistoryItemCell.self, forCellReuseIdentifier: HistoryItemCell.reuseIdentifier)
        return view
    }()
    
    private let emptyStateView = SidebarEmptyBackgroundView(message: "Your browsing history appears here")
    private var sections: [HistorySection] = []
    private var storeObserver: NSObjectProtocol?
    private var nextOffset = 0
    private var hasMoreItems = true
    private var fetchState: FetchState = .idle
    private var query = ""
    private var loadVersion = 0
    private var skipsNextStoreReload = false
    
    // MARK: - Lifecycle
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        installHeader()
        
        storeObserver = NotificationCenter.default.addObserver(
            forName: .historyStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.skipsNextStoreReload {
                self.skipsNextStoreReload = false
                return
            }
            self.reloadHistory()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSearch))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        tableView.addGestureRecognizer(tapGesture)
        
        refreshHistoryPresence()
        reloadHistory()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        LibrarySharedUtils.syncTableHeaderWidth(headerView, in: tableView)
        tableView.backgroundView?.frame = tableView.bounds
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installClearHistoryNavigationActionIfNeeded()
    }
    
    // MARK: - View Setup
    
    private func installHeader() {
        headerView.layoutMargins = tableView.layoutMargins
        headerView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [
            searchBar.topAnchor.constraint(equalTo: headerView.layoutMarginsGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: headerView.layoutMarginsGuide.leadingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ]
        
        if showsNavigationClearAction {
            constraints.append(searchBar.trailingAnchor.constraint(equalTo: headerView.layoutMarginsGuide.trailingAnchor))
        } else {
            headerView.addSubview(clearHistoryButton)
            clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: clearHistoryButton.leadingAnchor),
                clearHistoryButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -UX.headerClearButtonTrailingInset),
                clearHistoryButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                clearHistoryButton.widthAnchor.constraint(equalTo: clearHistoryButton.heightAnchor),
                clearHistoryButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        LibrarySharedUtils.updateTableHeaderHeight(headerView, in: tableView)
        
    }
    
    private func refreshHistoryPresence() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hasHistory = !HistoryStore.shared.currentSnapshot(limit: 1, offset: 0).items.isEmpty
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                self.updateSearchHeaderVisibility(containsHistory: hasHistory)
            }
        }
    }
    
    private func updateSearchHeaderVisibility(containsHistory: Bool) {
        if containsHistory {
            if tableView.tableHeaderView !== headerView {
                tableView.tableHeaderView = headerView
                LibrarySharedUtils.syncTableHeaderWidth(headerView, in: tableView)
            }
            return
        }
        
        if tableView.tableHeaderView != nil {
            tableView.tableHeaderView = nil
        }
    }
    
    @objc private func dismissSearch() {
        searchBar.resignFirstResponder()
    }
    
    // MARK: - Clear History
    
    @objc private func showClearHistory() {
        searchBar.resignFirstResponder()
        
        let browserViewController = findBrowser()
        let viewController = ClearHistoryViewController(tabCount: browserViewController?.tabManager.regularTabs.count ?? 0) { [weak browserViewController] startDate, shouldCloseTabs in
            HistoryStore.shared.clearVisits(since: startDate)
            
            if shouldCloseTabs {
                browserViewController?.tabManager.removeAllTabs(mode: .regular)
                browserViewController?.tabManager.createTab(selecting: true, mode: .regular)
            }
        }
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    private func installClearHistoryNavigationActionIfNeeded() {
        guard showsNavigationClearAction,
              let navigationItem = navigationController?.topViewController?.navigationItem else {
            return
        }
        
        clearHistoryActionItem.tintColor = .label
        LibraryActionButton.installNavigationAction(clearHistoryActionItem, in: navigationItem)
    }
    
    // MARK: - Loading
    
    private func reloadHistory() {
        refreshHistoryPresence()
        if !query.isEmpty {
            searchHistory(term: query)
            return
        }
        
        reloadFirstHistoryPage()
    }
    
    private func reloadFirstHistoryPage() {
        loadVersion += 1
        nextOffset = 0
        hasMoreItems = true
        fetchState = .idle
        loadNextHistoryPage()
    }
    
    private func loadNextHistoryPage() {
        guard query.isEmpty, hasMoreItems, fetchState == .idle else {
            return
        }
        
        fetchState = .loading
        let offset = nextOffset
        let generation = loadVersion
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let items = HistoryStore.shared.currentSnapshot(limit: Fetch.pageSize, offset: offset).items
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.loadVersion == generation, self.query.isEmpty else {
                    return
                }
                
                self.appendHistoryPage(items, reset: offset == 0)
                self.nextOffset += items.count
                self.hasMoreItems = items.count == Fetch.pageSize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.fetchState = .idle
                }
            }
        }
    }
    
    // MARK: - Paging
    
    private func appendHistoryPage(_ items: [HistorySiteSnapshot], reset: Bool) {
        let fetchedSections = HistorySection.make(from: items)
        
        if reset {
            sections = fetchedSections
            updateEmptyState()
            tableView.reloadData()
            return
        }
        
        guard !fetchedSections.isEmpty else {
            updateEmptyState()
            return
        }
        
        updateEmptyState()
        
        if sections.isEmpty {
            sections = fetchedSections
            tableView.reloadData()
            return
        }
        
        var updatedSections = sections
        var mergedRowIndexPaths: [IndexPath] = []
        var sectionsToInsert = fetchedSections[...]
        
        if let lastSectionIndex = updatedSections.indices.last,
           let firstFetchedSection = sectionsToInsert.first,
           updatedSections[lastSectionIndex].day == firstFetchedSection.day {
            let startRow = updatedSections[lastSectionIndex].items.count
            updatedSections[lastSectionIndex].items.append(contentsOf: firstFetchedSection.items)
            mergedRowIndexPaths = firstFetchedSection.items.indices.map {
                IndexPath(row: startRow + $0, section: lastSectionIndex)
            }
            sectionsToInsert = sectionsToInsert.dropFirst()
        }
        
        let insertStartIndex = updatedSections.count
        updatedSections.append(contentsOf: sectionsToInsert)
        sections = updatedSections
        
        tableView.performBatchUpdates {
            if !mergedRowIndexPaths.isEmpty {
                tableView.insertRows(at: mergedRowIndexPaths, with: .none)
            }
            
            if !sectionsToInsert.isEmpty {
                let insertedIndexes = IndexSet(insertStartIndex..<(insertStartIndex + sectionsToInsert.count))
                tableView.insertSections(insertedIndexes, with: .none)
            }
        }
    }
    
    // MARK: - Search
    
    private func searchHistory(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            query = ""
            HistoryStore.shared.interruptReader()
            reloadFirstHistoryPage()
            if preserveFocusOnClear {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchBar.window != nil else {
                        return
                    }
                    
                    self.searchBar.becomeFirstResponder()
                }
            }
            return
        }
        
        query = normalizedTerm
        
        HistoryStore.shared.interruptReader()
        loadVersion += 1
        let generation = loadVersion
        fetchState = .loading
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let items = HistoryStore.shared.search(matching: normalizedTerm, limit: Fetch.searchLimit).items
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.loadVersion == generation, self.query == normalizedTerm else {
                    return
                }
                
                self.sections = HistorySection.make(from: items)
                self.hasMoreItems = false
                self.updateEmptyState()
                self.tableView.reloadData()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.fetchState = .idle
                }
            }
        }
    }
    
    // MARK: - Display State
    
    private func updateEmptyState() {
        let hasRows = !sections.isEmpty
        emptyStateView.message = query.isEmpty ? "Your browsing history appears here" : "No matching history"
        tableView.backgroundView = hasRows ? nil : emptyStateView
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    private func item(at indexPath: IndexPath) -> HistorySiteSnapshot? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.row) else {
            return nil
        }
        
        return sections[indexPath.section].items[indexPath.row]
    }
    
    private var loadedItemCount: Int {
        return sections.reduce(0) { $0 + $1.items.count }
    }
    
    private func flatRowIndex(for indexPath: IndexPath) -> Int {
        let priorCount = sections[..<indexPath.section].reduce(0) { $0 + $1.items.count }
        return priorCount + indexPath.row
    }
    
    private func loadNextPageIfNeeded(for indexPath: IndexPath) {
        let remainingItems = loadedItemCount - flatRowIndex(for: indexPath) - 1
        guard remainingItems <= Fetch.prefetchThreshold else {
            return
        }
        
        loadNextHistoryPage()
    }
    
    // MARK: - Navigation
    
    private func openHistoryItem(_ item: HistorySiteSnapshot) {
        guard let browserViewController = findBrowser() else {
            return
        }
        
        browserViewController.loadViewIfNeeded()
        browserViewController.tabManager.browse(to: item.url.absoluteString)
        
        if navigationController?.presentingViewController is BrowserViewController {
            navigationController?.dismiss(animated: true)
        }
    }
    
    private func findBrowser() -> BrowserViewController? {
        if let sidebarViewController = splitViewController as? SidebarViewController {
            return sidebarViewController.contentBrowser.sidebarContentViewController as? BrowserViewController
        }
        
        if let browserViewController = navigationController?.presentingViewController as? BrowserViewController {
            return browserViewController
        }
        
        return view.window?.rootViewController.flatMap { findBrowser(from: $0) }
    }
    
    private func findBrowser(from controller: UIViewController) -> BrowserViewController? {
        if let browserViewController = controller as? BrowserViewController {
            return browserViewController
        }
        
        if let navigationController = controller as? UINavigationController {
            return navigationController.viewControllers.compactMap { findBrowser(from: $0) }.first
        }
        
        if let tabBarController = controller as? UITabBarController,
           let viewControllers = tabBarController.viewControllers {
            return viewControllers.compactMap { findBrowser(from: $0) }.first
        }
        
        if let sidebarViewController = controller as? SidebarViewController {
            return sidebarViewController.contentBrowser.sidebarContentViewController as? BrowserViewController
        }
        
        if let presentedViewController = controller.presentedViewController,
           let browserViewController = findBrowser(from: presentedViewController) {
            return browserViewController
        }
        
        return controller.children.compactMap { findBrowser(from: $0) }.first
    }
    
    // MARK: - Deletion
    
    private func deleteVisibleRow(at indexPath: IndexPath) {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.row) else {
            return
        }
        
        sections[indexPath.section].items.remove(at: indexPath.row)
        
        if sections[indexPath.section].items.isEmpty {
            sections.remove(at: indexPath.section)
            tableView.deleteSections(IndexSet(integer: indexPath.section), with: .automatic)
        } else {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
        
        updateEmptyState()
        refreshHistoryPresence()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard sections.indices.contains(section) else {
            return 0
        }
        
        return sections[section].items.count
    }
    
    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: HistoryItemCell.reuseIdentifier,
            for: indexPath
        ) as? HistoryItemCell,
              let item = item(at: indexPath) else {
            return UITableViewCell()
        }
        
        cell.configure(with: item)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard sections.indices.contains(section) else {
            return nil
        }
        
        return LibrarySharedUtils.makeGroupedSectionHeader(title: sections[section].title)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UX.groupedSectionHeaderHeight
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        loadNextPageIfNeeded(for: indexPath)
    }
    
    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self, let item = self.item(at: indexPath) else {
                completion(false)
                return
            }
            
            self.skipsNextStoreReload = true
            HistoryStore.shared.removeSite(id: item.id)
            self.deleteVisibleRow(at: indexPath)
            completion(true)
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        openHistoryItem(item)
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let preserveFocusOnClear = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchBar.isFirstResponder
        searchHistory(term: searchText, preserveFocusOnClear: preserveFocusOnClear)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === tableView else {
            return true
        }
        
        return LibrarySharedUtils.isTapOutsideSearchBar(touch, in: tableView, ignoring: searchBar)
    }
}
