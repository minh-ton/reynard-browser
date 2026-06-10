//
//  HistoryItemCell.swift
//  Reynard
//
//  Created by Minh Ton on 23/4/26.
//

import UIKit

final class HistoryItemCell: UITableViewCell {
    static let reuseIdentifier = "HistoryItemCell"
    
    private static let faviconStore = FaviconStore.shared
    
    private let faviconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        return label
    }()
    
    private let urlLabel: UILabel = {
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
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        clipsToBounds = true
        contentView.clipsToBounds = true
        
        let labelsStack = UIStackView(arrangedSubviews: [titleLabel, urlLabel])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = 4
        
        contentView.addSubview(faviconView)
        contentView.addSubview(labelsStack)
        
        NSLayoutConstraint.activate([
            faviconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            faviconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            faviconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 13),
            faviconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),
            faviconView.widthAnchor.constraint(equalToConstant: 26),
            faviconView.heightAnchor.constraint(equalToConstant: 26),
            
            labelsStack.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 13),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 13),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),
        ])
        
        separatorInset.left = 56
        
        applyFavicon(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layoutIfNeeded()
        let guideFrameInContent = contentView.layoutMarginsGuide.layoutFrame
        let guideFrameInCell = convert(guideFrameInContent, from: contentView)
        let rightInset = bounds.width - guideFrameInCell.maxX
        separatorInset = UIEdgeInsets(
            top: separatorInset.top,
            left: separatorInset.left,
            bottom: separatorInset.bottom,
            right: rightInset
        )
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        faviconTask?.cancel()
        faviconTask = nil
        titleLabel.text = nil
        urlLabel.text = nil
        applyFavicon(nil)
    }
    
    func apply(item: HistorySiteSnapshot) {
        representedURL = item.url
        faviconTask?.cancel()
        faviconTask = nil
        
        titleLabel.text = item.title
        urlLabel.text = item.url.absoluteString
        
        if let cachedImage = Self.faviconStore.cachedImage(for: item.url) {
            applyFavicon(cachedImage)
            return
        }
        
        applyFavicon(nil)
        let expectedURL = item.url
        faviconTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            let image = await Self.faviconStore.resolveFavicon(for: expectedURL)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                guard self.representedURL == expectedURL else {
                    return
                }
                
                self.applyFavicon(image)
            }
        }
    }
    
    private func applyFavicon(_ image: UIImage?) {
        if let image {
            faviconView.image = image
            faviconView.tintColor = nil
            return
        }
        
        faviconView.image = UIImage(systemName: "globe")
        faviconView.tintColor = .secondaryLabel
    }
}
