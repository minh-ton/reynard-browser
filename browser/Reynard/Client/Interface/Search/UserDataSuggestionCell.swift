//
//  UserDataSuggestionCell.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class UserDataSuggestionCell: UITableViewCell {
    private enum UX {
        static let iconSize: CGFloat = 19.5
        static let textLeadingSpacing: CGFloat = 13
        static let textTopInset: CGFloat = 11
        static let textBottomInset: CGFloat = 11
        static let subtitleTopSpacing: CGFloat = 1
    }
    
    static let reuseIdentifier = "UserDataSuggestionCell"
    
    private static let faviconStore = FaviconStore.shared
    private static let relativeDateFormatter = RelativeDateTimeFormatter()
    
    private let sourceIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        imageView.image = UIImage(named: "reynard.globe")
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
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let textStackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var representedURL: URL?
    private var faviconTask: Task<Void, Never>?
    
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
    
    deinit {
        faviconTask?.cancel()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        faviconTask?.cancel()
        faviconTask = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        sourceIconView.image = UIImage(named: "reynard.globe")
        sourceIconView.tintColor = .label
        setFilledBackgroundVisible(false)
    }
    
    // MARK: - Configuration
    
    func apply(result: UserDataSearchResult, showsFavicon: Bool = false) {
        representedURL = result.url
        faviconTask?.cancel()
        faviconTask = nil
        
        titleLabel.text = result.title
        switch result.source {
        case .bookmark:
            subtitleLabel.text = URLUtils.displayString(for: result.url)
            sourceIconView.image = UIImage(named: "reynard.book")
        case .history:
            let relativeDate = Self.relativeDateFormatter.localizedString(for: result.lastVisitedAt ?? Date(), relativeTo: Date())
            subtitleLabel.text = "\(URLUtils.hostDisplayString(for: result.url)) · Visited \(relativeDate)"
            sourceIconView.image = UIImage(named: "reynard.clock")
        case .tab:
            subtitleLabel.text = "\(URLUtils.hostDisplayString(for: result.url)) · Opened Tab"
            sourceIconView.image = UIImage(named: "reynard.square.on.square")
        }
        
        sourceIconView.tintColor = .label
        guard showsFavicon else {
            return
        }
        
        resolveFavicon(for: result.url)
    }
    
    func setFilledBackgroundVisible(_ visible: Bool) {
        contentView.backgroundColor = visible ? .secondarySystemBackground : .clear
    }
    
    private func configureAppearance() {
        selectionStyle = .none
        clipsToBounds = true
        contentView.clipsToBounds = true
        backgroundColor = .clear
        contentView.backgroundColor = .secondarySystemBackground
    }
    
    private func configureHierarchy() {
        contentView.addSubview(sourceIconView)
        contentView.addSubview(textStackView)
        textStackView.addSubview(titleLabel)
        textStackView.addSubview(subtitleLabel)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            sourceIconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            sourceIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            sourceIconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            textStackView.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: UX.textLeadingSpacing),
            textStackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStackView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.textTopInset),
            textStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.textBottomInset),
            
            titleLabel.topAnchor.constraint(equalTo: textStackView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textStackView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: textStackView.trailingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: UX.subtitleTopSpacing),
            subtitleLabel.leadingAnchor.constraint(equalTo: textStackView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: textStackView.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: textStackView.bottomAnchor),
        ])
    }
    
    // MARK: - Favicon
    
    private func resolveFavicon(for url: URL) {
        if let cachedImage = Self.faviconStore.cachedFavicon(for: url) {
            sourceIconView.image = cachedImage
            sourceIconView.tintColor = nil
            return
        }
        
        sourceIconView.image = UIImage(named: "reynard.globe")
        sourceIconView.tintColor = .label
        
        faviconTask = Task { [weak self] in
            guard let self else { return }
            
            let image = await Self.faviconStore.favicon(for: url)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                guard self.representedURL == url else { return }
                self.sourceIconView.image = image ?? UIImage(named: "reynard.globe")
                self.sourceIconView.tintColor = image == nil ? .label : nil
            }
        }
    }
}
