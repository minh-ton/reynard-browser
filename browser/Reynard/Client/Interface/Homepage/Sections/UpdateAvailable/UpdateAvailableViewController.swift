//
//  UpdateAvailableViewController.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import UIKit

final class UpdateAvailableViewController: UIViewController, HomepageRecommendationViewController {
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
    
    weak var delegate: HomepageSectionDelegate?
    
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
        label.text = NSLocalizedString("Update Available", comment: "")
        label.textAlignment = .left
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.text = NSLocalizedString("A new version of Reynard Browser is available. Open Settings to update.", comment: "")
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
    
    private lazy var settingsButton: UIButton = {
        return makeActionButton(
            title: NSLocalizedString("Open Settings", comment: ""),
            imageName: "reynard.gearshape",
            action: #selector(openSettings)
        )
    }()
    
    // MARK: - Lifecycle
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observeUpdates()
        configureView()
        updateContentInsets()
        updateRecommendationState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateRecommendationState()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateActionButtonLayout()
    }
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        if isViewLoaded {
            updateContentInsets()
            updateRecommendationState()
            updateActionButtonLayout()
        }
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        if isViewLoaded {
            updateRecommendationState()
        }
    }
    
    static func isRecommendationShown(isPrivateBrowsing: Bool, contentMode: HomepageContentMode) -> Bool {
        guard Prefs.HomepageSettings.showsNewUpdates else {
            return false
        }
        
        if isPrivateBrowsing || contentMode.isDetached {
            return false
        }
        
        if PerformanceRecommendationViewController.isRecommendationShown(
            isPrivateBrowsing: isPrivateBrowsing,
            contentMode: contentMode
        ) {
            return false
        }
        
        return BrowserUpdates.shared.hasUpdate
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
    
    private func observeUpdates() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appUpdateAvailable),
            name: .appUpdateAvailable,
            object: nil
        )
    }
    
    // MARK: - Actions
    
    @objc private func openSettings() {
        delegate?.homepageSectionDidSelectSettings(self)
    }
    
    @objc private func appUpdateAvailable() {
        updateRecommendationState()
    }
    
    // MARK: - Layout
    
    private func updateContentInsets() {
        cardView.directionalLayoutMargins = contentInsets
    }
    
    private func updateRecommendationState() {
        view.isHidden = !isRecommendationShown
    }
    
    private func updateActionButtonLayout() {
        let availableButtonWidth = cardView.bounds.width - cardView.directionalLayoutMargins.leading - cardView.directionalLayoutMargins.trailing
        guard availableButtonWidth > 0 else {
            return
        }
        
        let requiredHorizontalButtonWidth = settingsButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        
        let usesVerticalButtons = requiredHorizontalButtonWidth > availableButtonWidth
        buttonStackView.axis = usesVerticalButtons ? .vertical : .horizontal
        buttonStackView.alignment = usesVerticalButtons ? .fill : .center
        buttonStackView.spacing = usesVerticalButtons ? UX.labelSpacing : UX.buttonSpacing
        buttonTrailingSpacerView.isHidden = usesVerticalButtons
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
    
    // MARK: - Helpers
    
    private var isRecommendationShown: Bool {
        return Self.isRecommendationShown(isPrivateBrowsing: isPrivateBrowsing, contentMode: contentMode)
    }
}
