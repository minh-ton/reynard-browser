//
//  PerformanceRecommendationViewController.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import UIKit

protocol PerformanceRecommendationViewControllerDelegate: AnyObject {
    func performanceRecommendationViewControllerDidSelectGuide(_ controller: PerformanceRecommendationViewController)
    func performanceRecommendationViewControllerDidSelectSettings(_ controller: PerformanceRecommendationViewController)
}

final class PerformanceRecommendationViewController: UIViewController, HomepageRecommendationViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let sectionBottomSpacing: CGFloat = 24
        static let cornerRadius: CGFloat = 17
        static let labelSpacing: CGFloat = 8
        static let buttonStackTopSpacing: CGFloat = 14
        static let buttonSpacing: CGFloat = 22
        static let buttonImageSpacing: CGFloat = 6
        static let actionIconSize: CGFloat = 15
        static let titleFontSize: CGFloat = 22
    }
    
    weak var delegate: PerformanceRecommendationViewControllerDelegate?
    
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var isPrivateBrowsing = false
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.cornerRadius
        view.clipsToBounds = true
        view.backgroundColor = .systemGray6
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
        label.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: UX.titleFontSize, weight: .bold)
        )
        label.text = "Performance Recommendation"
        label.textAlignment = .left
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Enable JIT to improve website performance and compatibility."
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let buttonStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.buttonSpacing
        return stackView
    }()
    
    private let buttonTrailingSpacerView: UIView = {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()
    
    private lazy var guideButton: UIButton = {
        return makeActionButton(
            title: "Learn More",
            imageName: "reynard.arrow.up.right",
            action: #selector(viewGuide)
        )
    }()
    
    private lazy var settingsButton: UIButton = {
        return makeActionButton(
            title: "Open Settings",
            imageName: "reynard.gearshape",
            action: #selector(openSettings)
        )
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        updateContentInsets()
        updateVisibility()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVisibility()
    }
    
    // MARK: - Public API
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        if isViewLoaded {
            updateContentInsets()
            updateVisibility()
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
        cardView.addSubview(textStackView)
        
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(messageLabel)
        textStackView.addArrangedSubview(buttonStackView)
        textStackView.setCustomSpacing(UX.buttonStackTopSpacing, after: messageLabel)
        
        buttonStackView.addArrangedSubview(guideButton)
        buttonStackView.addArrangedSubview(settingsButton)
        buttonStackView.addArrangedSubview(buttonTrailingSpacerView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.sectionBottomSpacing),
            
            textStackView.topAnchor.constraint(equalTo: cardView.layoutMarginsGuide.topAnchor),
            textStackView.leadingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.leadingAnchor),
            textStackView.trailingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.trailingAnchor),
            textStackView.bottomAnchor.constraint(equalTo: cardView.layoutMarginsGuide.bottomAnchor),
        ])
    }
    
    private func makeActionButton(title: String, imageName: String, action: Selector) -> UIButton {
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.actionIconSize, weight: .regular)
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(named: imageName, in: .main, with: configuration), for: .normal)
        button.tintColor = .label
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        button.semanticContentAttribute = .forceLeftToRight
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: UX.buttonImageSpacing, bottom: 0, right: -UX.buttonImageSpacing)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    // MARK: - Actions
    
    @objc private func viewGuide() {
        delegate?.performanceRecommendationViewControllerDidSelectGuide(self)
    }
    
    @objc private func openSettings() {
        delegate?.performanceRecommendationViewControllerDidSelectSettings(self)
    }
    
    // MARK: - Layout
    
    private func updateContentInsets() {
        cardView.directionalLayoutMargins = contentInsets
    }
    
    private func updateVisibility() {
        view.isHidden = isPrivateBrowsing
        || contentMode.isDetached
        || Prefs.JITSettings.isJITEnabled
        || getEntitlementValue("com.apple.private.security.no-sandbox")
    }
    
    private var contentInsets: NSDirectionalEdgeInsets {
        switch contentMode {
        case .embeddedNarrow, .detachedNarrow:
            return NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        case .embeddedWide, .detachedWide:
            return NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24)
        case .embeddedExpanded:
            return NSDirectionalEdgeInsets(top: 32, leading: 28, bottom: 32, trailing: 28)
        }
    }
}
