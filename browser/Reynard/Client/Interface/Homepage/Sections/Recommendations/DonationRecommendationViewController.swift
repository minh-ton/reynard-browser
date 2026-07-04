//
//  DonationRecommendationViewController.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import UIKit

final class DonationRecommendationViewController: UIViewController, HomepageRecommendationViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let sectionBottomSpacing: CGFloat = 24
        static let cornerRadius: CGFloat = 17
        static let borderWidth: CGFloat = 2
        static let labelSpacing: CGFloat = 8
        static let buttonStackTopSpacing: CGFloat = 14
        static let buttonSpacing: CGFloat = 22
        static let buttonImageSpacing: CGFloat = 6
        static let actionIconSize: CGFloat = 15
        static let titleFontSize: CGFloat = 22
        static let coffeeImageWidth: CGFloat = 55.9
        static let coffeeImageHeight: CGFloat = 80.6
        static let coffeeImageTopOffset: CGFloat = -30
        static let coffeeImageTrailingOffset: CGFloat = 2
        static let coffeeImageRotation: CGFloat = .pi / 9
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
    
    private enum DonationRecommendationLink {
        static let buyMeACoffee = URL(string: "https://buymeacoffee.com/hnimnot")!
    }
    
    weak var delegate: HomepageSectionDelegate?
    
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var isPrivateBrowsing = false
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.cornerRadius
        view.layer.borderColor = UIColor.systemYellow.cgColor
        view.layer.borderWidth = UX.borderWidth
        view.clipsToBounds = true
        view.backgroundColor = .systemGray6
        return view
    }()
    
    private let tintView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.08)
        view.isUserInteractionEnabled = false
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
        label.text = NSLocalizedString("Support The Project", comment: "")
        label.textAlignment = .left
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.text = NSLocalizedString("AboutDeveloperMessage", comment: "")
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private lazy var donateButton: UIButton = {
        return makeActionButton(
            title: NSLocalizedString("Buy Me a Coffee", comment: ""),
            imageName: "reynard.arrow.up.right",
            action: #selector(openDonationLink)
        )
    }()
    
    private lazy var notNowButton: UIButton = {
        return makeActionButton(
            title: NSLocalizedString("Not Now", comment: ""),
            imageName: "reynard.clock",
            action: #selector(postponeDonationRecommendation)
        )
    }()
    
    private let buttonTrailingSpacerView: UIView = {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()
    
    private let buttonStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.buttonSpacing
        return stackView
    }()
    
    private let coffeeImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "bmc"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.transform = CGAffineTransform(rotationAngle: UX.coffeeImageRotation)
        return imageView
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
    
    // MARK: - Configuration
    
    private func configureView() {
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    private func configureAppearance() {
        view.backgroundColor = .clear
        view.clipsToBounds = false
    }
    
    private func configureHierarchy() {
        view.addSubview(cardView)
        view.addSubview(coffeeImageView)
        
        cardView.addSubview(tintView)
        cardView.addSubview(textStackView)
        
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(messageLabel)
        textStackView.addArrangedSubview(buttonStackView)
        textStackView.setCustomSpacing(UX.buttonStackTopSpacing, after: messageLabel)
        
        buttonStackView.addArrangedSubview(donateButton)
        buttonStackView.addArrangedSubview(notNowButton)
        buttonStackView.addArrangedSubview(buttonTrailingSpacerView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.sectionBottomSpacing),
            
            tintView.topAnchor.constraint(equalTo: cardView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            
            textStackView.topAnchor.constraint(equalTo: cardView.layoutMarginsGuide.topAnchor),
            textStackView.leadingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.leadingAnchor),
            textStackView.trailingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.trailingAnchor),
            textStackView.bottomAnchor.constraint(equalTo: cardView.layoutMarginsGuide.bottomAnchor),
            
            coffeeImageView.widthAnchor.constraint(equalToConstant: UX.coffeeImageWidth),
            coffeeImageView.heightAnchor.constraint(equalToConstant: UX.coffeeImageHeight),
            coffeeImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: UX.coffeeImageTopOffset),
            coffeeImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: UX.coffeeImageTrailingOffset),
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
    
    @objc private func openDonationLink() {
        delegate?.homepageSection(self, didRequestOpenURL: DonationRecommendationLink.buyMeACoffee, disposition: .currentTab)
    }
    
    @objc private func postponeDonationRecommendation() {
        let multiplier = max(Prefs.HomepageSettings.donationRecommendationMultiplier, 1)
        Prefs.HomepageSettings.donationRecommendationShowTime = nextDonationRecommendationShowTime(months: multiplier)
        Prefs.HomepageSettings.donationRecommendationMultiplier = multiplier * 2
        updateRecommendationState()
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
        
        let requiredHorizontalButtonWidth = donateButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        + notNowButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        + UX.buttonSpacing
        
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
        if isPrivateBrowsing || contentMode.isDetached {
            return false
        }
        
        if PerformanceRecommendationViewController.isRecommendationShown(
            isPrivateBrowsing: isPrivateBrowsing,
            contentMode: contentMode
        ) {
            return false
        }
        
        if UpdateAvailableViewController.isRecommendationShown(
            isPrivateBrowsing: isPrivateBrowsing,
            contentMode: contentMode
        ) {
            return false
        }
        
        return Date() >= Prefs.HomepageSettings.donationRecommendationShowTime
    }
    
    private func nextDonationRecommendationShowTime(months: Int) -> Date {
        return Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date().addingTimeInterval(TimeInterval(months * 30 * 86_400))
    }
}
