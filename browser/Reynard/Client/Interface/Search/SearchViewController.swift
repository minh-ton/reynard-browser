//
//  SearchViewController.swift
//  Reynard
//
//  Created by Minh Ton on 1/6/26.
//

import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, result: UserDataSearchResult?)
    func searchViewController(_ controller: SearchViewController, didUpdateAutocompleteFor query: String, result: UserDataSearchResult?, topDomain: String?)
    func searchViewControllerDidStartScrolling(_ controller: SearchViewController)
}

final class SearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum UX {
        static let limitedCompletionCountWithUserData = 4
        static let tableInset: CGFloat = 8
        static let estimatedRowHeight: CGFloat = 60
        static let sectionHeaderHeight: CGFloat = 34
        static let bestMatchHeaderHeight: CGFloat = 8
        static let headerLabelLeading: CGFloat = 24
        static let headerLabelTrailing: CGFloat = 16
        static let headerLabelTop: CGFloat = 10
        static let headerLabelBottom: CGFloat = 6
        static let sectionHeaderFontSize: CGFloat = 15
    }
    
    private enum SuggestionSection: Int, CaseIterable {
        case topSuggestions
        case searchSuggestions
        case userDataResults
    }
    
    private enum SuggestionRow {
        case bestMatch(UserDataSearchResult)
        case topDomain(String)
        case autocomplete(query: String)
        case completion(String)
        case userDataResult(UserDataSearchResult)
    }
    
    private enum SuggestionIdentity: Equatable {
        case userData(UserDataSearchResult)
        case topDomain(String)
        case autocomplete(String)
        case completion(String)
    }
    
    weak var delegate: SearchViewControllerDelegate?
    var overlayContentHeightDidChange: ((CGFloat) -> Void)?
    
    private let viewModel: SearchViewModel
    private var results = SearchResults.empty
    private var chromeMode: BrowserChromeMode = .phone
    private var lastReportedOverlayContentHeight: CGFloat = -1
    private var selectedSuggestionIdentity: SuggestionIdentity?
    
    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.alwaysBounceVertical = true
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .none
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    
    private lazy var bestMatchSpacerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var userDataHeaderView = makeSectionHeaderView(title: NSLocalizedString("Bookmarks, History, and Tabs", comment: ""))
    
    // MARK: - Lifecycle
    
    init(viewModel: SearchViewModel = SearchViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        configureViewModel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureTableView()
        configureHierarchy()
        configureConstraints()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportOverlayContentHeightIfNeeded()
    }
    
    // MARK: - Public API
    
    func updateQuery(_ query: String, openTabs: [UserDataSearch.OpenTab]) {
        viewModel.updateQuery(query, openTabs: openTabs)
    }
    
    func clearSuggestions() {
        viewModel.clear()
    }
    
    func setChromeMode(_ chromeMode: BrowserChromeMode) {
        guard self.chromeMode != chromeMode else {
            return
        }
        
        self.chromeMode = chromeMode
        tableView.reloadData()
        reportOverlayContentHeightIfNeeded()
    }
    
    var hasSuggestions: Bool {
        return !suggestionIndexPaths.isEmpty
    }
    
    func moveSuggestionSelection(by offset: Int) {
        let indexPaths = suggestionIndexPaths
        guard !indexPaths.isEmpty,
              offset != 0 else {
            return
        }
        
        let currentIndex = selectedSuggestionIndexPath.flatMap {
            indexPaths.firstIndex(of: $0)
        } ?? 0
        let selectedIndex = (currentIndex + offset + indexPaths.count) % indexPaths.count
        guard let row = suggestionRow(at: indexPaths[selectedIndex]) else {
            return
        }
        
        selectedSuggestionIdentity = suggestionIdentity(for: row)
        updateVisibleSuggestionHighlights()
        scrollToSuggestionIfNeeded(at: indexPaths[selectedIndex], offset: offset)
    }
    
    @discardableResult
    func submitSelectedSuggestion() -> Bool {
        guard let selectedSuggestionIndexPath,
              let suggestionRow = suggestionRow(at: selectedSuggestionIndexPath) else {
            return false
        }
        selectSuggestion(suggestionRow)
        return true
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        SuggestionSection.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return suggestionRows(in: section).count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let suggestionRow = suggestionRow(at: indexPath) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        
        switch suggestionRow {
        case let .bestMatch(result):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UserDataSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! UserDataSuggestionCell
            cell.apply(result: result, showsFavicon: true)
            return cell
        case let .topDomain(domain):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: domain, query: results.query)
            cell.setIcon(UIImage(named: "reynard.globe"))
            cell.setTrailingIconVisible(true)
            cell.setTrailingIconDirection(upward: chromeMode != .phone)
            return cell
        case let .autocomplete(query):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: query, query: query)
            cell.setIcon(UIImage(named: "reynard.magnifyingglass"))
            cell.setTrailingIconVisible(false)
            return cell
        case let .completion(completion):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: completion, query: results.query)
            cell.setIcon(UIImage(named: "reynard.magnifyingglass"))
            cell.setTrailingIconVisible(true)
            cell.setTrailingIconDirection(upward: chromeMode != .phone)
            return cell
        case let .userDataResult(result):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UserDataSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! UserDataSuggestionCell
            cell.apply(result: result)
            return cell
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? SuggestionCell)?.setFilledBackgroundVisible(isSuggestionHighlighted(at: indexPath))
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionKind = SuggestionSection(rawValue: section) else {
            return nil
        }
        
        switch sectionKind {
        case .topSuggestions:
            return results.bestMatch == nil ? nil : bestMatchSpacerView
        case .searchSuggestions:
            return hasQuery ? makeSectionHeaderView(title: String(format: NSLocalizedString("%@ Suggestions", comment: "Search provider name"), viewModel.searchSuggestionProvider.name)) : nil
        case .userDataResults:
            return showsUserDataResults ? userDataHeaderView : nil
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sectionKind = SuggestionSection(rawValue: section) else {
            return .leastNormalMagnitude
        }
        
        switch sectionKind {
        case .topSuggestions:
            return results.bestMatch == nil ? .leastNormalMagnitude : UX.bestMatchHeaderHeight
        case .searchSuggestions:
            return hasQuery ? UX.sectionHeaderHeight : .leastNormalMagnitude
        case .userDataResults:
            return showsUserDataResults ? UX.sectionHeaderHeight : .leastNormalMagnitude
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard SuggestionSection(rawValue: section) == .topSuggestions,
              !suggestionRows(in: section).isEmpty else {
            return nil
        }
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard SuggestionSection(rawValue: section) == .topSuggestions,
              !suggestionRows(in: section).isEmpty else {
            return .leastNormalMagnitude
        }
        return UX.bestMatchHeaderHeight
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let suggestionRow = suggestionRow(at: indexPath) else {
            return
        }
        selectSuggestion(suggestionRow)
    }
    
    private func selectSuggestion(_ suggestionRow: SuggestionRow) {
        switch suggestionRow {
        case let .bestMatch(result), let .userDataResult(result):
            delegate?.searchViewController(self, didSelectSuggestion: result.url.absoluteString, result: result)
        case let .topDomain(domain):
            delegate?.searchViewController(self, didSelectSuggestion: "https://\(domain)", result: nil)
        case let .autocomplete(domain), let .completion(domain):
            delegate?.searchViewController(self, didSelectSuggestion: domain, result: nil)
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.searchViewControllerDidStartScrolling(self)
    }
    
    // MARK: - View Model
    
    private func configureViewModel() {
        viewModel.resultsDidChange = { [weak self] updatedResults in
            self?.applyResults(updatedResults)
        }
    }
    
    private func applyResults(_ newResults: SearchResults) {
        let queryChanged = results.query != newResults.query
        results = newResults
        if queryChanged || selectedSuggestionIndexPath == nil {
            self.selectedSuggestionIdentity = nil
        }
        tableView.reloadData()
        delegate?.searchViewController(
            self,
            didUpdateAutocompleteFor: newResults.query,
            result: hasQuery ? newResults.bestMatch : nil,
            topDomain: hasQuery ? visibleTopDomainCompletions.first : nil
        )
        reportOverlayContentHeightIfNeeded()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        view.backgroundColor = .clear
    }
    
    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = UX.estimatedRowHeight
        tableView.contentInset = UIEdgeInsets(top: UX.tableInset, left: 0, bottom: UX.tableInset, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: UX.tableInset, left: 0, bottom: UX.tableInset, right: 0)
        tableView.register(SearchSuggestionCell.self, forCellReuseIdentifier: SearchSuggestionCell.reuseIdentifier)
        tableView.register(UserDataSuggestionCell.self, forCellReuseIdentifier: UserDataSuggestionCell.reuseIdentifier)
    }
    
    private func configureHierarchy() {
        view.addSubview(tableView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func makeSectionHeaderView(title: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UX.sectionHeaderFontSize, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = title
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UX.headerLabelLeading),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UX.headerLabelTrailing),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -UX.headerLabelBottom),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: UX.headerLabelTop),
        ])
        
        return container
    }
    
    // MARK: - Rows
    
    private var hasQuery: Bool {
        return !results.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var showsUserDataResults: Bool {
        return hasQuery && !results.userDataResults.isEmpty
    }
    
    private var visibleTopDomainCompletions: [String] {
        guard results.bestMatch == nil else {
            return []
        }
        
        return results.topDomainCompletions
    }
    
    private var visibleCompletions: [String] {
        guard showsUserDataResults else {
            return results.completions
        }
        
        return Array(results.completions.prefix(UX.limitedCompletionCountWithUserData))
    }
    
    private var suggestionIndexPaths: [IndexPath] {
        return SuggestionSection.allCases.flatMap { section in
            suggestionRows(in: section.rawValue).indices.map {
                IndexPath(row: $0, section: section.rawValue)
            }
        }
    }
    
    private var selectedSuggestionIndexPath: IndexPath? {
        guard let selectedSuggestionIdentity else {
            return nil
        }
        return suggestionIndexPaths.first { indexPath in
            suggestionRow(at: indexPath).map { suggestionIdentity(for: $0) } == selectedSuggestionIdentity
        }
    }
    
    private func suggestionIdentity(for row: SuggestionRow) -> SuggestionIdentity {
        switch row {
        case let .bestMatch(result), let .userDataResult(result):
            return .userData(result)
        case let .topDomain(domain):
            return .topDomain(domain)
        case let .autocomplete(query):
            return .autocomplete(query)
        case let .completion(completion):
            return .completion(completion)
        }
    }
    
    private func isSuggestionHighlighted(at indexPath: IndexPath) -> Bool {
        if let selectedSuggestionIndexPath {
            return indexPath == selectedSuggestionIndexPath
        }
        return indexPath == suggestionIndexPaths.first
    }
    
    private func updateVisibleSuggestionHighlights() {
        tableView.indexPathsForVisibleRows?.forEach { indexPath in
            let cell = tableView.cellForRow(at: indexPath) as? SuggestionCell
            cell?.setFilledBackgroundVisible(isSuggestionHighlighted(at: indexPath))
        }
    }
    
    private func scrollToSuggestionIfNeeded(at indexPath: IndexPath, offset: Int) {
        tableView.layoutIfNeeded()
        let visibleBounds = tableView.bounds.inset(by: tableView.adjustedContentInset)
        guard !visibleBounds.contains(tableView.rectForRow(at: indexPath)) else {
            return
        }
        tableView.scrollToRow(
            at: indexPath,
            at: offset > 0 ? .bottom : .top,
            animated: false
        )
    }
    
    private func suggestionRows(in section: Int) -> [SuggestionRow] {
        guard let sectionKind = SuggestionSection(rawValue: section) else {
            return []
        }
        
        switch sectionKind {
        case .topSuggestions:
            guard hasQuery else {
                return []
            }
            
            if let bestMatch = results.bestMatch {
                return [.bestMatch(bestMatch)]
            }
            
            return results.topDomainCompletions.map { .topDomain($0) }
        case .searchSuggestions:
            let completions = visibleCompletions.map { SuggestionRow.completion($0) }
            guard hasQuery else {
                return completions
            }
            
            return [.autocomplete(query: results.query)] + completions
        case .userDataResults:
            return results.userDataResults.map { .userDataResult($0) }
        }
    }
    
    private func suggestionRow(at indexPath: IndexPath) -> SuggestionRow? {
        let rows = suggestionRows(in: indexPath.section)
        guard rows.indices.contains(indexPath.row) else {
            return nil
        }
        
        return rows[indexPath.row]
    }
    
    // MARK: - Content Height
    
    private func reportOverlayContentHeightIfNeeded() {
        guard isViewLoaded else {
            return
        }
        
        tableView.layoutIfNeeded()
        let contentHeight = tableView.contentSize.height
        guard abs(contentHeight - lastReportedOverlayContentHeight) > 0.5 else {
            return
        }
        
        lastReportedOverlayContentHeight = contentHeight
        DispatchQueue.main.async { [weak self] in
            guard self?.lastReportedOverlayContentHeight == contentHeight else {
                return
            }
            self?.overlayContentHeightDidChange?(contentHeight)
        }
    }
}
