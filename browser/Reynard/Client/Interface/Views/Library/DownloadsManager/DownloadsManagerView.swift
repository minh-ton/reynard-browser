//
//  DownloadsManagerView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

final class DownloadsManagerView: UIView, UITableViewDataSource, UITableViewDelegate {
    private struct Section {
        let title: String
        let items: [DownloadItemSnapshot]
    }
    
    private struct SectionSignature: Equatable {
        let title: String
        let itemIDs: [UUID]
    }
    
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .plain)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGroupedBackground
        view.dataSource = self
        view.delegate = self
        view.rowHeight = UITableView.automaticDimension
        view.estimatedRowHeight = 96
        view.separatorStyle = .singleLine
        view.separatorInset = .zero
        view.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 1 / UIScreen.main.scale))
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = 0
        }
        view.register(DownloadItemCell.self, forCellReuseIdentifier: DownloadItemCell.reuseIdentifier)
        return view
    }()
    
    private let emptyStateView = EmptyDownloadsBackgroundView()
    
    private var sections: [Section] = []
    private var notificationToken: NSObjectProtocol?
    private var isShowingSwipeActions = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGroupedBackground
        addSubview(tableView)
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        tableView.backgroundView?.frame = tableView.bounds
    }
    
    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }
    
    private func reloadDownloads() {
        let updatedSections = makeSections(from: DownloadStore.shared.snapshot().items)
        let previousSections = sections
        let shouldReloadTable = sectionSignatures(for: previousSections) != sectionSignatures(for: updatedSections)
        
        sections = updatedSections
        tableView.backgroundView = sections.isEmpty ? emptyStateView : nil
        updateSeparatorVisibility()
        
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
            
            let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard item.state == .completed else {
            return
        }
        
        presentShareSheet(for: item, from: indexPath)
    }
    
    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isShowingSwipeActions = true
    }
    
    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isShowingSwipeActions = false
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
    
    private var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first { $0 is UIViewController } as? UIViewController
    }
    
    private func updateSeparatorVisibility() {
        let shouldHideSeparators = sections.isEmpty
        tableView.separatorStyle = shouldHideSeparators ? .none : .singleLine
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

private final class EmptyDownloadsBackgroundView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Downloads will appear here."
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = max(bounds.width - 48, 0)
        let fittingSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = label.sizeThatFits(fittingSize)
        label.frame = CGRect(
            x: (bounds.width - min(labelSize.width, maxWidth)) / 2,
            y: (bounds.height - labelSize.height) / 2,
            width: min(labelSize.width, maxWidth),
            height: labelSize.height
        ).integral
    }
}
