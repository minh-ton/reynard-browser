//
//  BookmarkFolderRowCell.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class BookmarkFolderRowCell: UITableViewCell {
    private enum UX {
        static let hierarchyIndentWidth: CGFloat = 28
        static let iconSize: CGFloat = 24
        static let titleLeadingSpacing: CGFloat = 16
        static let titleVerticalInset: CGFloat = 10
        static let separatorTitleOffset: CGFloat = 40
    }
    
    private var hierarchyDepth = 0
    
    private var folderIconLeadingConstraint: NSLayoutConstraint?
    
    private let folderIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        return imageView
    }()
    
    private let folderTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        tintColor = .systemBlue
        
        contentView.addSubview(folderIconView)
        contentView.addSubview(folderTitleLabel)
        
        let folderIconLeadingConstraint = folderIconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        self.folderIconLeadingConstraint = folderIconLeadingConstraint
        
        NSLayoutConstraint.activate([
            folderIconLeadingConstraint,
            folderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderIconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            folderIconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            folderTitleLabel.leadingAnchor.constraint(equalTo: folderIconView.trailingAnchor, constant: UX.titleLeadingSpacing),
            folderTitleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            folderTitleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderTitleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.titleVerticalInset),
            folderTitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.titleVerticalInset),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let titleLeading = contentView.layoutMargins.left + CGFloat(hierarchyDepth) * UX.hierarchyIndentWidth + UX.separatorTitleOffset
        separatorInset = UIEdgeInsets(
            top: separatorInset.top,
            left: titleLeading,
            bottom: separatorInset.bottom,
            right: contentView.layoutMargins.right
        )
    }
    
    func configure(folder: BookmarkFolderSnapshot, depth: Int, isSelected: Bool) {
        hierarchyDepth = depth
        folderTitleLabel.text = folder.title
        folderIconLeadingConstraint?.constant = CGFloat(depth) * UX.hierarchyIndentWidth
        folderIconView.tintColor = isSelected ? .systemBlue : .secondaryLabel
        
        if folder.parentGUID == nil {
            folderIconView.image = UIImage(named: "reynard.book")?.withRenderingMode(.alwaysTemplate)
        } else if folder.isProtected && folder.title == "Favorites" {
            folderIconView.image = UIImage(named: "reynard.star")?.withRenderingMode(.alwaysTemplate)
        } else {
            folderIconView.image = UIImage(named: "reynard.folder")?.withRenderingMode(.alwaysTemplate)
        }
    }
}
