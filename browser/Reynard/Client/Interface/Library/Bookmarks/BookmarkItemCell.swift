//
//  BookmarkItemCell.swift
//  Reynard
//
//  Created by Minh Ton on 23/5/26.
//

final class BookmarkItemCell: UITableViewCell {
    static let reuseIdentifier = "BookmarkItemCell"
    
    private static let faviconStore = FaviconStore.shared
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
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
    private let countLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()
    
    private var representedURL: URL?
    private var faviconTask: Task<Void, Never>?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        clipsToBounds = true
        contentView.clipsToBounds = true
        
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            countLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        
        separatorInset.left = 56
        applyIcon(UIImage(systemName: "globe"), tintColor: .secondaryLabel)
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
        countLabel.text = nil
        countLabel.isHidden = true
        applyIcon(UIImage(systemName: "globe"), tintColor: .secondaryLabel)
    }
    
    func apply(folder: BookmarkFolderSnapshot) {
        representedURL = nil
        faviconTask?.cancel()
        faviconTask = nil
        titleLabel.text = folder.title
        countLabel.text = "\(folder.childCount)"
        countLabel.isHidden = false
        
        if folder.isProtected && folder.title == "Favorites" {
            applyIcon(UIImage(systemName: "star"), tintColor: .secondaryLabel)
        } else {
            applyIcon(UIImage(systemName: "folder"), tintColor: .secondaryLabel)
        }
    }
    
    func apply(bookmark: BookmarkSnapshot) {
        representedURL = bookmark.url
        faviconTask?.cancel()
        faviconTask = nil
        titleLabel.text = bookmark.title
        countLabel.text = nil
        countLabel.isHidden = true
        
        if let cachedImage = Self.faviconStore.cachedImage(for: bookmark.url) {
            applyIcon(cachedImage, tintColor: nil)
            return
        }
        
        applyIcon(UIImage(systemName: "globe"), tintColor: .secondaryLabel)
        let expectedURL = bookmark.url
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
                
                self.applyIcon(image ?? UIImage(systemName: "globe"), tintColor: image == nil ? .secondaryLabel : nil)
            }
        }
    }
    
    private func applyIcon(_ image: UIImage?, tintColor: UIColor?) {
        iconView.image = image
        iconView.tintColor = tintColor
    }
}
