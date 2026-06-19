//
//  SearchViewController.swift
//  Reynard
//
//  Created by Minh Ton on 1/6/26.
//

import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, result: UserDataSearchResult?)
    func searchViewController(_ controller: SearchViewController, didUpdateAutocompleteFor query: String, result: UserDataSearchResult?)
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
        case primarySuggestion
        case typedQuery
        case completions
        case userDataResults
    }
    
    private enum SuggestionRow {
        case bestMatch(UserDataSearchResult)
        case autocomplete(query: String)
        case completion(String)
        case userDataResult(UserDataSearchResult)
    }
    
    weak var delegate: SearchViewControllerDelegate?
    var overlayContentHeightDidChange: ((CGFloat) -> Void)?
    
    private let viewModel: SearchViewModel
    private var results = SearchResults.empty
    private var chromeMode: BrowserChromeMode = .phone
    private var lastReportedOverlayContentHeight: CGFloat = -1
    
    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
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
    
    private lazy var completionsHeaderView = makeSectionHeaderView(title: "\(viewModel.completionProvider.name) Suggestions")
    private lazy var userDataHeaderView = makeSectionHeaderView(title: "Bookmarks, History, and Tabs")
    
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
    
    func updateQuery(
        _ query: String,
        activeTabMode: TabMode?,
        excludingTabID: UUID?
    ) {
        viewModel.updateQuery(
            query,
            activeTabMode: activeTabMode,
            excludingTabID: excludingTabID
        )
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
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        SuggestionSection.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionKind = SuggestionSection(rawValue: section) else { return 0 }
        switch sectionKind {
        case .primarySuggestion:
            return hasQuery && results.bestMatch != nil ? 1 : 0
        case .typedQuery:
            return hasQuery ? 1 : 0
        case .completions:
            return visibleCompletions.count
        case .userDataResults:
            return results.userDataResults.count
        }
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
            cell.setFilledBackgroundVisible(true)
            return cell
        case let .autocomplete(query):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: query, query: query)
            cell.setTrailingIconVisible(false)
            cell.setFilledBackgroundVisible(results.bestMatch == nil)
            return cell
        case let .completion(completion):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: completion, query: results.query)
            cell.setTrailingIconVisible(true)
            cell.setTrailingIconDirection(upward: chromeMode != .phone)
            cell.setFilledBackgroundVisible(false)
            return cell
        case let .userDataResult(result):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UserDataSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! UserDataSuggestionCell
            cell.apply(result: result)
            cell.setFilledBackgroundVisible(false)
            return cell
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionKind = SuggestionSection(rawValue: section) else {
            return nil
        }
        
        switch sectionKind {
        case .primarySuggestion:
            return results.bestMatch == nil ? nil : bestMatchSpacerView
        case .typedQuery:
            return hasQuery ? completionsHeaderView : nil
        case .completions:
            return nil
        case .userDataResults:
            return showsUserDataResults ? userDataHeaderView : nil
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sectionKind = SuggestionSection(rawValue: section) else {
            return .leastNormalMagnitude
        }
        
        switch sectionKind {
        case .primarySuggestion:
            return results.bestMatch == nil ? .leastNormalMagnitude : UX.bestMatchHeaderHeight
        case .typedQuery:
            return hasQuery ? UX.sectionHeaderHeight : .leastNormalMagnitude
        case .completions:
            return .leastNormalMagnitude
        case .userDataResults:
            return showsUserDataResults ? UX.sectionHeaderHeight : .leastNormalMagnitude
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let sectionKind = SuggestionSection(rawValue: section),
              sectionKind == .primarySuggestion,
              results.bestMatch != nil else {
            return nil
        }
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let sectionKind = SuggestionSection(rawValue: section),
              sectionKind == .primarySuggestion,
              results.bestMatch != nil else {
            return .leastNormalMagnitude
        }
        return UX.bestMatchHeaderHeight
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let suggestionRow = suggestionRow(at: indexPath) else {
            return
        }
        
        switch suggestionRow {
        case let .bestMatch(result), let .userDataResult(result):
            delegate?.searchViewController(self, didSelectSuggestion: result.url.absoluteString, result: result)
        case let .autocomplete(query), let .completion(query):
            delegate?.searchViewController(self, didSelectSuggestion: query, result: nil)
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
        results = newResults
        tableView.reloadData()
        delegate?.searchViewController(
            self,
            didUpdateAutocompleteFor: newResults.query,
            result: hasQuery ? newResults.bestMatch : nil
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
    
    private var visibleCompletions: [String] {
        guard showsUserDataResults else {
            return results.completions
        }
        
        return Array(results.completions.prefix(UX.limitedCompletionCountWithUserData))
    }
    
    private func suggestionRow(at indexPath: IndexPath) -> SuggestionRow? {
        guard let sectionKind = SuggestionSection(rawValue: indexPath.section) else {
            return nil
        }
        
        switch sectionKind {
        case .primarySuggestion:
            guard indexPath.row == 0,
                  hasQuery,
                  let bestMatch = results.bestMatch else {
                return nil
            }
            
            return .bestMatch(bestMatch)
        case .typedQuery:
            guard indexPath.row == 0, hasQuery else {
                return nil
            }
            
            return .autocomplete(query: results.query)
        case .completions:
            guard visibleCompletions.indices.contains(indexPath.row) else {
                return nil
            }
            
            return .completion(visibleCompletions[indexPath.row])
        case .userDataResults:
            guard results.userDataResults.indices.contains(indexPath.row) else {
                return nil
            }
            
            return .userDataResult(results.userDataResults[indexPath.row])
        }
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
