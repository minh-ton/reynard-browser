//
//  DownloadsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private enum UX {
        static let estimatedRowHeight: CGFloat = 96
        static let sectionHeaderTopPadding: CGFloat = 0
        static let groupedSectionHeaderHeight: CGFloat = 34
        static let headerMenuButtonTrailingInset: CGFloat = 20
    }
    
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search Downloads"
        searchBar.delegate = self
        return searchBar
    }()
    
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var downloadsMenuButton = LibraryActionButton(
        target: self,
        iconName: "reynard.ellipsis",
        action: #selector(didTapDownloadsMenu)
    )
    private var legacyDownloadsMenuDelegate: LibraryLegacyMenuDelegate?
    private lazy var downloadsMenuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(named: "reynard.ellipsis"),
            style: .plain,
            target: self,
            action: #selector(didTapDownloadsMenu)
        )
        item.tag = LibraryActionButton.downloadsNavigationActionTag
        return item
    }()
    private var showsNavigationMenu: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        
        return false
    }
    
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGroupedBackground
        view.dataSource = self
        view.delegate = self
        view.rowHeight = UITableView.automaticDimension
        view.estimatedRowHeight = UX.estimatedRowHeight
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = UX.sectionHeaderTopPadding
        }
        view.register(DownloadItemCell.self, forCellReuseIdentifier: DownloadItemCell.reuseIdentifier)
        return view
    }()
    
    private let emptyStateView = SidebarEmptyBackgroundView(message: "Files you download appear here")
    private var sections: [DownloadSection] = []
    private var storeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var isSwipeEditing = false
    private var query = ""
    
    // MARK: - Lifecycle
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        installLayout()
        installHeader()
        observeStore()
        installGestures()
        reloadDownloads()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        LibrarySharedUtils.syncTableHeaderWidth(headerView, in: tableView)
        tableView.backgroundView?.frame = tableView.bounds
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installDownloadsNavigationMenuIfNeeded()
        reloadDownloads()
    }
    
    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }
    
    // MARK: - View Setup
    
    private func installLayout() {
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func observeStore() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDownloads()
        }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDownloads()
        }
    }
    
    private func installGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSearch))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        tableView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Downloads
    
    private func reloadDownloads() {
        let snapshot = DownloadStore.shared.currentSnapshot()
        updateSearchHeaderVisibility(containsDownloads: !snapshot.items.isEmpty)
        
        let updatedSections = DownloadSection.make(from: matchingDownloads(from: snapshot.items))
        let previousSections = sections
        let shouldReloadTable = sectionFingerprints(for: previousSections) != sectionFingerprints(for: updatedSections)
        
        sections = updatedSections
        updateEmptyState()
        
        if isSwipeEditing {
            if shouldReloadTable {
                isSwipeEditing = false
                tableView.setEditing(false, animated: false)
                tableView.reloadData()
            } else {
                updateChangedVisibleCells(previousSections: previousSections)
            }
            return
        }
        
        if shouldReloadTable {
            tableView.reloadData()
            return
        }
        
        updateChangedVisibleCells(previousSections: previousSections)
    }
    
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
            headerView.addSubview(downloadsMenuButton)
            downloadsMenuButton.translatesAutoresizingMaskIntoConstraints = false
            
            if #available(iOS 14.0, *) {
                downloadsMenuButton.menu = makeDownloadsMenu()
                downloadsMenuButton.showsMenuAsPrimaryAction = true
            } else if #available(iOS 13.0, *) {
                let delegate = LibraryLegacyMenuDelegate { [weak self] in
                    self?.makeDownloadsMenu()
                }
                downloadsMenuButton.addInteraction(UIContextMenuInteraction(delegate: delegate))
                legacyDownloadsMenuDelegate = delegate
            }
            
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: downloadsMenuButton.leadingAnchor),
                downloadsMenuButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -UX.headerMenuButtonTrailingInset),
                downloadsMenuButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                downloadsMenuButton.widthAnchor.constraint(equalTo: downloadsMenuButton.heightAnchor),
                downloadsMenuButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        LibrarySharedUtils.updateTableHeaderHeight(headerView, in: tableView)
    }
    
    private func updateSearchHeaderVisibility(containsDownloads: Bool) {
        if containsDownloads {
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
    
    // MARK: - Menu
    
    @objc private func didTapDownloadsMenu() {
        if #available(iOS 13.0, *) {
            if #unavailable(iOS 14.0) {
                LibrarySharedUtils.presentLegacyContextMenu(from: downloadsMenuButton)
            }
        }
    }
    
    fileprivate func makeDownloadsMenu() -> UIMenu {
        UIMenu(title: "", children: [
            UIAction(title: "Open Downloads Folder", image: UIImage(named: "reynard.folder")) { [weak self] _ in
                self?.openDownloadsFolder()
            },
            UIAction(title: "Clear Downloads History", image: UIImage(named: "reynard.arrow.down.circle.badge.xmark")) { [weak self] _ in
                self?.showClearDownloads()
            },
        ])
    }
    
    private func openDownloadsFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        let encodedPath = downloadsURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let filesURL = URL(string: "shareddocuments://\(encodedPath)") else {
            return
        }
        
        UIApplication.shared.open(filesURL, options: [:], completionHandler: nil)
    }
    
    private func showClearDownloads() {
        let clearViewController = ClearDownloadsViewController { startDate in
            DownloadStore.shared.clearCompletedDownloads(since: startDate)
        }
        let navigationController = UINavigationController(rootViewController: clearViewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
    
    private func installDownloadsNavigationMenuIfNeeded() {
        guard showsNavigationMenu,
              let navigationItem = navigationController?.topViewController?.navigationItem else {
            return
        }
        
        downloadsMenuItem.tintColor = .label
        if #available(iOS 14.0, *) {
            downloadsMenuItem.menu = makeDownloadsMenu()
            downloadsMenuItem.target = nil
            downloadsMenuItem.action = nil
        }
        LibraryActionButton.installNavigationAction(downloadsMenuItem, in: navigationItem)
    }
    
    // MARK: - Search
    
    private func matchingDownloads(from items: [DownloadItemSnapshot]) -> [DownloadItemSnapshot] {
        let normalizedTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else {
            return items
        }
        
        return items.filter { $0.fileName.localizedCaseInsensitiveContains(normalizedTerm) }
    }
    
    private func searchDownloads(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            query = ""
            reloadDownloads()
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
        reloadDownloads()
    }
    
    // MARK: - Display State
    
    private func updateEmptyState() {
        emptyStateView.message = query.isEmpty ? "Files you download appear here" : "No matching downloads"
        tableView.backgroundView = sections.isEmpty ? emptyStateView : nil
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    private func updateChangedVisibleCells(previousSections: [DownloadSection]) {
        let visibleIndexPaths = changedVisibleIndexPaths(previousSections: previousSections)
        guard !visibleIndexPaths.isEmpty else {
            return
        }
        
        for indexPath in visibleIndexPaths {
            guard let item = item(at: indexPath),
                  let cell = tableView.cellForRow(at: indexPath) as? DownloadItemCell else {
                continue
            }
            
            cell.configure(with: item)
        }
    }
    
    private func changedVisibleIndexPaths(previousSections: [DownloadSection]) -> [IndexPath] {
        (tableView.indexPathsForVisibleRows ?? []).filter { indexPath in
            guard let previousItem = item(at: indexPath, in: previousSections),
                  let currentItem = item(at: indexPath, in: sections) else {
                return false
            }
            
            return !hasSameVisibleState(previousItem, currentItem)
        }
    }
    
    private func sectionFingerprints(for sections: [DownloadSection]) -> [DownloadSectionFingerprint] {
        sections.map { section in
            DownloadSectionFingerprint(title: section.title, itemIDs: section.items.map(\.id))
        }
    }
    
    private func item(at indexPath: IndexPath, in sections: [DownloadSection]? = nil) -> DownloadItemSnapshot? {
        let resolvedSections = sections ?? self.sections
        guard indexPath.section < resolvedSections.count,
              indexPath.row < resolvedSections[indexPath.section].items.count else {
            return nil
        }
        
        return resolvedSections[indexPath.section].items[indexPath.row]
    }
    
    private func hasSameVisibleState(_ lhs: DownloadItemSnapshot, _ rhs: DownloadItemSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.fileName == rhs.fileName &&
        lhs.fileURL == rhs.fileURL &&
        lhs.state == rhs.state &&
        lhs.fileExists == rhs.fileExists &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.downloadedBytes == rhs.downloadedBytes &&
        lhs.bytesPerSecond == rhs.bytesPerSecond
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: DownloadItemCell.reuseIdentifier,
            for: indexPath
        ) as? DownloadItemCell,
              let item = item(at: indexPath) else {
            return UITableViewCell()
        }
        
        cell.configure(with: item)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        LibrarySharedUtils.makeGroupedSectionHeader(title: sections[section].title)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UX.groupedSectionHeaderHeight
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = item(at: indexPath) else {
            return nil
        }
        
        switch item.state {
        case .downloading:
            let cancelAction = UIContextualAction(style: .destructive, title: "Cancel") { [weak self] _, _, completion in
                self?.confirmCancelDownload(for: item, completion: completion)
            }
            let configuration = UISwipeActionsConfiguration(actions: [cancelAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
            
        case .completed:
            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                DownloadStore.shared.removeDownload(id: item.id)
                completion(true)
            }
            
            guard item.fileExists else {
                let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
                configuration.performsFirstActionWithFullSwipe = true
                return configuration
            }
            
            let shareAction = UIContextualAction(style: .normal, title: "Share") { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                
                self.shareDownload(item, from: indexPath)
                completion(true)
            }
            shareAction.backgroundColor = .systemGreen
            
            let openAction = UIContextualAction(style: .normal, title: "Open in\nFiles") { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                
                self.revealInFiles(item)
                completion(true)
            }
            openAction.backgroundColor = .systemBlue
            
            let configuration = UISwipeActionsConfiguration(actions: [deleteAction, shareAction, openAction])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard item.state == .completed, item.fileExists else {
            return
        }
        
        self.shareDownload(item, from: indexPath)
    }
    
    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isSwipeEditing = true
    }
    
    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isSwipeEditing = false
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let preserveFocusOnClear = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchBar.isFirstResponder
        searchDownloads(term: searchText, preserveFocusOnClear: preserveFocusOnClear)
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
    
    // MARK: - Item Actions
    
    private func confirmCancelDownload(
        for item: DownloadItemSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        AlertPresenter.show(
            title: "Cancel Download?",
            message: "Do you want to stop downloading \(item.fileName)?",
            buttons: [
                AlertPresenter.Button(title: "Keep Downloading", style: .cancel) {
                    completion(false)
                },
                AlertPresenter.Button(title: "Cancel Download", style: .destructive) {
                    DownloadStore.shared.cancel(id: item.id)
                    completion(true)
                },
            ]
        )
    }
    
    private func shareDownload(_ item: DownloadItemSnapshot, from indexPath: IndexPath) {
        guard let fileURL = item.fileURL else {
            return
        }
        
        let sheet = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }
    
    private func revealInFiles(_ item: DownloadItemSnapshot) {
        guard let fileURL = item.fileURL else {
            return
        }
        
        let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let filesURL = URL(string: "shareddocuments://\(encodedPath)") else {
            return
        }
        
        UIApplication.shared.open(filesURL, options: [:], completionHandler: nil)
    }
}
