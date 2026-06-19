//
//  BookmarksViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class BookmarksViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private enum UX {
        static let searchResultLimit = 50
        static let sectionHeaderTopPadding: CGFloat = 0
        static let headerMenuButtonTrailingInset: CGFloat = 20
        static let emptyStateFontSize: CGFloat = 16
        static let groupedSectionHeaderHeight: CGFloat = 34
    }
    
    private let folderID: String?
    private let store: BookmarkStore
    private var sections: [(title: String, items: [BookmarkContentSnapshot])] = []
    private var query = ""
    private var searchVersion = 0
    private var isRoot: Bool {
        return folderID == nil
    }
    private lazy var newFolderButton = UIBarButtonItem(
        title: "New Folder",
        style: .plain,
        target: self,
        action: #selector(showNewFolderEditor)
    )
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search Bookmarks"
        searchBar.delegate = self
        return searchBar
    }()
    private lazy var bookmarkMenuButton = LibraryActionButton(
        target: self,
        iconName: "reynard.ellipsis",
        action: #selector(didTapBookmarkMenu)
    )
    private var legacyBookmarkMenuDelegate: LibraryLegacyMenuDelegate?
    private lazy var bookmarkMenuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(named: "reynard.ellipsis"),
            style: .plain,
            target: self,
            action: #selector(didTapBookmarkMenu)
        )
        item.tag = LibraryActionButton.bookmarksNavigationActionTag
        return item
    }()
    private let showsNavigationMenu: Bool
    
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.alwaysBounceVertical = true
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = UX.sectionHeaderTopPadding
        }
        return tableView
    }()
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No matching bookmarks"
        label.font = .systemFont(ofSize: UX.emptyStateFontSize, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    // MARK: - Lifecycle
    
    init(folderID: String? = nil, store: BookmarkStore = .shared) {
        self.folderID = folderID
        self.store = store
        if #available(iOS 26.0, *) {
            showsNavigationMenu = folderID == nil
        } else {
            showsNavigationMenu = false
        }
        super.init(nibName: nil, bundle: nil)
        title = "Bookmarks"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        installLayout()
        
        tableView.register(BookmarkItemCell.self, forCellReuseIdentifier: BookmarkItemCell.reuseIdentifier)
        
        if isRoot {
            installHeader()
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSearch))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            tableView.addGestureRecognizer(tapGesture)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadChangedBookmarks),
            name: .bookmarkStoreDidChange,
            object: nil
        )
        
        reloadBookmarkRows()
        updateToolbarItems(animated: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeHeaderIfNeeded()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(isRoot, animated: animated)
        installBookmarkNavigationMenuIfNeeded()
        reloadBookmarkRows()
        updateToolbarItems(animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        updateToolbarItems(animated: animated)
        updateBookmarkMenu()
    }
    
    private func installLayout() {
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = item(at: indexPath) else {
            return UITableViewCell()
        }
        
        let cell = tableView.dequeueReusableCell(
            withIdentifier: BookmarkItemCell.reuseIdentifier,
            for: indexPath
        ) as! BookmarkItemCell
        
        switch item {
        case let .folder(folder):
            cell.configure(folder: folder)
            cell.accessoryType = .disclosureIndicator
            return cell
        case let .bookmark(bookmark):
            cell.configure(bookmark: bookmark)
            cell.accessoryType = .none
            return cell
        }
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
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let item = item(at: indexPath) else {
            return false
        }
        
        switch item {
        case .bookmark:
            return true
        case let .folder(folder):
            return !folder.isProtected
        }
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard query.isEmpty,
              Prefs.BookmarkSettings.sortOrders == .none,
              let item = item(at: indexPath) else {
            return false
        }
        
        if case let .folder(folder) = item {
            return !folder.isProtected
        }
        
        return true
    }
    
    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedDestinationIndexPath.section == sourceIndexPath.section,
              sections.indices.contains(sourceIndexPath.section) else {
            return sourceIndexPath
        }
        
        let protectedLeadingCount = sections[sourceIndexPath.section].items.prefix { item in
            if case let .folder(folder) = item {
                return folder.isProtected
            }
            
            return false
        }.count
        
        guard proposedDestinationIndexPath.row < protectedLeadingCount else {
            return proposedDestinationIndexPath
        }
        
        return IndexPath(row: protectedLeadingCount, section: sourceIndexPath.section)
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        self.tableView(tableView, canEditRowAt: indexPath) ? .delete : .none
    }
    
    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard sourceIndexPath.section == destinationIndexPath.section,
              sections.indices.contains(sourceIndexPath.section),
              sections[sourceIndexPath.section].items.indices.contains(sourceIndexPath.row),
              sections[destinationIndexPath.section].items.indices.contains(destinationIndexPath.row) else {
            reloadBookmarkRows()
            return
        }
        
        let movedItem = sections[sourceIndexPath.section].items.remove(at: sourceIndexPath.row)
        sections[destinationIndexPath.section].items.insert(movedItem, at: destinationIndexPath.row)
        
        let movedGUID: String
        switch movedItem {
        case let .bookmark(bookmark):
            movedGUID = bookmark.guid
        case let .folder(folder):
            movedGUID = folder.guid
        }
        
        let didMove = store.moveBookmarkItem(
            guid: movedGUID,
            to: sections[..<destinationIndexPath.section].reduce(0) { $0 + $1.items.count } + destinationIndexPath.row,
            in: folderID
        )
        
        if !didMove {
            reloadBookmarkRows()
        }
    }
    
    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete,
              item(at: indexPath) != nil else {
            return
        }
        
        _ = deleteItem(at: indexPath)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = item(at: indexPath) else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            
            completion(self.deleteItem(at: indexPath))
        }
        
        guard case let .bookmark(bookmark) = item else {
            return UISwipeActionsConfiguration(actions: [deleteAction])
        }
        
        let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            
            let viewController = EditBookmarkViewController(bookmark: bookmark, store: self.store)
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            self.present(navigationController, animated: true)
            completion(true)
        }
        editAction.backgroundColor = .systemBlue
        
        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }
    
    private func deleteItem(at indexPath: IndexPath) -> Bool {
        guard let item = item(at: indexPath) else {
            return false
        }
        
        let didDelete: Bool
        switch item {
        case let .bookmark(bookmark):
            didDelete = store.removeBookmark(guid: bookmark.guid)
        case let .folder(folder):
            guard !folder.isProtected else {
                return false
            }
            didDelete = store.removeFolder(guid: folder.guid)
        }
        
        reloadBookmarkRows()
        return didDelete
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !isEditing,
              let item = item(at: indexPath) else {
            return
        }
        
        switch item {
        case let .folder(folder):
            let viewController = BookmarksViewController(folderID: folder.guid, store: store)
            navigationController?.pushViewController(viewController, animated: true)
        case let .bookmark(bookmark):
            openBookmarkURL(bookmark)
        }
    }
    
    // MARK: - Actions
    
    @objc private func reloadChangedBookmarks() {
        reloadBookmarkRows()
    }
    
    @objc private func dismissSearch() {
        searchBar.resignFirstResponder()
    }
    
    @objc private func showNewFolderEditor() {
        let viewController = NewBookmarkFolderViewController(selectedFolderID: folderID, store: store)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    @objc private func didTapBookmarkMenu() {
        if isEditing {
            setEditing(false, animated: true)
            return
        }
        
        if #available(iOS 13.0, *) {
            if #unavailable(iOS 14.0) {
                LibrarySharedUtils.presentLegacyContextMenu(from: bookmarkMenuButton)
            }
        }
    }
    
    // MARK: - Menu
    
    private func updateBookmarkMenu() {
        let symbolName = isEditing ? "reynard.checkmark" : "reynard.ellipsis"
        
        if showsNavigationMenu {
            bookmarkMenuItem.image = UIImage(named: symbolName)
            bookmarkMenuItem.tintColor = .label
            
            if #available(iOS 14.0, *) {
                bookmarkMenuItem.menu = isEditing ? nil : makeBookmarkMenu()
                bookmarkMenuItem.target = isEditing ? self : nil
                bookmarkMenuItem.action = isEditing ? #selector(didTapBookmarkMenu) : nil
            }
            
            return
        }
        
        bookmarkMenuButton.setIcon(named: symbolName)
        
        if #available(iOS 14.0, *) {
            bookmarkMenuButton.menu = isEditing ? nil : makeBookmarkMenu()
            bookmarkMenuButton.showsMenuAsPrimaryAction = !isEditing
        }
    }
    
    fileprivate func makeBookmarkMenu() -> UIMenu {
        UIMenu(title: "", children: [
            makeSortMenu(),
            UIAction(
                title: "Show Folders on Top",
                image: UIImage(named: "reynard.text.below.folder"),
                state: Prefs.BookmarkSettings.placeFoldersOnTop ? .on : .off
            ) { [weak self] _ in
                Prefs.BookmarkSettings.placeFoldersOnTop.toggle()
                self?.reloadBookmarkRows()
                self?.updateBookmarkMenu()
            },
            UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [
                UIAction(title: "Edit Bookmarks", image: UIImage(named: "reynard.pencil")) { [weak self] _ in
                    self?.setEditing(true, animated: true)
                },
                UIAction(title: "New Folder", image: UIImage(named: "reynard.folder.badge.plus")) { [weak self] _ in
                    self?.showNewFolderEditor()
                },
            ]),
        ])
    }
    
    private func makeSortMenu() -> UIMenu {
        let selectedOrder = Prefs.BookmarkSettings.sortOrders
        let sortOptions: [(title: String, order: BookmarkSortOrder)] = [
            ("None", .none),
            ("Date Added", .date_added),
            ("Name", .name),
            ("Address", .address),
        ]
        let menu = UIMenu(
            title: "Sort By",
            image: UIImage(named: "reynard.arrow.up.arrow.down"),
            identifier: nil,
            options: [],
            children: sortOptions.map {
                let order = $0.order
                return UIAction(title: $0.title, state: order == selectedOrder ? .on : .off) { [weak self] _ in
                    Prefs.BookmarkSettings.sortOrders = order
                    self?.reloadBookmarkRows()
                    self?.updateBookmarkMenu()
                }
            }
        )
        
        if #available(iOS 15.0, *) {
            menu.subtitle = sortOptions.first { $0.order == selectedOrder }?.title
        }
        
        return menu
    }
    
    private func installBookmarkNavigationMenuIfNeeded() {
        guard showsNavigationMenu,
              let navigationItem = navigationController?.topViewController?.navigationItem else {
            return
        }
        
        updateBookmarkMenu()
        LibraryActionButton.installNavigationAction(bookmarkMenuItem, in: navigationItem)
    }
    
    // MARK: - Bookmark Loading
    
    private func reloadBookmarkRows() {
        if !query.isEmpty {
            searchBookmarks(term: query)
            return
        }
        
        reloadFolder()
    }
    
    private func reloadFolder() {
        let snapshot = store.contents(of: folderID)
        sections = makeBookmarkSections(from: snapshot.items)
        title = snapshot.parent.title
        updateEmptyState()
        tableView.reloadData()
    }
    
    private func updateEmptyState() {
        tableView.backgroundView = sections.isEmpty && !query.isEmpty ? emptyLabel : nil
    }
    
    private func makeBookmarkSections(from newItems: [BookmarkContentSnapshot]) -> [(title: String, items: [BookmarkContentSnapshot])] {
        guard Prefs.BookmarkSettings.placeFoldersOnTop else {
            let sortedItems = sortBookmarks(newItems)
            return sortedItems.isEmpty ? [] : [("Bookmarks", sortedItems)]
        }
        
        let folders = sortBookmarks(newItems.filter {
            if case .folder = $0 {
                return true
            }
            
            return false
        })
        let bookmarks = sortBookmarks(newItems.filter {
            if case .bookmark = $0 {
                return true
            }
            
            return false
        })
        return [
            ("Folders", folders),
            ("Bookmarks", bookmarks),
        ].filter { !$0.items.isEmpty }
    }
    
    private func sortBookmarks(_ newItems: [BookmarkContentSnapshot]) -> [BookmarkContentSnapshot] {
        let values = { (item: BookmarkContentSnapshot) -> (dateAdded: Date, title: String, address: String) in
            switch item {
            case let .folder(folder):
                return (folder.dateAdded, folder.title, folder.title)
            case let .bookmark(bookmark):
                return (bookmark.dateAdded, bookmark.title, bookmark.url.absoluteString)
            }
        }
        let movableItems = newItems.filter { item in
            if case let .folder(folder) = item {
                return !folder.isProtected
            }
            
            return true
        }
        let sortedMovableItems: [BookmarkContentSnapshot]
        switch Prefs.BookmarkSettings.sortOrders {
        case .none:
            return newItems
        case .date_added:
            sortedMovableItems = movableItems.sorted { lhs, rhs in
                let lhsValues = values(lhs)
                let rhsValues = values(rhs)
                if lhsValues.dateAdded == rhsValues.dateAdded {
                    return lhsValues.title.localizedCaseInsensitiveCompare(rhsValues.title) == .orderedAscending
                }
                return lhsValues.dateAdded > rhsValues.dateAdded
            }
        case .name:
            sortedMovableItems = movableItems.sorted { lhs, rhs in
                values(lhs).title.localizedCaseInsensitiveCompare(values(rhs).title) == .orderedAscending
            }
        case .address:
            sortedMovableItems = movableItems.sorted { lhs, rhs in
                values(lhs).address.localizedCaseInsensitiveCompare(values(rhs).address) == .orderedAscending
            }
        }
        
        var movableIndex = 0
        return newItems.map { item in
            if case let .folder(folder) = item, folder.isProtected {
                return item
            }
            
            let sortedItem = sortedMovableItems[movableIndex]
            movableIndex += 1
            return sortedItem
        }
    }
    
    private func item(at indexPath: IndexPath) -> BookmarkContentSnapshot? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.row) else {
            return nil
        }
        
        return sections[indexPath.section].items[indexPath.row]
    }
    
    // MARK: - Header
    
    private func installHeader() {
        headerView.layoutMargins = tableView.layoutMargins
        headerView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [
            searchBar.topAnchor.constraint(equalTo: headerView.layoutMarginsGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: headerView.layoutMarginsGuide.leadingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        ]
        
        if showsNavigationMenu {
            constraints.append(searchBar.trailingAnchor.constraint(equalTo: headerView.layoutMarginsGuide.trailingAnchor))
        } else {
            headerView.addSubview(bookmarkMenuButton)
            bookmarkMenuButton.translatesAutoresizingMaskIntoConstraints = false
            if #available(iOS 13.0, *) {
                if #unavailable(iOS 14.0) {
                    let delegate = LibraryLegacyMenuDelegate { [weak self] in
                        guard let self, !self.isEditing else {
                            return nil
                        }
                        
                        return self.makeBookmarkMenu()
                    }
                    bookmarkMenuButton.addInteraction(UIContextMenuInteraction(delegate: delegate))
                    legacyBookmarkMenuDelegate = delegate
                }
            }
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: bookmarkMenuButton.leadingAnchor),
                bookmarkMenuButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -UX.headerMenuButtonTrailingInset),
                bookmarkMenuButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                bookmarkMenuButton.widthAnchor.constraint(equalTo: bookmarkMenuButton.heightAnchor),
                bookmarkMenuButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        updateBookmarkMenu()
        
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        LibrarySharedUtils.updateTableHeaderHeight(headerView, in: tableView)
    }
    
    private func resizeHeaderIfNeeded() {
        guard folderID == nil else {
            return
        }
        
        LibrarySharedUtils.syncTableHeaderWidth(headerView, in: tableView)
    }
    
    // MARK: - Search
    
    private func searchBookmarks(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            query = ""
            searchVersion += 1
            reloadFolder()
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
        searchVersion += 1
        let generation = searchVersion
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let searchResults = self.store.bookmarks(matching: normalizedTerm, limit: UX.searchResultLimit)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.searchVersion == generation, self.query == normalizedTerm else {
                    return
                }
                
                self.sections = self.makeBookmarkSections(from: searchResults.map { .bookmark($0) })
                self.updateEmptyState()
                self.tableView.reloadData()
            }
        }
    }
    
    // MARK: - Toolbar
    
    private func updateToolbarItems(animated: Bool) {
        guard !isRoot else {
            return
        }
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let items: [UIBarButtonItem]
        if isEditing {
            items = [newFolderButton, flexibleSpace, editButtonItem]
        } else {
            items = [flexibleSpace, editButtonItem]
        }
        setToolbarItems(items, animated: animated)
    }
    
    // MARK: - Navigation
    
    private func openBookmarkURL(_ bookmark: BookmarkSnapshot) {
        guard let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self) else {
            return
        }
        
        browserViewController.loadViewIfNeeded()
        browserViewController.tabManager.browse(to: bookmark.url.absoluteString)
        
        if navigationController?.presentingViewController is BrowserViewController {
            navigationController?.dismiss(animated: true)
        }
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let preserveFocusOnClear = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchBar.isFirstResponder
        searchBookmarks(term: searchText, preserveFocusOnClear: preserveFocusOnClear)
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
