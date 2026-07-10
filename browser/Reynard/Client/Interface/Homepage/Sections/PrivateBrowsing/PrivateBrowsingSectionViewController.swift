//
//  PrivateBrowsingSectionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/6/26.
//

import UIKit

final class PrivateBrowsingSectionViewController: UIViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let sectionBottomSpacing: CGFloat = 24
        static let cornerRadius: CGFloat = 17
        static let titleFontSize: CGFloat = 28
        static let messageFontSize: CGFloat = 17
        static let labelSpacing: CGFloat = 10
        static let maximumContentWidth: CGFloat = 580
        static let narrowContentTopInset: CGFloat = 24
        static let narrowContentHorizontalInset: CGFloat = 20
        static let narrowContentBottomInset: CGFloat = 24
        static let wideContentTopInset: CGFloat = 28
        static let wideContentHorizontalInset: CGFloat = 24
        static let wideContentBottomInset: CGFloat = 28
        static let expandedContentTopInset: CGFloat = 32
        static let expandedContentHorizontalInset: CGFloat = 28
        static let expandedContentBottomInset: CGFloat = 32
    }
    
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var isPrivateBrowsing = false
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.cornerRadius
        view.clipsToBounds = true
        view.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .systemGray6 : UIColor.black.withAlphaComponent(0.7)
        }
        return view
    }()
    
    private let textContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let textStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = UX.labelSpacing
        return stackView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: .systemFont(ofSize: UX.titleFontSize, weight: .bold)
        )
        label.text = "Private Browsing"
        label.textAlignment = .center
        label.textColor = .white
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: UX.messageFontSize, weight: .regular)
        )
        label.text = "After you close a tab, Reynard won’t remember any of your browsing history or cookies. However, downloads and new bookmarks will be saved."
        label.textAlignment = .center
        label.textColor = UIColor.white.withAlphaComponent(0.72)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        updateContentInsets()
        updateVisibility()
    }
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        if isViewLoaded {
            updateContentInsets()
        }
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        if isViewLoaded {
            updateVisibility()
        }
    }
    
    // MARK: - Configuration
    
    private func configureView() {
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    private func configureAppearance() {
        view.backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        view.addSubview(cardView)
        cardView.addSubview(textContainerView)
        textContainerView.addSubview(textStackView)
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(messageLabel)
    }
    
    private func configureConstraints() {
        let preferredContentWidthConstraint = textContainerView.widthAnchor.constraint(
            equalTo: cardView.layoutMarginsGuide.widthAnchor
        )
        preferredContentWidthConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.sectionBottomSpacing),
            
            textContainerView.topAnchor.constraint(equalTo: cardView.layoutMarginsGuide.topAnchor),
            textContainerView.bottomAnchor.constraint(equalTo: cardView.layoutMarginsGuide.bottomAnchor),
            textContainerView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            textContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: cardView.layoutMarginsGuide.leadingAnchor),
            textContainerView.trailingAnchor.constraint(lessThanOrEqualTo: cardView.layoutMarginsGuide.trailingAnchor),
            textContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumContentWidth),
            preferredContentWidthConstraint,
            
            textStackView.topAnchor.constraint(equalTo: textContainerView.topAnchor),
            textStackView.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
            textStackView.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
            textStackView.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor),
        ])
    }
    
    // MARK: - Layout
    
    private func updateContentInsets() {
        cardView.directionalLayoutMargins = contentInsets
    }
    
    private func updateVisibility() {
        view.isHidden = !isPrivateBrowsing
    }
    
    private var contentInsets: NSDirectionalEdgeInsets {
        switch contentMode {
        case .embeddedNarrow, .detachedNarrow:
            return NSDirectionalEdgeInsets(
                top: UX.narrowContentTopInset,
                leading: UX.narrowContentHorizontalInset,
                bottom: UX.narrowContentBottomInset,
                trailing: UX.narrowContentHorizontalInset
            )
        case .embeddedWide, .detachedWide:
            return NSDirectionalEdgeInsets(
                top: UX.wideContentTopInset,
                leading: UX.wideContentHorizontalInset,
                bottom: UX.wideContentBottomInset,
                trailing: UX.wideContentHorizontalInset
            )
        case .embeddedExpanded:
            return NSDirectionalEdgeInsets(
                top: UX.expandedContentTopInset,
                leading: UX.expandedContentHorizontalInset,
                bottom: UX.expandedContentBottomInset,
                trailing: UX.expandedContentHorizontalInset
            )
        }
    }
}
