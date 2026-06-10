//  HistoryManagerView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class HistoryManagerView: UIView {
    private weak var hostedViewController: HistoryManagerViewController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        embedViewControllerIfNeeded()
    }
    
    private func embedViewControllerIfNeeded() {
        guard hostedViewController == nil,
              let parentViewController = containingViewController else {
            return
        }
        
        let historyViewController = HistoryManagerViewController()
        historyViewController.view.translatesAutoresizingMaskIntoConstraints = false
        historyViewController.view.backgroundColor = .clear
        
        parentViewController.addChild(historyViewController)
        addSubview(historyViewController.view)
        
        NSLayoutConstraint.activate([
            historyViewController.view.topAnchor.constraint(equalTo: topAnchor),
            historyViewController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            historyViewController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            historyViewController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        historyViewController.didMove(toParent: parentViewController)
        hostedViewController = historyViewController
    }
}

private extension UIView {
    var containingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
}

private final class HistoryManagerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private struct Section {
        let day: Date
        let title: String
        var items: [HistorySiteSnapshot]
    }
    
    private enum Constants {
        static let queryFetchLimit = 100
        static let historyPanelPrefetchOffset = 8
        static let searchQueryFetchLimit = 50
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
    
    private lazy var clearHistoryButton = MakeButtons.makeLibraryActionsButton(
        target: self,
        imageName: "clock.badge.xmark",
        action: #selector(clearHistoryButtonTapped)
    )
    private lazy var clearHistoryBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(named: "clock.badge.xmark"),
            style: .plain,
            target: self,
            action: #selector(clearHistoryButtonTapped)
        )
        item.tag = MakeButtons.historyLibraryActionBarButtonTag
        return item
    }()
    private var usesNavigationActionsButton: Bool {
        if #available(iOS 26.0, *) {
            return MakeButtons.hasLiquidGlass
        }
        
        return false
    }
    
    private let headerContainerView: UIView = {
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
        view.estimatedRowHeight = 72
        view.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = 0
        }
        view.register(HistoryItemCell.self, forCellReuseIdentifier: HistoryItemCell.reuseIdentifier)
        return view
    }()
    
    private let emptyStateView = LibraryEmptyBackgroundView(message: "Your browsing history appears here")
    private var sections: [Section] = []
    private var historyObserver: NSObjectProtocol?
    private var currentFetchOffset = 0
    private var hasMoreHistory = true
    private var isFetchInProgress = false
    private var currentSearchTerm = ""
    private var requestGeneration = 0
    private var suppressNextReload = false
    private var hasStoredHistory = false
    
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
        
        setupHeaderView()
        
        historyObserver = NotificationCenter.default.addObserver(
            forName: .historyStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.suppressNextReload {
                self.suppressNextReload = false
                return
            }
            self.reloadHistory()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        tableView.addGestureRecognizer(tapGesture)
        
        refreshSearchBarVisibility()
        reloadHistory()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderSizeIfNeeded()
        tableView.backgroundView?.frame = tableView.bounds
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installNavigationActionsButtonIfNeeded()
    }
    
    private func setupHeaderView() {
        headerContainerView.layoutMargins = tableView.layoutMargins
        headerContainerView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [
            searchBar.topAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.leadingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor)
        ]
        
        if usesNavigationActionsButton {
            constraints.append(searchBar.trailingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.trailingAnchor))
        } else {
            headerContainerView.addSubview(clearHistoryButton)
            clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: clearHistoryButton.leadingAnchor),
                clearHistoryButton.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor, constant: -20),
                clearHistoryButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                clearHistoryButton.widthAnchor.constraint(equalTo: clearHistoryButton.heightAnchor),
                clearHistoryButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerContainerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        updateHeaderFittingHeight()
        
    }
    
    private func refreshSearchBarVisibility() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hasStoredHistory = !HistoryStore.shared.snapshot(limit: 1, offset: 0).items.isEmpty
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                self.hasStoredHistory = hasStoredHistory
                self.updateSearchBarVisibility()
            }
        }
    }
    
    private func updateSearchBarVisibility() {
        if hasStoredHistory {
            if tableView.tableHeaderView !== headerContainerView {
                tableView.tableHeaderView = headerContainerView
                updateHeaderSizeIfNeeded()
            }
            return
        }
        
        if tableView.tableHeaderView != nil {
            tableView.tableHeaderView = nil
        }
    }
    
    @objc private func handleBackgroundTap() {
        searchBar.resignFirstResponder()
    }
    
    @objc private func clearHistoryButtonTapped() {
        searchBar.resignFirstResponder()
        
        let browserViewController = resolvedBrowserViewController()
        let viewController = ClearHistoryViewController(tabCount: browserViewController?.tabManager.regularTabs.count ?? 0) { [weak browserViewController] startDate, shouldCloseTabs in
            HistoryStore.shared.clearHistory(since: startDate)
            
            if shouldCloseTabs {
                browserViewController?.clearAllTabs()
                browserViewController?.createTab(selecting: true, isPrivate: false)
            }
        }
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    private func installNavigationActionsButtonIfNeeded() {
        guard usesNavigationActionsButton,
              let navigationItem = navigationController?.topViewController?.navigationItem else {
            return
        }
        
        clearHistoryBarButtonItem.tintColor = .label
        MakeButtons.installLibraryActionBarButton(clearHistoryBarButtonItem, in: navigationItem)
    }
    
    private func updateHeaderFittingHeight() {
        headerContainerView.setNeedsLayout()
        headerContainerView.layoutIfNeeded()
        
        let targetSize = CGSize(width: headerContainerView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = headerContainerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        
        var frame = headerContainerView.frame
        if frame.height != height {
            frame.size.height = height
            headerContainerView.frame = frame
            tableView.tableHeaderView = headerContainerView
        }
    }
    
    private func updateHeaderSizeIfNeeded() {
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else { return }
        
        var frame = headerContainerView.frame
        guard frame.width != targetWidth else { return }
        
        frame.size.width = targetWidth
        headerContainerView.frame = frame
        updateHeaderFittingHeight()
    }
    
    private func reloadHistory() {
        refreshSearchBarVisibility()
        if !currentSearchTerm.isEmpty {
            performSearch(term: currentSearchTerm)
            return
        }
        
        resetPagedHistoryAndLoad()
    }
    
    private func resetPagedHistoryAndLoad() {
        requestGeneration += 1
        currentFetchOffset = 0
        hasMoreHistory = true
        isFetchInProgress = false
        sections = []
        tableView.reloadData()
        updateBackgroundView()
        loadNextPage()
    }
    
    private func loadNextPage() {
        guard currentSearchTerm.isEmpty, hasMoreHistory, !isFetchInProgress else {
            return
        }
        
        isFetchInProgress = true
        let offset = currentFetchOffset
        let generation = requestGeneration
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let items = HistoryStore.shared.snapshot(limit: Constants.queryFetchLimit, offset: offset).items
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.requestGeneration == generation, self.currentSearchTerm.isEmpty else {
                    return
                }
                
                self.applyPage(items, reset: offset == 0)
                self.currentFetchOffset += items.count
                self.hasMoreHistory = items.count == Constants.queryFetchLimit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isFetchInProgress = false
                }
            }
        }
    }
    
    private func applyPage(_ items: [HistorySiteSnapshot], reset: Bool) {
        let fetchedSections = makeSections(from: items)
        
        if reset {
            sections = fetchedSections
            updateBackgroundView()
            tableView.reloadData()
            return
        }
        
        guard !fetchedSections.isEmpty else {
            updateBackgroundView()
            return
        }
        
        updateBackgroundView()
        
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
    
    private func performSearch(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            currentSearchTerm = ""
            HistoryStore.shared.interruptReader()
            resetPagedHistoryAndLoad()
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
        
        currentSearchTerm = normalizedTerm
        
        HistoryStore.shared.interruptReader()
        requestGeneration += 1
        let generation = requestGeneration
        isFetchInProgress = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let items = HistoryStore.shared.search(matching: normalizedTerm, limit: Constants.searchQueryFetchLimit).items
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.requestGeneration == generation, self.currentSearchTerm == normalizedTerm else {
                    return
                }
                
                self.sections = self.makeSections(from: items)
                self.hasMoreHistory = false
                self.updateBackgroundView()
                self.tableView.reloadData()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isFetchInProgress = false
                }
            }
        }
    }
    
    private func updateBackgroundView() {
        let hasHistory = !sections.isEmpty
        emptyStateView.message = currentSearchTerm.isEmpty ? "Your browsing history appears here" : "No matching history"
        tableView.backgroundView = hasHistory ? nil : emptyStateView
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    private func makeSections(from items: [HistorySiteSnapshot]) -> [Section] {
        guard !items.isEmpty else {
            return []
        }
        
        let calendar = Calendar.current
        let groupedItems = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.lastVisitedAt)
        }
        
        return groupedItems.keys.sorted(by: >).compactMap { day in
            guard let items = groupedItems[day] else {
                return nil
            }
            
            let sortedItems = items.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            return Section(day: day, title: sectionTitle(for: day), items: sortedItems)
        }
    }
    
    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE, d MMMM")
        return formatter.string(from: date)
    }
    
    private func item(at indexPath: IndexPath) -> HistorySiteSnapshot? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.row) else {
            return nil
        }
        
        return sections[indexPath.section].items[indexPath.row]
    }
    
    private var loadedItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }
    
    private func flatIndex(for indexPath: IndexPath) -> Int {
        let priorCount = sections[..<indexPath.section].reduce(0) { $0 + $1.items.count }
        return priorCount + indexPath.row
    }
    
    private func loadNextPageIfNeeded(for indexPath: IndexPath) {
        let remainingItems = loadedItemCount - flatIndex(for: indexPath) - 1
        guard remainingItems <= Constants.historyPanelPrefetchOffset else {
            return
        }
        
        loadNextPage()
    }
    
    private func openHistoryItem(_ item: HistorySiteSnapshot) {
        guard let browserViewController = resolvedBrowserViewController() else {
            return
        }
        
        browserViewController.loadViewIfNeeded()
        browserViewController.browse(to: item.url.absoluteString)
        
        if navigationController?.presentingViewController is BrowserViewController {
            navigationController?.dismiss(animated: true)
        }
    }
    
    private func resolvedBrowserViewController() -> BrowserViewController? {
        if let splitViewController = splitViewController as? BrowserSplitViewController {
            return splitViewController.contentBrowserViewController
        }
        
        if let browserViewController = navigationController?.presentingViewController as? BrowserViewController {
            return browserViewController
        }
        
        return view.window?.rootViewController.flatMap { resolvedBrowserViewController(from: $0) }
    }
    
    private func resolvedBrowserViewController(from controller: UIViewController) -> BrowserViewController? {
        if let browserViewController = controller as? BrowserViewController {
            return browserViewController
        }
        
        if let navigationController = controller as? UINavigationController {
            return navigationController.viewControllers.compactMap { resolvedBrowserViewController(from: $0) }.first
        }
        
        if let tabBarController = controller as? UITabBarController,
           let viewControllers = tabBarController.viewControllers {
            return viewControllers.compactMap { resolvedBrowserViewController(from: $0) }.first
        }
        
        if let splitViewController = controller as? BrowserSplitViewController {
            return splitViewController.contentBrowserViewController
        }
        
        if let presentedViewController = controller.presentedViewController,
           let browserViewController = resolvedBrowserViewController(from: presentedViewController) {
            return browserViewController
        }
        
        return controller.children.compactMap { resolvedBrowserViewController(from: $0) }.first
    }
    
    private func removeItem(at indexPath: IndexPath) {
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
        
        updateBackgroundView()
        refreshSearchBarVisibility()
    }
    
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
        
        cell.apply(item: item)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard sections.indices.contains(section) else {
            return nil
        }
        
        let container = UIView()
        container.backgroundColor = .systemGroupedBackground
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = sections[section].title
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
        ])
        
        return container
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        34
    }
    
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
            
            self.suppressNextReload = true
            HistoryStore.shared.deleteHistoryItem(id: item.id)
            self.removeItem(at: indexPath)
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
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let preserveFocusOnClear = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchBar.isFirstResponder
        performSearch(term: searchText, preserveFocusOnClear: preserveFocusOnClear)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === tableView else {
            return true
        }
        
        var view = touch.view
        while let currentView = view {
            if currentView === searchBar {
                return false
            }
            view = currentView.superview
        }
        
        return true
    }
}

