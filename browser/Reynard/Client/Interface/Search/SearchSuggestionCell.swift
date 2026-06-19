//
//  SearchSuggestionCell.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class SearchSuggestionCell: UITableViewCell {
    private enum UX {
        static let iconSize: CGFloat = 19.5
        static let titleLeadingSpacing: CGFloat = 13
        static let titleTrailingSpacing: CGFloat = 10
        static let verticalInset: CGFloat = 16
    }
    
    static let reuseIdentifier = "SearchSuggestionCell"
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "reynard.magnifyingglass")
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
    
    private let trailingIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "reynard.arrow.down.left.circle")
        imageView.tintColor = .tertiaryLabel
        return imageView
    }()
    
    // MARK: - Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        setTrailingIconVisible(true)
        setTrailingIconDirection(upward: false)
        setFilledBackgroundVisible(false)
    }
    
    // MARK: - Configuration
    
    func apply(text: String, query: String) {
        titleLabel.attributedText = attributedTitle(for: text, query: query)
    }
    
    func setFilledBackgroundVisible(_ visible: Bool) {
        contentView.backgroundColor = visible ? .secondarySystemBackground : .clear
    }
    
    func setTrailingIconVisible(_ visible: Bool) {
        trailingIconView.isHidden = !visible
    }
    
    func setTrailingIconDirection(upward: Bool) {
        trailingIconView.image = UIImage(named: upward ? "reynard.arrow.up.left.circle" : "reynard.arrow.down.left.circle")
    }
    
    private func configureAppearance() {
        selectionStyle = .none
        clipsToBounds = true
        contentView.clipsToBounds = true
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(trailingIconView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            trailingIconView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingIconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            trailingIconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: UX.titleLeadingSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: trailingIconView.leadingAnchor, constant: -UX.titleTrailingSpacing),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.verticalInset),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.verticalInset),
        ])
    }
    
    // MARK: - Title
    
    private func attributedTitle(for suggestion: String, query: String) -> NSAttributedString {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return NSAttributedString(
                string: suggestion,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
        
        let sharedLength = zip(suggestion, normalizedQuery).prefix { left, right in
            String(left).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == String(right).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }.count
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
}
