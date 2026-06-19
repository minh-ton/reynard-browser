//
//  TabBarCell.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabBarCell: UICollectionViewCell {
    private enum UX {
        static let expandedTabMinimumWidth: CGFloat = 220
        static let collapsedTabMinimumWidth: CGFloat = 96
        static let tabTitleFontSize: CGFloat = 14
        static let tabTitleSpacing: CGFloat = 6
        static let tabFaviconSideLength: CGFloat = 16
        static let tabCloseButtonSideLength: CGFloat = 22
        static let tabCloseButtonTrailingInset: CGFloat = 6
        static let tabCloseButtonSymbolPointSize: CGFloat = 14
        static let expandedTabContentLeadingInset: CGFloat = 10
        static let expandedTabContentTrailingInset: CGFloat = 34
        static let collapsedTabContentHorizontalInset: CGFloat = 8
        static let expandedTabTitleWidthInset: CGFloat = 58
        static let tabSeparatorWidth: CGFloat = 2 / UIScreen.main.scale
    }
    
    enum LayoutMode {
        case expanded
        case faviconOnly
    }
    
    static let reuseIdentifier = "TabBarCell"
    private static let minimumVisibleTabTitle = "WWWWW"
    
    static var expandedMinimumWidth: CGFloat {
        return UX.expandedTabMinimumWidth
    }
    
    static var collapsedMinimumWidth: CGFloat {
        return UX.collapsedTabMinimumWidth
    }
    
    private static let fallbackFavicon = UIImage(named: "reynard.globe")
    
    var closeHandler: (() -> Void)?
    
    private let faviconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: UX.tabTitleFontSize, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.textAlignment = .center
        return label
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "reynard.x.square.fill"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.tabCloseButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = .secondaryLabel
        button.isHidden = true
        return button
    }()
    
    private let trailingSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()
    
    private let titleStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.tabTitleSpacing
        return stackView
    }()
    
    private var expandedTrailingConstraint: NSLayoutConstraint!
    private var collapsedTrailingConstraint: NSLayoutConstraint!
    private var expandedLeadingConstraint: NSLayoutConstraint!
    private var collapsedLeadingConstraint: NSLayoutConstraint!
    private var expandedTitleWidthConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureContentPriorities()
        configureActions()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        faviconView.image = Self.fallbackFavicon
        titleLabel.isHidden = false
        titleStack.spacing = UX.tabTitleSpacing
        expandedLeadingConstraint.isActive = true
        collapsedLeadingConstraint.isActive = false
        expandedTrailingConstraint.isActive = true
        collapsedTrailingConstraint.isActive = false
        expandedTitleWidthConstraint.isActive = true
        closeHandler = nil
    }
    
    // MARK: - Configuration
    
    func configure(tab: Tab, isSelected: Bool, layoutMode: LayoutMode, cellWidth: CGFloat) {
        let displayTitle = tab.title.isEmpty ? "Homepage" : tab.title
        titleLabel.text = displayTitle
        faviconView.image = tab.favicon ?? Self.fallbackFavicon
        contentView.backgroundColor = isSelected ? .systemGray6 : .systemGray5
        titleLabel.textColor = isSelected ? .label : .secondaryLabel
        faviconView.tintColor = isSelected ? .label : .secondaryLabel
        let minimumVisibleTitle = Self.minimumVisibleTabTitle as NSString
        let minimumTitleWidth = minimumVisibleTitle.size(withAttributes: [.font: titleLabel.font as Any]).width
        let availableTitleWidth = cellWidth - UX.expandedTabTitleWidthInset
        let isTooNarrowForTitle = availableTitleWidth < minimumTitleWidth
        let isCollapsed = layoutMode == .faviconOnly || isTooNarrowForTitle
        
        titleLabel.isHidden = isCollapsed
        titleStack.spacing = isCollapsed ? 0 : UX.tabTitleSpacing
        expandedLeadingConstraint.isActive = !isCollapsed
        collapsedLeadingConstraint.isActive = isCollapsed
        expandedTrailingConstraint.isActive = !isCollapsed
        collapsedTrailingConstraint.isActive = isCollapsed
        expandedTitleWidthConstraint.isActive = !isCollapsed
        closeButton.isHidden = isCollapsed || !isSelected
        trailingSeparator.isHidden = isSelected
    }
    
    func containsCloseButton(at point: CGPoint) -> Bool {
        guard !closeButton.isHidden else {
            return false
        }
        
        let pointInContentView = convert(point, to: contentView)
        return closeButton.frame.contains(pointInContentView)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        contentView.layer.cornerRadius = 0
    }
    
    private func configureHierarchy() {
        contentView.addSubview(titleStack)
        titleStack.addArrangedSubview(faviconView)
        titleStack.addArrangedSubview(titleLabel)
        contentView.addSubview(closeButton)
        contentView.addSubview(trailingSeparator)
    }
    
    private func configureContentPriorities() {
        faviconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        faviconView.setContentCompressionResistancePriority(.required, for: .vertical)
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
    }
    
    private func configureActions() {
        closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
    }
    
    private func configureConstraints() {
        expandedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -UX.expandedTabContentTrailingInset)
        collapsedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -UX.collapsedTabContentHorizontalInset)
        expandedLeadingConstraint = titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: UX.expandedTabContentLeadingInset)
        collapsedLeadingConstraint = titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: UX.collapsedTabContentHorizontalInset)
        expandedTitleWidthConstraint = titleLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -UX.expandedTabTitleWidthInset)
        
        NSLayoutConstraint.activate([
            titleStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            expandedLeadingConstraint,
            expandedTrailingConstraint,
            
            faviconView.widthAnchor.constraint(equalToConstant: UX.tabFaviconSideLength),
            faviconView.heightAnchor.constraint(equalToConstant: UX.tabFaviconSideLength),
            
            expandedTitleWidthConstraint,
            
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.tabCloseButtonTrailingInset),
            closeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
            closeButton.heightAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
            
            trailingSeparator.topAnchor.constraint(equalTo: contentView.topAnchor),
            trailingSeparator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            trailingSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: UX.tabSeparatorWidth),
        ])
    }
    
    // MARK: - Actions
    
    @objc private func handleCloseTap() {
        closeHandler?()
    }
}
