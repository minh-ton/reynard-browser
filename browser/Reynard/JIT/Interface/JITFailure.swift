//
//  JITFailureViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/3/26.
//

import UIKit

final class JITFailureView: UIView {
    private let symbolImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let errorContainerView = UIView()
    private let errorScrollView = UIScrollView()
    private let errorLabel = UILabel()
    private var symbolHeightConstraint: NSLayoutConstraint?
    private var topContentPreferredWidthConstraint: NSLayoutConstraint?
    private var quitButtonPreferredWidthConstraint: NSLayoutConstraint?
    private var quitButtonMaxLandscapeWidthConstraint: NSLayoutConstraint?
    private var topRegionBottomToErrorConstraint: NSLayoutConstraint?
    private var topRegionBottomToButtonConstraint: NSLayoutConstraint?
    private var currentPhoneLandscapeState: Bool?
    let quitButton = UIButton(type: .system)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateError(code: Int, description: String) {
        errorLabel.text = "Error \(code): \(description)"
        errorScrollView.setContentOffset(.zero, animated: false)
    }
    
    func updateContent(title: String, message: String, buttonTitle: String) {
        titleLabel.text = title
        messageLabel.text = message
        quitButton.setTitle(buttonTitle, for: .normal)
    }
    
    func setErrorDetailsHidden(_ hidden: Bool) {
        errorContainerView.isHidden = hidden
    }
    
    func setSymbolHidden(_ hidden: Bool) {
        symbolImageView.isHidden = hidden
        symbolHeightConstraint?.constant = hidden ? 0 : 96
    }
    
    func updateForOrientation(isPhoneLandscape: Bool) {
        guard currentPhoneLandscapeState != isPhoneLandscape else {
            return
        }
        
        currentPhoneLandscapeState = isPhoneLandscape
        setSymbolHidden(isPhoneLandscape)
        quitButtonMaxLandscapeWidthConstraint?.isActive = isPhoneLandscape
        topRegionBottomToErrorConstraint?.isActive = !isPhoneLandscape
        topRegionBottomToButtonConstraint?.isActive = isPhoneLandscape
    }
    
    private func configureView() {
        backgroundColor = .systemBackground
        let horizontalInset: CGFloat = 24
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 96, weight: .regular)
        symbolImageView.image = UIImage(systemName: "bolt.slash", withConfiguration: symbolConfiguration)
        symbolImageView.tintColor = .label
        symbolImageView.contentMode = .scaleAspectFit
        symbolImageView.setContentHuggingPriority(.required, for: .vertical)
        symbolImageView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        titleLabel.text = nil
        titleLabel.textAlignment = .center
        let titlePointSize = UIFont.preferredFont(forTextStyle: .title1).pointSize
        let boldTitleFont = UIFont.systemFont(ofSize: titlePointSize, weight: .bold)
        titleLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: boldTitleFont)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        
        messageLabel.text = nil
        messageLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        
        errorContainerView.backgroundColor = .secondarySystemBackground
        errorContainerView.layer.cornerRadius = 12
        errorContainerView.layer.cornerCurve = .continuous
        errorContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        errorScrollView.translatesAutoresizingMaskIntoConstraints = false
        errorScrollView.showsHorizontalScrollIndicator = false
        errorScrollView.showsVerticalScrollIndicator = false
        errorScrollView.alwaysBounceHorizontal = true
        errorScrollView.alwaysBounceVertical = false
        
        errorLabel.textAlignment = .left
        errorLabel.numberOfLines = 1
        errorLabel.lineBreakMode = .byClipping
        errorLabel.textColor = .label
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.font = .monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .regular
        )
        
        quitButton.setTitle(nil, for: .normal)
        quitButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        quitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        quitButton.backgroundColor = .label
        quitButton.setTitleColor(.systemBackground, for: .normal)
        quitButton.layer.cornerRadius = 12
        quitButton.layer.cornerCurve = .continuous
        quitButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        quitButton.accessibilityTraits.insert(.button)
        
        errorScrollView.addSubview(errorLabel)
        errorContainerView.addSubview(errorScrollView)
        
        let topContentStackView = UIStackView(arrangedSubviews: [
            symbolImageView,
            titleLabel,
            messageLabel,
        ])
        topContentStackView.axis = .vertical
        topContentStackView.alignment = .fill
        topContentStackView.spacing = 20
        topContentStackView.setCustomSpacing(56, after: symbolImageView)
        topContentStackView.translatesAutoresizingMaskIntoConstraints = false
        
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        
        let topRegionGuide = UILayoutGuide()
        addLayoutGuide(topRegionGuide)
        addSubview(topContentStackView)
        addSubview(errorContainerView)
        addSubview(quitButton)
        
        symbolHeightConstraint = symbolImageView.heightAnchor.constraint(equalToConstant: 96)
        topContentPreferredWidthConstraint = topContentStackView.widthAnchor.constraint(equalTo: topRegionGuide.widthAnchor, constant: -2 * horizontalInset)
        topContentPreferredWidthConstraint?.priority = .defaultHigh
        quitButtonPreferredWidthConstraint = quitButton.widthAnchor.constraint(equalTo: widthAnchor, constant: -2 * horizontalInset)
        quitButtonPreferredWidthConstraint?.priority = .defaultHigh
        quitButtonMaxLandscapeWidthConstraint = quitButton.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        topRegionBottomToErrorConstraint = topRegionGuide.bottomAnchor.constraint(equalTo: errorContainerView.topAnchor, constant: -20)
        topRegionBottomToButtonConstraint = topRegionGuide.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -20)
        
        guard
            let symbolHeightConstraint,
            let topContentPreferredWidthConstraint,
            let quitButtonPreferredWidthConstraint,
            let quitButtonMaxLandscapeWidthConstraint,
            let topRegionBottomToErrorConstraint,
            let topRegionBottomToButtonConstraint
        else {
            return
        }
        
        NSLayoutConstraint.activate([
            topRegionGuide.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topRegionGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            topRegionGuide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            topRegionBottomToErrorConstraint,
            topRegionBottomToButtonConstraint,
            
            topContentStackView.centerXAnchor.constraint(equalTo: topRegionGuide.centerXAnchor),
            topContentStackView.centerYAnchor.constraint(equalTo: topRegionGuide.centerYAnchor),
            topContentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            topContentStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),
            topContentPreferredWidthConstraint,
            topContentStackView.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
            
            errorContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            errorContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            errorContainerView.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -16),
            
            quitButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            quitButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            quitButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),
            quitButtonPreferredWidthConstraint,
            quitButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            
            symbolHeightConstraint,
            quitButtonMaxLandscapeWidthConstraint,
            quitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            errorScrollView.topAnchor.constraint(equalTo: errorContainerView.topAnchor, constant: 14),
            errorScrollView.leadingAnchor.constraint(equalTo: errorContainerView.leadingAnchor, constant: 14),
            errorScrollView.trailingAnchor.constraint(equalTo: errorContainerView.trailingAnchor, constant: -14),
            errorScrollView.bottomAnchor.constraint(equalTo: errorContainerView.bottomAnchor, constant: -14),
            errorScrollView.heightAnchor.constraint(equalToConstant: 24),
            
            errorLabel.leadingAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.topAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.bottomAnchor),
            errorLabel.heightAnchor.constraint(equalTo: errorScrollView.frameLayoutGuide.heightAnchor),
            errorLabel.widthAnchor.constraint(greaterThanOrEqualTo: errorScrollView.frameLayoutGuide.widthAnchor),
        ])
        
        quitButtonMaxLandscapeWidthConstraint.isActive = false
        topRegionBottomToButtonConstraint.isActive = false
    }
}

final class JITFailureViewController: UIViewController {
    private let errorCode: Int
    private let errorDescriptionText: String
    private let showsErrorDetails: Bool
    private let titleText: String
    private let messageText: String
    private let actionButtonTitle: String
    private let onPrimaryAction: (() -> Void)?
    private let contentView = JITFailureView()
    
    init(
        errorCode: Int,
        errorDescription: String,
        showsErrorDetails: Bool = true,
        titleText: String,
        messageText: String,
        actionButtonTitle: String,
        onPrimaryAction: (() -> Void)? = nil
    ) {
        self.errorCode = errorCode
        self.errorDescriptionText = errorDescription.isEmpty ? "Unknown error." : errorDescription
        self.showsErrorDetails = showsErrorDetails
        self.titleText = titleText
        self.messageText = messageText
        self.actionButtonTitle = actionButtonTitle
        self.onPrimaryAction = onPrimaryAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = contentView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        contentView.updateContent(title: titleText, message: messageText, buttonTitle: actionButtonTitle)
        contentView.updateError(code: errorCode, description: errorDescriptionText)
        contentView.setErrorDetailsHidden(!showsErrorDetails)
        contentView.quitButton.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let isPhoneLandscape = traitCollection.userInterfaceIdiom == .phone && view.bounds.width > view.bounds.height
        contentView.updateForOrientation(isPhoneLandscape: isPhoneLandscape)
    }
    
    @objc private func handlePrimaryAction() {
        dismiss(animated: true) { [onPrimaryAction] in
            onPrimaryAction?()
        }
    }
}
