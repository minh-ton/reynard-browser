//
//  DownloadsManagerView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class DownloadsManagerView: UIView, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate {
    private struct Section {
        let title: String
        let items: [DownloadItemSnapshot]
    }
    
    private struct SectionSignature: Equatable {
        let title: String
        let itemIDs: [UUID]
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
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var downloadsActionsButton = MakeButtons.makeLibraryActionsButton(
        target: self,
        imageName: "ellipsis",
        action: #selector(downloadsActionsButtonTapped)
    )
    private var legacyDownloadsActionsMenuDelegate: LegacyDownloadsActionsMenuDelegate?
    private lazy var downloadsActionsBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(downloadsActionsButtonTapped)
        )
        item.tag = MakeButtons.downloadsLibraryActionBarButtonTag
        return item
    }()
    private var usesNavigationActionsButton: Bool {
        if #available(iOS 26.0, *) {
            return MakeButtons.hasLiquidGlass
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
        view.estimatedRowHeight = 96
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = 0
        }
        view.register(DownloadItemCell.self, forCellReuseIdentifier: DownloadItemCell.reuseIdentifier)
        return view
    }()
    
    private let emptyStateView = LibraryEmptyBackgroundView(message: "Files you download appear here")
    private var sections: [Section] = []
    private var notificationToken: NSObjectProtocol?
    private var applicationActiveToken: NSObjectProtocol?
    private var isShowingSwipeActions = false
    private var currentSearchTerm = ""
    private var hasStoredDownloads = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGroupedBackground
        addSubview(tableView)
        setupHeaderView()
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDownloads()
        }
        applicationActiveToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDownloads()
        }
        
        reloadDownloads()
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        tableView.addGestureRecognizer(tapGesture)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateHeaderSizeIfNeeded()
        tableView.backgroundView?.frame = tableView.bounds
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if window != nil {
            installNavigationActionsButtonIfNeeded()
            reloadDownloads()
        }
    }
    
    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        if let applicationActiveToken {
            NotificationCenter.default.removeObserver(applicationActiveToken)
        }
    }
    
    private func reloadDownloads() {
        let snapshot = DownloadStore.shared.snapshot()
        hasStoredDownloads = !snapshot.items.isEmpty
        updateSearchBarVisibility()
        
        let updatedSections = makeSections(from: filteredItems(from: snapshot.items))
        let previousSections = sections
        let shouldReloadTable = sectionSignatures(for: previousSections) != sectionSignatures(for: updatedSections)
        
        sections = updatedSections
        updateBackgroundView()
        
        if isShowingSwipeActions {
            if shouldReloadTable {
                isShowingSwipeActions = false
                tableView.setEditing(false, animated: false)
                tableView.reloadData()
            } else {
                refreshVisibleCells(previousSections: previousSections)
            }
            return
        }
        
        if shouldReloadTable {
            tableView.reloadData()
            return
        }
        
        refreshVisibleCells(previousSections: previousSections)
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
            headerContainerView.addSubview(downloadsActionsButton)
            downloadsActionsButton.translatesAutoresizingMaskIntoConstraints = false
            
            if #available(iOS 14.0, *) {
                downloadsActionsButton.menu = makeDownloadsActionsMenu()
                downloadsActionsButton.showsMenuAsPrimaryAction = true
            } else if #available(iOS 13.0, *) {
                let delegate = LegacyDownloadsActionsMenuDelegate(owner: self)
                downloadsActionsButton.addInteraction(UIContextMenuInteraction(delegate: delegate))
                legacyDownloadsActionsMenuDelegate = delegate
            }
            
            constraints.append(contentsOf: [
                searchBar.trailingAnchor.constraint(equalTo: downloadsActionsButton.leadingAnchor),
                downloadsActionsButton.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor, constant: -20),
                downloadsActionsButton.centerYAnchor.constraint(equalTo: searchBar.searchTextField.centerYAnchor),
                downloadsActionsButton.widthAnchor.constraint(equalTo: downloadsActionsButton.heightAnchor),
                downloadsActionsButton.heightAnchor.constraint(equalTo: searchBar.searchTextField.heightAnchor),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        let targetWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        headerContainerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        updateHeaderFittingHeight()
    }
    
    private func updateSearchBarVisibility() {
        if hasStoredDownloads {
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
    
    @objc private func downloadsActionsButtonTapped() {
        if #available(iOS 13.0, *) {
            if #unavailable(iOS 14.0) {
                presentLegacyDownloadsActionsMenu()
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func presentLegacyDownloadsActionsMenu() {
        guard let interaction = downloadsActionsButton.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }
        
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }
        
        let center = NSValue(cgPoint: CGPoint(x: downloadsActionsButton.bounds.midX, y: downloadsActionsButton.bounds.midY))
        _ = interaction.perform(selector, with: center)
    }
    
    fileprivate func makeDownloadsActionsMenu() -> UIMenu {
        UIMenu(title: "", children: [
            UIAction(title: "Open Downloads Folder", image: UIImage(systemName: "folder")) { [weak self] _ in
                self?.openDownloadsFolder()
            },
            UIAction(title: "Clear Downloads History", image: UIImage(named: "arrow.down.circle.badge.xmark")) { [weak self] _ in
                self?.presentClearDownloadsHistory()
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
    
    private func presentClearDownloadsHistory() {
        guard let viewController = nearestViewController else {
            return
        }
        
        let clearViewController = ClearDownloadsViewController { startDate in
            DownloadStore.shared.clearDownloadHistory(since: startDate)
        }
        let navigationController = UINavigationController(rootViewController: clearViewController)
        navigationController.modalPresentationStyle = .pageSheet
        viewController.present(navigationController, animated: true)
    }
    
    private func installNavigationActionsButtonIfNeeded() {
        guard usesNavigationActionsButton,
              let navigationItem = nearestViewController?.navigationController?.topViewController?.navigationItem else {
            return
        }
        
        downloadsActionsBarButtonItem.tintColor = .label
        if #available(iOS 14.0, *) {
            downloadsActionsBarButtonItem.menu = makeDownloadsActionsMenu()
            downloadsActionsBarButtonItem.target = nil
            downloadsActionsBarButtonItem.action = nil
        }
        MakeButtons.installLibraryActionBarButton(downloadsActionsBarButtonItem, in: navigationItem)
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
    
    private func filteredItems(from items: [DownloadItemSnapshot]) -> [DownloadItemSnapshot] {
        let normalizedTerm = currentSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else {
            return items
        }
        
        return items.filter { $0.fileName.localizedCaseInsensitiveContains(normalizedTerm) }
    }
    
    private func performSearch(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedTerm.isEmpty {
            currentSearchTerm = ""
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
        
        currentSearchTerm = normalizedTerm
        reloadDownloads()
    }
    
    private func updateBackgroundView() {
        emptyStateView.message = currentSearchTerm.isEmpty ? "Files you download appear here" : "No matching downloads"
        tableView.backgroundView = sections.isEmpty ? emptyStateView : nil
        emptyStateView.updateContentInsets(from: tableView)
    }
    
    private func refreshVisibleCells(previousSections: [Section]) {
        let visibleIndexPaths = changedVisibleIndexPaths(previousSections: previousSections)
        guard !visibleIndexPaths.isEmpty else {
            return
        }
        
        for indexPath in visibleIndexPaths {
            guard let item = item(at: indexPath),
                  let cell = tableView.cellForRow(at: indexPath) as? DownloadItemCell else {
                continue
            }
            
            cell.apply(item: item)
        }
    }
    
    private func changedVisibleIndexPaths(previousSections: [Section]) -> [IndexPath] {
        (tableView.indexPathsForVisibleRows ?? []).filter { indexPath in
            guard let previousItem = item(at: indexPath, in: previousSections),
                  let currentItem = item(at: indexPath, in: sections) else {
                return false
            }
            
            return !itemsAreDisplayEquivalent(previousItem, currentItem)
        }
    }
    
    private func makeSections(from items: [DownloadItemSnapshot]) -> [Section] {
        guard !items.isEmpty else {
            return []
        }
        
        var todayItems: [DownloadItemSnapshot] = []
        var yesterdayItems: [DownloadItemSnapshot] = []
        var previousSevenDayItems: [DownloadItemSnapshot] = []
        var previousThirtyDayItems: [DownloadItemSnapshot] = []
        var monthlyItems: [DateComponents: [DownloadItemSnapshot]] = [:]
        let calendar = Calendar.current
        let now = Date()
        let monthFormatter = monthTitleFormatter
        let monthYearFormatter = monthYearTitleFormatter
        
        for item in items {
            let startOfItemDay = calendar.startOfDay(for: item.addedAt)
            let startOfToday = calendar.startOfDay(for: now)
            let dayDifference = calendar.dateComponents([.day], from: startOfItemDay, to: startOfToday).day ?? 0
            
            switch dayDifference {
            case Int.min..<1:
                todayItems.append(item)
            case 1:
                yesterdayItems.append(item)
            case 2...7:
                previousSevenDayItems.append(item)
            case 8...30:
                previousThirtyDayItems.append(item)
            default:
                let components = calendar.dateComponents([.year, .month], from: item.addedAt)
                monthlyItems[components, default: []].append(item)
            }
        }
        
        var resolvedSections: [Section] = []
        if !todayItems.isEmpty {
            resolvedSections.append(Section(title: "Today", items: todayItems))
        }
        if !yesterdayItems.isEmpty {
            resolvedSections.append(Section(title: "Yesterday", items: yesterdayItems))
        }
        if !previousSevenDayItems.isEmpty {
            resolvedSections.append(Section(title: "Previous 7 Days", items: previousSevenDayItems))
        }
        if !previousThirtyDayItems.isEmpty {
            resolvedSections.append(Section(title: "Previous 30 Days", items: previousThirtyDayItems))
        }
        
        let currentYear = calendar.component(.year, from: now)
        let sortedMonthComponents = monthlyItems.keys.sorted { lhs, rhs in
            let leftYear = lhs.year ?? 0
            let rightYear = rhs.year ?? 0
            if leftYear != rightYear {
                return leftYear > rightYear
            }
            
            return (lhs.month ?? 0) > (rhs.month ?? 0)
        }
        
        for components in sortedMonthComponents {
            guard let year = components.year,
                  let month = components.month,
                  let items = monthlyItems[components],
                  let titleDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
                continue
            }
            
            let title = year == currentYear ? monthFormatter.string(from: titleDate) : monthYearFormatter.string(from: titleDate)
            resolvedSections.append(Section(title: title, items: items))
        }
        
        return resolvedSections
    }
    
    private func sectionSignatures(for sections: [Section]) -> [SectionSignature] {
        sections.map { section in
            SectionSignature(title: section.title, itemIDs: section.items.map(\.id))
        }
    }
    
    private func item(at indexPath: IndexPath, in sections: [Section]? = nil) -> DownloadItemSnapshot? {
        let resolvedSections = sections ?? self.sections
        guard indexPath.section < resolvedSections.count,
              indexPath.row < resolvedSections[indexPath.section].items.count else {
            return nil
        }
        
        return resolvedSections[indexPath.section].items[indexPath.row]
    }
    
    private func itemsAreDisplayEquivalent(_ lhs: DownloadItemSnapshot, _ rhs: DownloadItemSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.fileName == rhs.fileName &&
        lhs.fileURL == rhs.fileURL &&
        lhs.state == rhs.state &&
        lhs.fileExists == rhs.fileExists &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.downloadedBytes == rhs.downloadedBytes &&
        lhs.bytesPerSecond == rhs.bytesPerSecond
    }
    
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
        
        cell.apply(item: item)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
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
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = item(at: indexPath) else {
            return nil
        }
        
        switch item.state {
        case .downloading:
            let cancelAction = UIContextualAction(style: .destructive, title: "Cancel") { [weak self] _, _, completion in
                self?.presentCancellationConfirmation(for: item, completion: completion)
            }
            let configuration = UISwipeActionsConfiguration(actions: [cancelAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
            
        case .completed:
            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                DownloadStore.shared.deleteDownloadedItem(id: item.id)
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
                
                self.presentShareSheet(for: item, from: indexPath)
                completion(true)
            }
            shareAction.backgroundColor = .systemGreen
            
            let openAction = UIContextualAction(style: .normal, title: "Open in\nFiles") { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                
                self.openDownloadedFile(item)
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
        
        self.presentShareSheet(for: item, from: indexPath)
    }
    
    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isShowingSwipeActions = true
    }
    
    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isShowingSwipeActions = false
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
    
    private func presentCancellationConfirmation(
        for item: DownloadItemSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        guard let viewController = nearestViewController else {
            DownloadStore.shared.cancelDownload(id: item.id)
            completion(true)
            return
        }
        
        let alert = UIAlertController(
            title: "Cancel Download?",
            message: "Do you want to stop downloading \(item.fileName)?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep Downloading", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Cancel Download", style: .destructive) { _ in
            DownloadStore.shared.cancelDownload(id: item.id)
            completion(true)
        })
        viewController.present(alert, animated: true)
    }
    
    private func presentShareSheet(for item: DownloadItemSnapshot, from indexPath: IndexPath) {
        guard let fileURL = item.fileURL,
              let viewController = nearestViewController else {
            return
        }
        
        let sheet = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        viewController.present(sheet, animated: true)
    }
    
    private func openDownloadedFile(_ item: DownloadItemSnapshot) {
        guard let fileURL = item.fileURL else {
            return
        }
        
        let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let filesURL = URL(string: "shareddocuments://\(encodedPath)") else {
            return
        }
        
        UIApplication.shared.open(filesURL, options: [:], completionHandler: nil)
    }
    
    private var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first { $0 is UIViewController } as? UIViewController
    }
}

private final class LegacyDownloadsActionsMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var owner: DownloadsManagerView?
    
    init(owner: DownloadsManagerView) {
        self.owner = owner
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let owner else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            owner.makeDownloadsActionsMenu()
        }
    }
}

private let monthTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMM")
    return formatter
}()

private let monthYearTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return formatter
}()

