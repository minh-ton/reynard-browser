//
//  SidebarActionCell.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarActionCell: UICollectionViewCell {
    private enum UX {
        static let iconLeadingInset: CGFloat = 16
        static let iconSize: CGFloat = 18
        static let titleLeadingSpacing: CGFloat = 12
        static let titleTrailingInset: CGFloat = 12
    }
    
    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .label
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(title: String, symbolName: String) {
        titleLabel.text = title
        iconView.image = UIImage(named: symbolName)
    }
    
    private func configureAppearance() {
        contentView.backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.iconLeadingInset),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: UX.titleLeadingSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.titleTrailingInset),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}
