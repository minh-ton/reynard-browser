//
//  TabOverviewCard.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewCard: UICollectionViewCell {
    static let reuseIdentifier = "TabOverviewCard"
    
    private static let fallbackFavicon = UIImage(systemName: "globe")
    private let basePreviewInset: CGFloat = 1
    private let liftedPreviewInset: CGFloat = -4
    private let baseShadowOpacity: Float = 0.12
    private let liftedShadowOpacity: Float = 0.18
    private let baseShadowRadius: CGFloat = 8
    private let liftedShadowRadius: CGFloat = 12
    private let transitionSnapshotOutset: CGFloat = 18
    private let baseShadowOffset = CGSize(width: 0, height: 3)
    private let liftedShadowOffset = CGSize(width: 0, height: 6)
    
    var onClose: (() -> Void)?
    
    private let previewShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark ? UIColor.white.cgColor : UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        view.layer.masksToBounds = false
        return view
    }()
    
    private var previewShadowTopConstraint: NSLayoutConstraint!
    private var previewShadowLeadingConstraint: NSLayoutConstraint!
    private var previewShadowTrailingConstraint: NSLayoutConstraint!
    private var previewShadowBottomConstraint: NSLayoutConstraint!
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let previewContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private var previewContainerTopConstraint: NSLayoutConstraint!
    private var previewContainerLeadingConstraint: NSLayoutConstraint!
    private var previewContainerTrailingConstraint: NSLayoutConstraint!
    private var previewContainerBottomConstraint: NSLayoutConstraint!
    
    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .medium),
            forImageIn: .normal
        )
        button.backgroundColor = .systemGray.withAlphaComponent(0.6)
        button.tintColor = .white
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        return button
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private let faviconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let titleContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 4
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        clipsToBounds = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        
        contentView.addSubview(cardView)
        cardView.addSubview(previewShadowView)
        cardView.addSubview(previewContainerView)
        previewContainerView.addSubview(previewImageView)
        previewContainerView.addSubview(closeButton)
        contentView.addSubview(titleContainerView)
        titleContainerView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(faviconImageView)
        titleStackView.addArrangedSubview(titleLabel)
        
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        let cardTopConstraint = cardView.topAnchor.constraint(equalTo: contentView.topAnchor)
        let cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        
        previewShadowTopConstraint = previewShadowView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: basePreviewInset)
        previewShadowLeadingConstraint = previewShadowView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: basePreviewInset)
        previewShadowTrailingConstraint = previewShadowView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -basePreviewInset)
        previewShadowBottomConstraint = previewShadowView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -basePreviewInset)
        
        previewContainerTopConstraint = previewContainerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: basePreviewInset)
        previewContainerLeadingConstraint = previewContainerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: basePreviewInset)
        previewContainerTrailingConstraint = previewContainerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -basePreviewInset)
        previewContainerBottomConstraint = previewContainerView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -basePreviewInset)
        
        let previewImageTopConstraint = previewImageView.topAnchor.constraint(equalTo: previewContainerView.topAnchor)
        let previewImageLeadingConstraint = previewImageView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor)
        let previewImageTrailingConstraint = previewImageView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor)
        let previewImageBottomConstraint = previewImageView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor)
        
        let closeButtonTopConstraint = closeButton.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: 10)
        let closeButtonTrailingConstraint = closeButton.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: -10)
        let closeButtonWidthConstraint = closeButton.widthAnchor.constraint(equalToConstant: 24)
        let closeButtonHeightConstraint = closeButton.heightAnchor.constraint(equalToConstant: 24)
        
        let titleContainerTopConstraint = titleContainerView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 4)
        let titleContainerLeadingConstraint = titleContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6)
        let titleContainerTrailingConstraint = titleContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6)
        let titleContainerHeightConstraint = titleContainerView.heightAnchor.constraint(equalToConstant: 18)
        let titleContainerBottomConstraint = titleContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        
        let titleStackCenterXConstraint = titleStackView.centerXAnchor.constraint(equalTo: titleContainerView.centerXAnchor)
        let titleStackLeadingConstraint = titleStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleContainerView.leadingAnchor)
        let titleStackTrailingConstraint = titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: titleContainerView.trailingAnchor)
        let titleStackCenterYConstraint = titleStackView.centerYAnchor.constraint(equalTo: titleContainerView.centerYAnchor)
        
        let faviconWidthConstraint = faviconImageView.widthAnchor.constraint(equalToConstant: 16)
        let faviconHeightConstraint = faviconImageView.heightAnchor.constraint(equalToConstant: 16)
        let titleLabelWidthConstraint = titleLabel.widthAnchor.constraint(lessThanOrEqualTo: titleContainerView.widthAnchor, constant: -24)
        
        NSLayoutConstraint.activate([
            cardTopConstraint,
            cardLeadingConstraint,
            cardTrailingConstraint,
            previewShadowTopConstraint,
            previewShadowLeadingConstraint,
            previewShadowTrailingConstraint,
            previewShadowBottomConstraint,
            previewContainerTopConstraint,
            previewContainerLeadingConstraint,
            previewContainerTrailingConstraint,
            previewContainerBottomConstraint,
            previewImageTopConstraint,
            previewImageLeadingConstraint,
            previewImageTrailingConstraint,
            previewImageBottomConstraint,
            closeButtonTopConstraint,
            closeButtonTrailingConstraint,
            closeButtonWidthConstraint,
            closeButtonHeightConstraint,
            titleContainerTopConstraint,
            titleContainerLeadingConstraint,
            titleContainerTrailingConstraint,
            titleContainerHeightConstraint,
            titleContainerBottomConstraint,
            titleStackCenterXConstraint,
            titleStackLeadingConstraint,
            titleStackTrailingConstraint,
            titleStackCenterYConstraint,
            faviconWidthConstraint,
            faviconHeightConstraint,
            titleLabelWidthConstraint
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        previewImageView.image = nil
        faviconImageView.image = Self.fallbackFavicon
        onClose = nil
        contentView.alpha = 1
        previewShadowView.layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark ? UIColor.white.cgColor : UIColor.black.cgColor
        setReorderLifted(false, animated: false)
    }
    
    func configure(tab: Tab) {
        titleLabel.text = tab.title.isEmpty ? "Homepage" : tab.title
        previewImageView.image = tab.thumbnail
        faviconImageView.image = tab.favicon ?? Self.fallbackFavicon
    }
    
    var currentPreviewImage: UIImage? {
        previewImageView.image
    }
    
    func previewFrame(in targetView: UIView) -> CGRect {
        cardView.convert(cardView.bounds, to: targetView)
    }
    
    func previewSnapshotView() -> UIView? {
        cardView.snapshotView(afterScreenUpdates: false)
    }
    
    func transitionContentFrame(in targetView: UIView) -> CGRect {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        let snapshotBounds = contentView.bounds.insetBy(dx: -transitionSnapshotOutset, dy: -transitionSnapshotOutset)
        return contentView.convert(snapshotBounds, to: targetView)
    }
    
    func transitionPreviewImageFrame(in targetView: UIView) -> CGRect {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        return previewImageView.convert(previewImageView.bounds, to: targetView)
    }
    
    func transitionSnapshotView() -> UIView? {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        
        let snapshotBounds = contentView.bounds.insetBy(dx: -transitionSnapshotOutset, dy: -transitionSnapshotOutset)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: snapshotBounds.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: transitionSnapshotOutset, y: transitionSnapshotOutset)
            contentView.layer.render(in: context.cgContext)
        }
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = false
        return imageView
    }
    
    func setTransitionHidden(_ hidden: Bool) {
        contentView.alpha = hidden ? 0 : 1
    }
    
    func setReorderLifted(_ lifted: Bool, animated: Bool) {
        let inset = lifted ? liftedPreviewInset : basePreviewInset
        previewShadowTopConstraint.constant = inset
        previewShadowLeadingConstraint.constant = inset
        previewShadowTrailingConstraint.constant = -inset
        previewShadowBottomConstraint.constant = -inset
        previewContainerTopConstraint.constant = inset
        previewContainerLeadingConstraint.constant = inset
        previewContainerTrailingConstraint.constant = -inset
        previewContainerBottomConstraint.constant = -inset
        
        let shadowOpacity = lifted ? liftedShadowOpacity : baseShadowOpacity
        let shadowRadius = lifted ? liftedShadowRadius : baseShadowRadius
        let shadowOffset = lifted ? liftedShadowOffset : baseShadowOffset
        let animations = {
            self.contentView.layoutIfNeeded()
            self.previewShadowView.layer.shadowOpacity = shadowOpacity
            self.previewShadowView.layer.shadowRadius = shadowRadius
            self.previewShadowView.layer.shadowOffset = shadowOffset
        }
        
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: animations)
        } else {
            animations()
        }
    }
    
    func containsCloseButton(point: CGPoint) -> Bool {
        let pointInPreviewContainer = convert(point, to: previewContainerView)
        return closeButton.frame.contains(pointInPreviewContainer)
    }
    
    @objc private func closeTapped() {
        onClose?()
    }
}
