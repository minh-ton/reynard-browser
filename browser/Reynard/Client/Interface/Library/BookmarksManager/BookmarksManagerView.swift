//
//  BookmarksManagerView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

enum BookmarkSortOrder: String {
    case none
    case date_added
    case name
    case address
}

final class BookmarksManagerView: UIView {
    private weak var hostedViewController: BookmarksFolderViewController?
    
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
        
        let bookmarksViewController = BookmarksFolderViewController(parentFolderGUID: nil)
        bookmarksViewController.view.translatesAutoresizingMaskIntoConstraints = false
        bookmarksViewController.view.backgroundColor = .clear
        
        parentViewController.addChild(bookmarksViewController)
        addSubview(bookmarksViewController.view)
        
        NSLayoutConstraint.activate([
            bookmarksViewController.view.topAnchor.constraint(equalTo: topAnchor),
            bookmarksViewController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            bookmarksViewController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            bookmarksViewController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        bookmarksViewController.didMove(toParent: parentViewController)
        hostedViewController = bookmarksViewController
    }
}

private final class BookmarksFolderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private static let searchResultLimit = 50
    
    private let parentFolderGUID: String?
    private let store: BookmarkStore
    private var sections: [(title: String, items: [BookmarkContentSnapshot])] = []
    private var currentSearchTerm = ""
    private var requestGeneration = 0
    private var isRootFolder: Bool {
        parentFolderGUID == nil
    }
    private lazy var newFolderButtonItem = UIBarButtonItem(
        title: "New Folder",
        style: .plain,
        target: self,
        action: #selector(promptForNewFolder)
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
    private lazy var searchActionsButton = MakeButtons.makeLibraryActionsButton(
        target: self,
        imageName: "ellipsis",
        action: #selector(searchActionsButtonTapped)
    )
    private var legacySearchActionsMenuDelegate: LegacySearchActionsMenuDelegate?
    private lazy var bookmarksActionsBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(searchActionsButtonTapped)
        )
        item.tag = MakeButtons.bookmarksLibraryActionBarButtonTag
        return item
    }()
    private let usesNavigationActionsButton: Bool
    private let headerContainerView: UIView = {
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
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No matching bookmarks"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    init(parentFolderGUID: String?, store: BookmarkStore = .shared) {
        self.parentFolderGUID = parentFolderGUID
        self.store = store
        if #available(iOS 26.0, *) {
            usesNavigationActionsButton = parentFolderGUID == nil && MakeButtons.hasLiquidGlass
        } else {
            usesNavigationActionsButton = false
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
        configureLayout()
        
        tableView.register(BookmarkItemCell.self, forCellReuseIdentifier: BookmarkItemCell.reuseIdentifier)
        
        if isRootFolder {
            setupHeaderView()
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            tableView.addGestureRecognizer(tapGesture)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookmarkStoreDidChange),
            name: .bookmarkStoreDidChange,
            object: nil
        )
        
        reloadContents()
        updateToolbarItems(animated: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderSizeIfNeeded()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(isRootFolder, animated: animated)
        installNavigationActionsButtonIfNeeded()
        reloadContents()
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
        updateSearchActionsButton()
    }
    
    private func configureLayout() {
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
            cell.apply(folder: folder)
            cell.accessoryType = .disclosureIndicator
            return cell
        case let .bookmark(bookmark):
            cell.apply(bookmark: bookmark)
            cell.accessoryType = .none
            return cell
        }
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
        guard currentSearchTerm.isEmpty,
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
            reloadContents()
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
        
        let didMove = store.moveItem(
            guid: movedGUID,
            toIndex: sections[..<destinationIndexPath.section].reduce(0) { $0 + $1.items.count } + destinationIndexPath.row,
            inFolderWithGUID: parentFolderGUID
        )
        
        if !didMove {
            reloadContents()
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
            didDelete = store.deleteBookmark(guid: bookmark.guid)
        case let .folder(folder):
            guard !folder.isProtected else {
                return false
            }
            didDelete = store.deleteFolder(guid: folder.guid)
        }
        
        reloadContents()
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
            let viewController = BookmarksFolderViewController(parentFolderGUID: folder.guid, store: store)
            navigationController?.pushViewController(viewController, animated: true)
        case let .bookmark(bookmark):
            openBookmark(bookmark)
        }
    }
    
    @objc private func handleBookmarkStoreDidChange() {
        reloadContents()
    }
    
    @objc private func handleBackgroundTap() {
        searchBar.resignFirstResponder()
    }
    
    @objc private func promptForNewFolder() {
        let viewController = NewBookmarkFolderViewController(selectedParentFolderGUID: parentFolderGUID, store: store)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    @objc private func searchActionsButtonTapped() {
        if isEditing {
            setEditing(false, animated: true)
            return
        }
        
        if #available(iOS 13.0, *) {
            if #unavailable(iOS 14.0) {
                presentLegacySearchActionsMenu()
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func presentLegacySearchActionsMenu() {
        guard let interaction = searchActionsButton.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }
        
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }
        
        let center = NSValue(cgPoint: CGPoint(x: searchActionsButton.bounds.midX, y: searchActionsButton.bounds.midY))
        _ = interaction.perform(selector, with: center)
    }
    
    private func updateSearchActionsButton() {
        let symbolName = isEditing ? "checkmark" : "ellipsis"
        
        if usesNavigationActionsButton {
            bookmarksActionsBarButtonItem.image = UIImage(systemName: symbolName)
            bookmarksActionsBarButtonItem.tintColor = .label
            
            if #available(iOS 14.0, *) {
                bookmarksActionsBarButtonItem.menu = isEditing ? nil : makeSearchActionsMenu()
                bookmarksActionsBarButtonItem.target = isEditing ? self : nil
                bookmarksActionsBarButtonItem.action = isEditing ? #selector(searchActionsButtonTapped) : nil
            }
            
            return
        }
        
        MakeButtons.updateLibraryActionsButton(searchActionsButton, imageName: symbolName)
        
        if #available(iOS 14.0, *) {
            searchActionsButton.menu = isEditing ? nil : makeSearchActionsMenu()
            searchActionsButton.showsMenuAsPrimaryAction = !isEditing
        }
    }
    
    fileprivate func makeSearchActionsMenu() -> UIMenu {
        UIMenu(title: "", children: [
            makeSortMenu(),
            UIAction(
                title: "Show Folders on Top",
                image: UIImage(named: "text.below.folder"),
                state: Prefs.BookmarkSettings.placeFoldersOnTop ? .on : .off
            ) { [weak self] _ in
                Prefs.BookmarkSettings.placeFoldersOnTop.toggle()
                self?.reloadContents()
                self?.updateSearchActionsButton()
            },
            UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [
                UIAction(title: "Edit Bookmarks", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    self?.setEditing(true, animated: true)
                },
                UIAction(title: "New Folder", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                    self?.promptForNewFolder()
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
            image: UIImage(systemName: "arrow.up.arrow.down"),
            identifier: nil,
            options: [],
            children: sortOptions.map {
                let order = $0.order
                return UIAction(title: $0.title, state: order == selectedOrder ? .on : .off) { [weak self] _ in
                    Prefs.BookmarkSettings.sortOrders = order
                    self?.reloadContents()
                    self?.updateSearchActionsButton()
                }
            }
        )
        
        if #available(iOS 15.0, *) {
            menu.subtitle = sortOptions.first { $0.order == selectedOrder }?.title
        }
        
        return menu
    }
    
    private func installNavigationActionsButtonIfNeeded() {
        guard usesNavigationActionsButton,
              let navigationItem = navigationController?.topViewController?.navigationItem else {
            return
        }
        
        updateSearchActionsButton()
        MakeButtons.installLibraryActionBarButton(bookmarksActionsBarButtonItem, in: navigationItem)
    }
    
    private func reloadContents() {
        if !currentSearchTerm.isEmpty {
            performSearch(term: currentSearchTerm)
            return
        }
        
        reloadFolderContents()
    }
    
    private func reloadFolderContents() {
        let snapshot = store.folderContents(parentGUID: parentFolderGUID)
        sections = makeSections(from: snapshot.items)
        title = snapshot.parent.title
        updateBackgroundView()
        tableView.reloadData()
    }
    
    private func updateBackgroundView() {
        tableView.backgroundView = sections.isEmpty && !currentSearchTerm.isEmpty ? emptyStateLabel : nil
    }
    
    private func makeSections(from newItems: [BookmarkContentSnapshot]) -> [(title: String, items: [BookmarkContentSnapshot])] {
        guard Prefs.BookmarkSettings.placeFoldersOnTop else {
            let sortedItems = sorted(newItems)
            return sortedItems.isEmpty ? [] : [("Bookmarks", sortedItems)]
        }
        
        let folders = sorted(newItems.filter {
            if case .folder = $0 {
                return true
            }
            
            return false
        })
        let bookmarks = sorted(newItems.filter {
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
    
    private func sorted(_ newItems: [BookmarkContentSnapshot]) -> [BookmarkContentSnapshot] {
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
    
    private func setupHeaderView() {
        headerContainerView.layoutMargins = tableView.layoutMargins
        headerContainerView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [
            searchBar.topAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.leadingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
        ]
        
        if usesNavigationActionsButton {
            constraints.append(searchBar.trailingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.trailingAnchor))
        } else {
            headerContainerView.addSubview(searchActionsButton)
            searchActionsButton.translatesAutoresizingMaskIntoConstraints = false
            if #available(iOS 13.0, *) {
                if #unavailable(iOS 14.0) {
                    let delegate = LegacySearchActionsMenuDelegate(owner: self)
                    searchActionsButton.addInteraction(UIContextMenuInteraction(delegate: delegate))
                    legacySearchActionsMenuDelegate = delegate
                }
            }
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: searchActionsButton.leadingAnchor),
                searchActionsButton.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor, constant: -20),
                searchActionsButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                searchActionsButton.widthAnchor.constraint(equalTo: searchActionsButton.heightAnchor),
                searchActionsButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        updateSearchActionsButton()
        
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerContainerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        updateHeaderFittingHeight()
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
        guard parentFolderGUID == nil else {
            return
        }
        
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else {
            return
        }
        
        var frame = headerContainerView.frame
        guard frame.width != targetWidth else {
            return
        }
        
        frame.size.width = targetWidth
        headerContainerView.frame = frame
        updateHeaderFittingHeight()
    }
    
    private func performSearch(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            currentSearchTerm = ""
            requestGeneration += 1
            reloadFolderContents()
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
        requestGeneration += 1
        let generation = requestGeneration
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let searchResults = self.store.searchBookmarks(matching: normalizedTerm, limit: Self.searchResultLimit)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                
                guard self.requestGeneration == generation, self.currentSearchTerm == normalizedTerm else {
                    return
                }
                
                self.sections = self.makeSections(from: searchResults.map { .bookmark($0) })
                self.updateBackgroundView()
                self.tableView.reloadData()
            }
        }
    }
    
    private func updateToolbarItems(animated: Bool) {
        guard !isRootFolder else {
            return
        }
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let items: [UIBarButtonItem]
        if isEditing {
            items = [newFolderButtonItem, flexibleSpace, editButtonItem]
        } else {
            items = [flexibleSpace, editButtonItem]
        }
        setToolbarItems(items, animated: animated)
    }
    
    private func openBookmark(_ bookmark: BookmarkSnapshot) {
        guard let browserViewController = resolvedBrowserViewController() else {
            return
        }
        
        browserViewController.loadViewIfNeeded()
        browserViewController.browse(to: bookmark.url.absoluteString)
        
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
        
        return nil
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

private final class LegacySearchActionsMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var owner: BookmarksFolderViewController?
    
    init(owner: BookmarksFolderViewController) {
        self.owner = owner
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let owner,
              !owner.isEditing else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            owner.makeSearchActionsMenu()
        }
    }
}

private extension UIView {
    var containingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
}
