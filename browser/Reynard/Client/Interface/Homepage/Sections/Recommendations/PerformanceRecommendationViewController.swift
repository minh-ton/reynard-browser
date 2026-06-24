//
//  PerformanceRecommendationViewController.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import UIKit

protocol PerformanceRecommendationViewControllerDelegate: AnyObject {
    func performanceRecommendationViewControllerDidSelectSettings(_ controller: PerformanceRecommendationViewController)
    func performanceRecommendationViewController(_ controller: PerformanceRecommendationViewController, didSelectExternalURL url: URL)
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
    
    private enum PerformanceRecommendationLink {
        static let enableInAppJITGuide = URL(string: "https://github.com/minh-ton/reynard-browser#why-enable-jit")!
        static let installTrollStoreGuide = URL(string: "https://ios.cfw.guide/installing-trollstore/")!
        static let downloadTrollStoreBuild = {
            guard let updateFeedData = BrowserUpdates.shared.sourceData,
                  let updateFeed = try? JSONSerialization.jsonObject(with: updateFeedData) as? [String: Any],
                  let appEntries = updateFeed["apps"] as? [[String: Any]],
                  let appEntry = appEntries.first,
                  let versions = appEntry["versions"] as? [[String: Any]],
                  let latestEntry = versions.first,
                  let packageURLString = latestEntry["downloadURL"] as? String,
                  let packageURL = URL(string: packageURLString) else {
                return URL(string: "https://github.com/minh-ton/reynard-browser/releases/latest")!
            }
            
            return URL(string: packageURLString.replacingOccurrences(
                of: "Reynard.ipa",
                with: "Reynard-TrollStore.tipa"
            ))!
        }
    }
    
    private enum PerformanceRecommendationAction {
        case settings
        case openURL(URL)
    }
    
    private enum PerformanceRecommendationContent {
        case enableInAppJIT
        case installTrollStore
        
        var title: String {
            switch self {
            case .enableInAppJIT:
                return "Performance Recommendation"
            case .installTrollStore:
                return "Get Better Performance"
            }
        }
        
        var message: String {
            switch self {
            case .enableInAppJIT:
                return "Enable JIT to improve website performance and compatibility."
            case .installTrollStore:
                return "Your device supports TrollStore. Install the TrollStore version of Reynard to enable JIT automatically for improved website performance and compatibility."
            }
        }
        
        var primaryButtonTitle: String {
            switch self {
            case .enableInAppJIT:
                return "Learn More"
            case .installTrollStore:
                return "Install TrollStore"
            }
        }
        
        var secondaryButtonTitle: String {
            switch self {
            case .enableInAppJIT:
                return "Open Settings"
            case .installTrollStore:
                return "Download Reynard (.tipa)"
            }
        }
        
        var primaryAction: PerformanceRecommendationAction {
            switch self {
            case .enableInAppJIT:
                return .openURL(PerformanceRecommendationLink.enableInAppJITGuide)
            case .installTrollStore:
                return .openURL(PerformanceRecommendationLink.installTrollStoreGuide)
            }
        }
        
        var secondaryAction: PerformanceRecommendationAction {
            switch self {
            case .enableInAppJIT:
                return .settings
            case .installTrollStore:
                return .openURL(PerformanceRecommendationLink.downloadTrollStoreBuild())
            }
        }
    }
    
    weak var delegate: PerformanceRecommendationViewControllerDelegate?
    
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var displayedContent: PerformanceRecommendationContent?
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
    
    private lazy var primaryActionButton: UIButton = {
        return makeActionButton(
            title: "Learn More",
            imageName: "reynard.arrow.up.right",
            action: #selector(performPrimaryAction)
        )
    }()
    
    private lazy var secondaryActionButton: UIButton = {
        return makeActionButton(
            title: "Open Settings",
            imageName: "reynard.gearshape",
            action: #selector(performSecondaryAction)
        )
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
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
    
    // MARK: - Public API
    
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
    }
    
    private func configureHierarchy() {
        view.addSubview(cardView)
        cardView.addSubview(textStackView)
        
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(messageLabel)
        textStackView.addArrangedSubview(buttonStackView)
        textStackView.setCustomSpacing(UX.buttonStackTopSpacing, after: messageLabel)
        
        buttonStackView.addArrangedSubview(primaryActionButton)
        buttonStackView.addArrangedSubview(secondaryActionButton)
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
    
    @objc private func performPrimaryAction() {
        perform(displayedContent?.primaryAction)
    }
    
    @objc private func performSecondaryAction() {
        perform(displayedContent?.secondaryAction)
    }
    
    private func perform(_ action: PerformanceRecommendationAction?) {
        guard let action else {
            return
        }
        
        switch action {
        case .settings:
            delegate?.performanceRecommendationViewControllerDidSelectSettings(self)
        case let .openURL(url):
            delegate?.performanceRecommendationViewController(self, didSelectExternalURL: url)
        }
    }
    
    // MARK: - Layout
    
    private func updateContentInsets() {
        cardView.directionalLayoutMargins = contentInsets
    }
    
    private func updateRecommendationState() {
        guard let content = resolvedContent else {
            view.isHidden = true
            displayedContent = nil
            return
        }
        
        displayedContent = content
        updateDisplayedContent(content)
        updateActionButtonLayout()
        view.isHidden = false
    }
    
    private func updateDisplayedContent(_ content: PerformanceRecommendationContent) {
        titleLabel.text = content.title
        messageLabel.text = content.message
        primaryActionButton.setTitle(content.primaryButtonTitle, for: .normal)
        secondaryActionButton.setTitle(content.secondaryButtonTitle, for: .normal)
    }
    
    private func updateActionButtonLayout() {
        let availableButtonWidth = cardView.bounds.width - cardView.directionalLayoutMargins.leading - cardView.directionalLayoutMargins.trailing
        guard availableButtonWidth > 0 else {
            return
        }
        
        let requiredHorizontalButtonWidth = primaryActionButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        + secondaryActionButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
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
            return NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        case .embeddedWide, .detachedWide:
            return NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24)
        case .embeddedExpanded:
            return NSDirectionalEdgeInsets(top: 32, leading: 28, bottom: 32, trailing: 28)
        }
    }
    
    // MARK: - Helpers
    
    private var resolvedContent: PerformanceRecommendationContent? {
        if isPrivateBrowsing || contentMode.isDetached {
            return nil
        }
        
        if isiOS174OrNewer && !Prefs.JITSettings.isJITEnabled {
            return .enableInAppJIT
        }
        
        if shouldUseTrollStore {
            return .installTrollStore
        }
        
        return nil
    }
    
    private var isiOS174OrNewer: Bool {
        if #available(iOS 17.4, *) {
            return true
        }
        return false
    }
    
    private var shouldUseTrollStore: Bool {
        if #available(iOS 17.0, *) {
            if #unavailable(iOS 17.0.1) {
                return !getEntitlementValue("com.apple.private.security.no-sandbox")
            }
        }
        
        if #available(iOS 14.0, *) {
            if #unavailable(iOS 16.7) {
                return !getEntitlementValue("com.apple.private.security.no-sandbox")
            }
        }
        
        return false
    }
}
