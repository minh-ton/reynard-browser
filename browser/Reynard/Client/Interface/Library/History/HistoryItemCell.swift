//
//  HistoryItemCell.swift
//  Reynard
//
//  Created by Minh Ton on 23/4/26.
//

import UIKit

final class HistoryItemCell: UITableViewCell {
    private enum UX {
        static let labelsStackSpacing: CGFloat = 4
        static let faviconSize: CGFloat = 26
        static let faviconVerticalInset: CGFloat = 13
        static let labelsLeadingSpacing: CGFloat = 13
        static let labelsVerticalInset: CGFloat = 13
        static let separatorLeftInset: CGFloat = 56
    }
    
    static let reuseIdentifier = "HistoryItemCell"
    
    private static let faviconStore = FaviconStore.shared
    
    private let faviconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    private let pageTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        return label
    }()
    
    private let pageURLLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        return label
    }()
    
    private var representedURL: URL?
    private var faviconTask: Task<Void, Never>?
    
    // MARK: - Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        clipsToBounds = true
        contentView.clipsToBounds = true
        
        let labelsStack = UIStackView(arrangedSubviews: [pageTitleLabel, pageURLLabel])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = UX.labelsStackSpacing
        
        contentView.addSubview(faviconView)
        contentView.addSubview(labelsStack)
        
        NSLayoutConstraint.activate([
            faviconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            faviconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            faviconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.faviconVerticalInset),
            faviconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.faviconVerticalInset),
            faviconView.widthAnchor.constraint(equalToConstant: UX.faviconSize),
            faviconView.heightAnchor.constraint(equalToConstant: UX.faviconSize),
            
            labelsStack.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: UX.labelsLeadingSpacing),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.labelsVerticalInset),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.labelsVerticalInset),
        ])
        
        separatorInset.left = UX.separatorLeftInset
        
        setFavicon(nil)
    }
    
    // MARK: - Reuse And Layout
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        LibrarySharedUtils.alignSeparatorWithReadableContent(in: self)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        faviconTask?.cancel()
        faviconTask = nil
        pageTitleLabel.text = nil
        pageURLLabel.text = nil
        setFavicon(nil)
    }
    
    // MARK: - Configuration
    
    func configure(with item: HistorySiteSnapshot) {
        representedURL = item.url
        faviconTask?.cancel()
        faviconTask = nil
        
        pageTitleLabel.text = item.title
        pageURLLabel.text = item.url.absoluteString
        
        if let cachedImage = Self.faviconStore.cachedFavicon(for: item.url) {
            setFavicon(cachedImage)
            return
        }
        
        setFavicon(nil)
        let expectedURL = item.url
        faviconTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            let image = await Self.faviconStore.favicon(for: expectedURL)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                guard self.representedURL == expectedURL else {
                    return
                }
                
                self.setFavicon(image)
            }
        }
    }
    
    private func setFavicon(_ image: UIImage?) {
        if let image {
            faviconView.image = image
            faviconView.tintColor = nil
            return
        }
        
        faviconView.image = UIImage(named: "reynard.globe")
        faviconView.tintColor = .secondaryLabel
    }
}
