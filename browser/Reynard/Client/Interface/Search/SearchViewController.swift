//
//  SearchViewController.swift
//  Reynard
//
//  Created by Minh Ton on 1/6/26.
//

import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelectSuggestion suggestion: String, match: SearchAuxiliaryMatch?)
    func searchViewControllerDidStartScrolling(_ controller: SearchViewController)
}

final class SearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Constants {
        static let suggestionsSectionTitle = "Google Suggestions"
        static let auxiliarySectionTitle = "Bookmarks, History, and Tabs"
        static let hiddenRowHeight: CGFloat = 0.01
        static let limitedSuggestionCountWithAuxiliary = 4
        static let tableInset: CGFloat = 8
    }
    
    private enum SectionKind: Int, CaseIterable {
        case primary
        case firstSuggestion
        case remainingSuggestions
        case auxiliaryMatches
    }
    
    weak var delegate: SearchViewControllerDelegate?
    var overlayContentHeightDidChange: ((CGFloat) -> Void)?
    
    private var suggestions: [String] = []
    private var currentQuery = ""
    private var primaryMatch: SearchAuxiliaryMatch?
    private var auxiliaryMatches: [SearchAuxiliaryMatch] = []
    private var usesTopAddressBarMode = false
    private var usesPadChromeMode = false
    private var usesDetachedOverlayAppearance = false
    private var lastReportedOverlayContentHeight: CGFloat = -1
    private let backgroundContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 36
        view.layer.masksToBounds = true
        return view
    }()
    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.alwaysBounceVertical = true
        tableView.backgroundColor = .systemBackground
        tableView.keyboardDismissMode = .none
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    private lazy var bookmarkHeaderSpacerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    private lazy var suggestionsHeaderView: UIView = {
        let container = UIView()
        container.backgroundColor = .systemBackground
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = Constants.suggestionsSectionTitle
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
        ])
        
        return container
    }()
    private lazy var auxiliarySectionHeaderView: UIView = {
        let container = UIView()
        container.backgroundColor = .systemBackground
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = Constants.auxiliarySectionTitle
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
        ])
        
        return container
    }()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 60
        tableView.contentInset = UIEdgeInsets(top: Constants.tableInset, left: 0, bottom: Constants.tableInset, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: Constants.tableInset, left: 0, bottom: Constants.tableInset, right: 0)
        tableView.register(SearchSuggestionCell.self, forCellReuseIdentifier: SearchSuggestionCell.reuseIdentifier)
        tableView.register(SearchBookmarkCell.self, forCellReuseIdentifier: SearchBookmarkCell.reuseIdentifier)
        
        view.addSubview(backgroundContainerView)
        backgroundContainerView.addSubview(blurView)
        backgroundContainerView.addSubview(tableView)
        NSLayoutConstraint.activate([
            backgroundContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            blurView.topAnchor.constraint(equalTo: backgroundContainerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: backgroundContainerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: backgroundContainerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: backgroundContainerView.bottomAnchor),
            
            tableView.topAnchor.constraint(equalTo: backgroundContainerView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: backgroundContainerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: backgroundContainerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: backgroundContainerView.bottomAnchor),
        ])
        applyOverlayAppearance()
    }
    
    func setSuggestions(
        _ suggestions: [String],
        forQuery query: String = "",
        primaryMatch: SearchAuxiliaryMatch? = nil,
        auxiliaryMatches: [SearchAuxiliaryMatch] = []
    ) {
        self.suggestions = suggestions
        currentQuery = query
        self.primaryMatch = primaryMatch
        self.auxiliaryMatches = auxiliaryMatches
        tableView.reloadData()
        reportOverlayContentHeightIfNeeded()
    }
    
    func setUsesTopAddressBarMode(_ usesTopAddressBarMode: Bool) {
        guard self.usesTopAddressBarMode != usesTopAddressBarMode else {
            return
        }
        
        self.usesTopAddressBarMode = usesTopAddressBarMode
        tableView.reloadData()
        reportOverlayContentHeightIfNeeded()
    }
    
    func setUsesPadChromeMode(_ usesPadChromeMode: Bool) {
        guard self.usesPadChromeMode != usesPadChromeMode else {
            return
        }
        
        self.usesPadChromeMode = usesPadChromeMode
        tableView.reloadData()
        reportOverlayContentHeightIfNeeded()
    }
    
    func setUsesDetachedOverlayAppearance(_ usesDetachedOverlayAppearance: Bool) {
        guard self.usesDetachedOverlayAppearance != usesDetachedOverlayAppearance else {
            return
        }
        
        self.usesDetachedOverlayAppearance = usesDetachedOverlayAppearance
        guard isViewLoaded else {
            return
        }
        
        applyOverlayAppearance()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportOverlayContentHeightIfNeeded()
    }
    
    
    func numberOfSections(in tableView: UITableView) -> Int {
        SectionKind.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionKind = SectionKind(rawValue: section) else { return 0 }
        switch sectionKind {
        case .primary, .firstSuggestion:
            return 1
        case .remainingSuggestions:
            return displayedSuggestions.count
        case .auxiliaryMatches:
            return auxiliaryMatches.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionKind = SectionKind(rawValue: indexPath.section) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        switch sectionKind {
        case .primary:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchBookmarkCell.reuseIdentifier,
                for: indexPath
            ) as! SearchBookmarkCell
            if let primaryMatch {
                cell.apply(auxiliaryMatch: primaryMatch, showsFavicon: true)
            }
            cell.setShowsFilledBackground(true)
            return cell
        case .firstSuggestion:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            cell.apply(text: currentQuery, query: currentQuery)
            cell.setShowsTrailingIcon(false)
            cell.setShowsFilledBackground(primaryMatch == nil)
            return cell
        case .remainingSuggestions:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchSuggestionCell.reuseIdentifier,
                for: indexPath
            ) as! SearchSuggestionCell
            guard displayedSuggestions.indices.contains(indexPath.row) else { return cell }
            cell.apply(text: displayedSuggestions[indexPath.row], query: currentQuery)
            cell.setShowsTrailingIcon(true)
            cell.setTrailingIconPointsUp(usesTopAddressBarMode || usesPadChromeMode)
            cell.setShowsFilledBackground(false)
            return cell
        case .auxiliaryMatches:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchBookmarkCell.reuseIdentifier,
                for: indexPath
            ) as! SearchBookmarkCell
            guard auxiliaryMatches.indices.contains(indexPath.row) else { return cell }
            cell.apply(auxiliaryMatch: auxiliaryMatches[indexPath.row])
            cell.setShowsFilledBackground(false)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionKind = SectionKind(rawValue: section) else {
            return nil
        }
        
        switch sectionKind {
        case .primary:
            return primaryMatch == nil ? nil : bookmarkHeaderSpacerView
        case .firstSuggestion:
            return hasSearchQuery ? suggestionsHeaderView : nil
        case .remainingSuggestions:
            return nil
        case .auxiliaryMatches:
            return hasVisibleAuxiliaryMatches ? auxiliarySectionHeaderView : nil
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sectionKind = SectionKind(rawValue: section) else {
            return .leastNormalMagnitude
        }
        
        switch sectionKind {
        case .primary:
            return primaryMatch == nil ? .leastNormalMagnitude : 8
        case .firstSuggestion:
            return hasSearchQuery ? 34 : .leastNormalMagnitude
        case .remainingSuggestions:
            return .leastNormalMagnitude
        case .auxiliaryMatches:
            return hasVisibleAuxiliaryMatches ? 34 : .leastNormalMagnitude
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let sectionKind = SectionKind(rawValue: section), sectionKind == .primary, primaryMatch != nil else {
            return nil
        }
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sectionKind = SectionKind(rawValue: indexPath.section) else {
            return UITableView.automaticDimension
        }
        
        switch sectionKind {
        case .primary:
            return primaryMatch == nil ? Constants.hiddenRowHeight : UITableView.automaticDimension
        case .firstSuggestion:
            return hasSearchQuery ? UITableView.automaticDimension : Constants.hiddenRowHeight
        case .remainingSuggestions:
            return displayedSuggestions.isEmpty ? Constants.hiddenRowHeight : UITableView.automaticDimension
        case .auxiliaryMatches:
            return UITableView.automaticDimension
        }
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sectionKind = SectionKind(rawValue: indexPath.section) else {
            return tableView.estimatedRowHeight
        }
        
        switch sectionKind {
        case .primary:
            return primaryMatch == nil ? Constants.hiddenRowHeight : tableView.estimatedRowHeight
        case .firstSuggestion:
            return hasSearchQuery ? tableView.estimatedRowHeight : Constants.hiddenRowHeight
        case .remainingSuggestions:
            return displayedSuggestions.isEmpty ? Constants.hiddenRowHeight : tableView.estimatedRowHeight
        case .auxiliaryMatches:
            return tableView.estimatedRowHeight
        }
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let sectionKind = SectionKind(rawValue: section), sectionKind == .primary, primaryMatch != nil else {
            return .leastNormalMagnitude
        }
        return 8
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionKind = SectionKind(rawValue: indexPath.section) else {
            return
        }
        switch sectionKind {
        case .primary:
            guard let primaryMatch else { return }
            delegate?.searchViewController(self, didSelectSuggestion: primaryMatch.url.absoluteString, match: primaryMatch)
        case .firstSuggestion:
            guard hasSearchQuery else { return }
            delegate?.searchViewController(self, didSelectSuggestion: currentQuery, match: nil)
        case .remainingSuggestions:
            guard displayedSuggestions.indices.contains(indexPath.row) else { return }
            delegate?.searchViewController(self, didSelectSuggestion: displayedSuggestions[indexPath.row], match: nil)
        case .auxiliaryMatches:
            guard auxiliaryMatches.indices.contains(indexPath.row) else { return }
            delegate?.searchViewController(self, didSelectSuggestion: auxiliaryMatches[indexPath.row].url.absoluteString, match: auxiliaryMatches[indexPath.row])
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.searchViewControllerDidStartScrolling(self)
    }
    
    private var hasSearchQuery: Bool {
        !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var hasVisibleAuxiliaryMatches: Bool {
        hasSearchQuery && !auxiliaryMatches.isEmpty
    }
    
    private var displayedSuggestions: [String] {
        guard hasVisibleAuxiliaryMatches else {
            return suggestions
        }
        
        return Array(suggestions.prefix(Constants.limitedSuggestionCountWithAuxiliary))
    }
    
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
    
    private func applyOverlayAppearance() {
        let backgroundColor: UIColor = usesDetachedOverlayAppearance ? .clear : .systemBackground
        let tableBackgroundColor: UIColor = usesDetachedOverlayAppearance ? .clear : .systemBackground
        backgroundContainerView.backgroundColor = backgroundColor
        backgroundContainerView.layer.masksToBounds = usesDetachedOverlayAppearance
        tableView.backgroundColor = tableBackgroundColor
        suggestionsHeaderView.backgroundColor = tableBackgroundColor
        auxiliarySectionHeaderView.backgroundColor = tableBackgroundColor
        blurView.effect = usesDetachedOverlayAppearance ? UIBlurEffect(style: .systemChromeMaterial) : nil
        blurView.contentView.backgroundColor = usesDetachedOverlayAppearance
        ? UIColor.systemBackground.withAlphaComponent(0.28)
        : .clear
        
        if #available(iOS 26.0, *) {
            backgroundContainerView.layer.cornerRadius = usesDetachedOverlayAppearance ? 36 : 0
        } else {
            backgroundContainerView.layer.cornerRadius = usesDetachedOverlayAppearance ? 12 : 0
        }
    }
    
}

private final class SearchSuggestionCell: UITableViewCell {
    static let reuseIdentifier = "SearchSuggestionCell"
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "magnifyingglass")
        imageView.tintColor = .label
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let trailingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "arrow.down.left.circle")
        imageView.tintColor = .tertiaryLabel
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        clipsToBounds = true
        contentView.clipsToBounds = true
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(trailingImageView)
        
        let iconSize = 26.0 * 0.75
        let trailingIconSize = 26.0 * 0.75
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            trailingImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingImageView.widthAnchor.constraint(equalToConstant: trailingIconSize),
            trailingImageView.heightAnchor.constraint(equalToConstant: trailingIconSize),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(equalTo: trailingImageView.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        setShowsTrailingIcon(true)
        setTrailingIconPointsUp(false)
        setShowsFilledBackground(false)
    }
    
    func apply(text: String, query: String) {
        titleLabel.attributedText = attributedTitle(for: text, query: query)
    }
    
    private func attributedTitle(for suggestion: String, query: String) -> NSAttributedString {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return NSAttributedString(
                string: suggestion,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
        
        let sharedLength = sharedPrefixLength(lhs: suggestion, rhs: normalizedQuery)
        let attributed = NSMutableAttributedString()
        if sharedLength > 0 {
            let sharedPrefix = String(suggestion.prefix(sharedLength))
            attributed.append(NSAttributedString(
                string: sharedPrefix,
                attributes: [.foregroundColor: UIColor.label]
            ))
        }
        
        let suffix = String(suggestion.dropFirst(sharedLength))
        if !suffix.isEmpty {
            attributed.append(NSAttributedString(
                string: suffix,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            ))
        }
        
        if attributed.length == 0 {
            return NSAttributedString(
                string: suggestion,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
        
        return attributed
    }
    
    private func sharedPrefixLength(lhs: String, rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let count = min(lhsChars.count, rhsChars.count)
        var shared = 0
        
        while shared < count {
            let left = String(lhsChars[shared]).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let right = String(rhsChars[shared]).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if left != right {
                break
            }
            shared += 1
        }
        
        return shared
    }
    
    func setShowsFilledBackground(_ showsFilledBackground: Bool) {
        contentView.backgroundColor = showsFilledBackground ? .secondarySystemBackground : .clear
    }
    
    func setShowsTrailingIcon(_ showsTrailingIcon: Bool) {
        trailingImageView.isHidden = !showsTrailingIcon
    }
    
    func setTrailingIconPointsUp(_ pointsUp: Bool) {
        trailingImageView.image = UIImage(systemName: pointsUp ? "arrow.up.left.circle" : "arrow.down.left.circle")
    }
}

private final class SearchBookmarkCell: UITableViewCell {
    static let reuseIdentifier = "SearchBookmarkCell"
    
    private static let faviconStore = FaviconStore.shared
    private static let relativeDateFormatter = RelativeDateTimeFormatter()
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        imageView.image = UIImage(systemName: "globe")
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let urlLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let textContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var representedURL: URL?
    private var faviconTask: Task<Void, Never>?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        clipsToBounds = true
        contentView.clipsToBounds = true
        backgroundColor = .clear
        contentView.backgroundColor = .secondarySystemBackground
        
        contentView.addSubview(iconView)
        contentView.addSubview(textContainerView)
        textContainerView.addSubview(titleLabel)
        textContainerView.addSubview(urlLabel)
        
        let iconSize = 26.0 * 0.75
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            textContainerView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 13),
            textContainerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textContainerView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 11),
            textContainerView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -11),
            
            titleLabel.topAnchor.constraint(equalTo: textContainerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
            
            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            urlLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
            urlLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
            urlLabel.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        faviconTask?.cancel()
        faviconTask = nil
        titleLabel.text = nil
        urlLabel.text = nil
        iconView.image = UIImage(systemName: "globe")
        iconView.tintColor = .label
    }
    
    func apply(bookmark: BookmarkSnapshot) {
        representedURL = bookmark.url
        faviconTask?.cancel()
        faviconTask = nil
        
        titleLabel.text = bookmark.title
        urlLabel.text = displayURLString(for: bookmark.url)
        
        if let cachedImage = Self.faviconStore.cachedImage(for: bookmark.url) {
            iconView.image = cachedImage
            iconView.tintColor = nil
            return
        }
        
        iconView.image = UIImage(systemName: "globe")
        iconView.tintColor = .label
        
        let expectedURL = bookmark.url
        faviconTask = Task { [weak self] in
            guard let self else { return }
            
            let image = await Self.faviconStore.resolveFavicon(for: expectedURL)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                guard self.representedURL == expectedURL else { return }
                self.iconView.image = image ?? UIImage(systemName: "globe")
                self.iconView.tintColor = image == nil ? .label : nil
            }
        }
    }
    
    func apply(auxiliaryMatch: SearchAuxiliaryMatch, showsFavicon: Bool = false) {
        representedURL = auxiliaryMatch.url
        faviconTask?.cancel()
        faviconTask = nil
        
        titleLabel.text = auxiliaryMatch.title
        switch auxiliaryMatch.kind {
        case .bookmark:
            urlLabel.text = displayURLString(for: auxiliaryMatch.url)
            iconView.image = UIImage(systemName: "book")
        case .history:
            let relativeDate = Self.relativeDateFormatter.localizedString(for: auxiliaryMatch.historyLastVisitedAt ?? Date(), relativeTo: Date())
            urlLabel.text = "\(hostDisplayString(for: auxiliaryMatch.url)) · Visited \(relativeDate)"
            iconView.image = UIImage(systemName: "clock")
        case .tab:
            urlLabel.text = "\(hostDisplayString(for: auxiliaryMatch.url)) · Opened Tab"
            iconView.image = UIImage(systemName: "square.on.square")
        }
        
        iconView.tintColor = .label
        
        guard showsFavicon else {
            return
        }
        
        if let cachedImage = Self.faviconStore.cachedImage(for: auxiliaryMatch.url) {
            iconView.image = cachedImage
            iconView.tintColor = nil
            return
        }
        
        iconView.image = UIImage(systemName: "globe")
        iconView.tintColor = .label
        
        let expectedURL = auxiliaryMatch.url
        faviconTask = Task { [weak self] in
            guard let self else { return }
            
            let image = await Self.faviconStore.resolveFavicon(for: expectedURL)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                guard self.representedURL == expectedURL else { return }
                self.iconView.image = image ?? UIImage(systemName: "globe")
                self.iconView.tintColor = image == nil ? .label : nil
            }
        }
    }
    
    func setShowsFilledBackground(_ showsFilledBackground: Bool) {
        contentView.backgroundColor = showsFilledBackground ? .secondarySystemBackground : .clear
    }
    
    private func hostDisplayString(for url: URL) -> String {
        var host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst("www.".count))
        }
        if !host.isEmpty {
            return host
        }
        
        return displayURLString(for: url)
    }
    
    private func displayURLString(for url: URL) -> String {
        var value = url.absoluteString
        let lowered = value.lowercased()
        if lowered.hasPrefix("https://www.") {
            value = String(value.dropFirst("https://www.".count))
        } else if lowered.hasPrefix("http://www.") {
            value = String(value.dropFirst("http://www.".count))
        } else if lowered.hasPrefix("ftp://www.") {
            value = String(value.dropFirst("ftp://www.".count))
        } else if lowered.hasPrefix("https://") {
            value = String(value.dropFirst("https://".count))
        } else if lowered.hasPrefix("http://") {
            value = String(value.dropFirst("http://".count))
        } else if lowered.hasPrefix("ftp://") {
            value = String(value.dropFirst("ftp://".count))
        } else if lowered.hasPrefix("www.") {
            value = String(value.dropFirst("www.".count))
        }
        if value.count > 1, value.hasSuffix("/") {
            return String(value.dropLast())
        }
        
        return value
    }
}
