//
//  TabOverviewCard.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewCard: UICollectionViewCell {
    private enum UX {
        static let webpagePreviewCornerRadius: CGFloat = 18
        static let webpagePreviewRestingInset: CGFloat = 1
        static let webpagePreviewLiftedInset: CGFloat = -4
        static let webpagePreviewRestingShadowOpacity: Float = 0.12
        static let webpagePreviewLiftedShadowOpacity: Float = 0.18
        static let webpagePreviewRestingShadowRadius: CGFloat = 8
        static let webpagePreviewLiftedShadowRadius: CGFloat = 12
        static let webpagePreviewRestingShadowOffset = CGSize(width: 0, height: 3)
        static let webpagePreviewLiftedShadowOffset = CGSize(width: 0, height: 6)
        static let cardTransitionSnapshotOutset: CGFloat = 18
        static let closeButtonTopInset: CGFloat = 10
        static let closeButtonTrailingInset: CGFloat = 10
        static let closeButtonSideLength: CGFloat = 24
        static let closeButtonCornerRadius: CGFloat = 12
        static let closeButtonSymbolPointSize: CGFloat = 12
        static let closeButtonBackgroundAlpha: CGFloat = 0.6
        static let tabMetadataTopSpacing: CGFloat = 4
        static let tabMetadataHorizontalInset: CGFloat = 6
        static let tabMetadataHeight: CGFloat = 18
        static let tabMetadataItemSpacing: CGFloat = 4
        static let faviconSideLength: CGFloat = 16
        static let tabTitleMaximumWidthAdjustment: CGFloat = -24
        static let tabTitleFontSize: CGFloat = 14
        static let reorderLiftAnimationDuration: TimeInterval = 0.18
    }
    
    enum TransitionState {
        case visible
        case hiddenForAnimation
    }
    
    enum ReorderState {
        case resting
        case lifted
    }
    
    static let reuseIdentifier = "TabOverviewCard"
    
    var onClose: (() -> Void)?
    
    private static let fallbackFaviconImage = UIImage(named: "reynard.globe")
    private(set) var transitionState: TransitionState = .visible
    private(set) var reorderState: ReorderState = .resting
    
    private let webpagePreviewShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = UX.webpagePreviewCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.shadowOpacity = UX.webpagePreviewRestingShadowOpacity
        view.layer.shadowRadius = UX.webpagePreviewRestingShadowRadius
        view.layer.shadowOffset = UX.webpagePreviewRestingShadowOffset
        view.layer.masksToBounds = false
        return view
    }()
    
    private let webpagePreviewRegionView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let webpagePreviewClippingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = UX.webpagePreviewCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private let webpagePreviewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let closeTabButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "reynard.xmark"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.closeButtonSymbolPointSize, weight: .medium),
            forImageIn: .normal
        )
        button.backgroundColor = .systemGray.withAlphaComponent(UX.closeButtonBackgroundAlpha)
        button.tintColor = .white
        button.layer.cornerRadius = UX.closeButtonCornerRadius
        button.layer.cornerCurve = .continuous
        return button
    }()
    
    private let tabTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: UX.tabTitleFontSize, weight: .medium)
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
    
    private let tabMetadataContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let tabMetadataStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.tabMetadataItemSpacing
        return stackView
    }()
    
    private var webpagePreviewShadowTopConstraint: NSLayoutConstraint!
    private var webpagePreviewShadowLeadingConstraint: NSLayoutConstraint!
    private var webpagePreviewShadowTrailingConstraint: NSLayoutConstraint!
    private var webpagePreviewShadowBottomConstraint: NSLayoutConstraint!
    private var webpagePreviewTopConstraint: NSLayoutConstraint!
    private var webpagePreviewLeadingConstraint: NSLayoutConstraint!
    private var webpagePreviewTrailingConstraint: NSLayoutConstraint!
    private var webpagePreviewBottomConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureActions()
        updateWebpagePreviewShadowColor()
        applyReorderState(animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        webpagePreviewImageView.image = nil
        faviconImageView.image = Self.fallbackFaviconImage
        onClose = nil
        updateWebpagePreviewShadowColor()
        setTransitionState(.visible)
        setReorderState(.resting, animated: false)
    }
    
    // MARK: - Content
    
    func configure(with tab: Tab) {
        tabTitleLabel.text = tab.title.isEmpty ? "Homepage" : tab.title
        webpagePreviewImageView.image = tab.thumbnail
        faviconImageView.image = tab.favicon ?? Self.fallbackFaviconImage
    }
    
    var previewImage: UIImage? {
        return webpagePreviewImageView.image
    }
    
    // MARK: - Transition Geometry
    
    func webpagePreviewRegionFrame(in targetView: UIView) -> CGRect {
        webpagePreviewRegionView.convert(webpagePreviewRegionView.bounds, to: targetView)
    }
    
    func makeWebpagePreviewRegionSnapshot() -> UIView? {
        webpagePreviewRegionView.snapshotView(afterScreenUpdates: false)
    }
    
    func transitionSnapshotFrame(in targetView: UIView) -> CGRect {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        let snapshotBounds = contentView.bounds.insetBy(
            dx: -UX.cardTransitionSnapshotOutset,
            dy: -UX.cardTransitionSnapshotOutset
        )
        return contentView.convert(snapshotBounds, to: targetView)
    }
    
    func webpagePreviewImageFrame(in targetView: UIView) -> CGRect {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        return webpagePreviewImageView.convert(webpagePreviewImageView.bounds, to: targetView)
    }
    
    func makeTransitionSnapshot() -> UIView? {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        
        let snapshotBounds = contentView.bounds.insetBy(
            dx: -UX.cardTransitionSnapshotOutset,
            dy: -UX.cardTransitionSnapshotOutset
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = UIScreen.main.scale
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: snapshotBounds.size, format: rendererFormat)
        let snapshotImage = renderer.image { context in
            context.cgContext.translateBy(x: UX.cardTransitionSnapshotOutset, y: UX.cardTransitionSnapshotOutset)
            contentView.layer.render(in: context.cgContext)
        }
        
        let snapshotImageView = UIImageView(image: snapshotImage)
        snapshotImageView.contentMode = .scaleToFill
        snapshotImageView.clipsToBounds = false
        return snapshotImageView
    }
    
    // MARK: - State Updates
    
    func setTransitionState(_ state: TransitionState) {
        transitionState = state
        contentView.alpha = state == .visible ? 1 : 0
    }
    
    func setReorderState(_ state: ReorderState, animated: Bool) {
        reorderState = state
        applyReorderState(animated: animated)
    }
    
    func isCloseButton(at point: CGPoint) -> Bool {
        let pointInPreview = convert(point, to: webpagePreviewClippingView)
        return closeTabButton.frame.contains(pointInPreview)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        clipsToBounds = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
    }
    
    private func configureHierarchy() {
        contentView.addSubview(webpagePreviewRegionView)
        webpagePreviewRegionView.addSubview(webpagePreviewShadowView)
        webpagePreviewRegionView.addSubview(webpagePreviewClippingView)
        webpagePreviewClippingView.addSubview(webpagePreviewImageView)
        webpagePreviewClippingView.addSubview(closeTabButton)
        contentView.addSubview(tabMetadataContainerView)
        tabMetadataContainerView.addSubview(tabMetadataStackView)
        tabMetadataStackView.addArrangedSubview(faviconImageView)
        tabMetadataStackView.addArrangedSubview(tabTitleLabel)
    }
    
    private func configureConstraints() {
        webpagePreviewShadowTopConstraint = webpagePreviewShadowView.topAnchor.constraint(equalTo: webpagePreviewRegionView.topAnchor)
        webpagePreviewShadowLeadingConstraint = webpagePreviewShadowView.leadingAnchor.constraint(equalTo: webpagePreviewRegionView.leadingAnchor)
        webpagePreviewShadowTrailingConstraint = webpagePreviewShadowView.trailingAnchor.constraint(equalTo: webpagePreviewRegionView.trailingAnchor)
        webpagePreviewShadowBottomConstraint = webpagePreviewShadowView.bottomAnchor.constraint(equalTo: webpagePreviewRegionView.bottomAnchor)
        webpagePreviewTopConstraint = webpagePreviewClippingView.topAnchor.constraint(equalTo: webpagePreviewRegionView.topAnchor)
        webpagePreviewLeadingConstraint = webpagePreviewClippingView.leadingAnchor.constraint(equalTo: webpagePreviewRegionView.leadingAnchor)
        webpagePreviewTrailingConstraint = webpagePreviewClippingView.trailingAnchor.constraint(equalTo: webpagePreviewRegionView.trailingAnchor)
        webpagePreviewBottomConstraint = webpagePreviewClippingView.bottomAnchor.constraint(equalTo: webpagePreviewRegionView.bottomAnchor)
        
        NSLayoutConstraint.activate([
            webpagePreviewRegionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webpagePreviewRegionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webpagePreviewRegionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webpagePreviewShadowTopConstraint,
            webpagePreviewShadowLeadingConstraint,
            webpagePreviewShadowTrailingConstraint,
            webpagePreviewShadowBottomConstraint,
            webpagePreviewTopConstraint,
            webpagePreviewLeadingConstraint,
            webpagePreviewTrailingConstraint,
            webpagePreviewBottomConstraint,
            webpagePreviewImageView.topAnchor.constraint(equalTo: webpagePreviewClippingView.topAnchor),
            webpagePreviewImageView.leadingAnchor.constraint(equalTo: webpagePreviewClippingView.leadingAnchor),
            webpagePreviewImageView.trailingAnchor.constraint(equalTo: webpagePreviewClippingView.trailingAnchor),
            webpagePreviewImageView.bottomAnchor.constraint(equalTo: webpagePreviewClippingView.bottomAnchor),
            closeTabButton.topAnchor.constraint(equalTo: webpagePreviewImageView.topAnchor, constant: UX.closeButtonTopInset),
            closeTabButton.trailingAnchor.constraint(equalTo: webpagePreviewImageView.trailingAnchor, constant: -UX.closeButtonTrailingInset),
            closeTabButton.widthAnchor.constraint(equalToConstant: UX.closeButtonSideLength),
            closeTabButton.heightAnchor.constraint(equalToConstant: UX.closeButtonSideLength),
            tabMetadataContainerView.topAnchor.constraint(equalTo: webpagePreviewRegionView.bottomAnchor, constant: UX.tabMetadataTopSpacing),
            tabMetadataContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.tabMetadataHorizontalInset),
            tabMetadataContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.tabMetadataHorizontalInset),
            tabMetadataContainerView.heightAnchor.constraint(equalToConstant: UX.tabMetadataHeight),
            tabMetadataContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tabMetadataStackView.centerXAnchor.constraint(equalTo: tabMetadataContainerView.centerXAnchor),
            tabMetadataStackView.leadingAnchor.constraint(greaterThanOrEqualTo: tabMetadataContainerView.leadingAnchor),
            tabMetadataStackView.trailingAnchor.constraint(lessThanOrEqualTo: tabMetadataContainerView.trailingAnchor),
            tabMetadataStackView.centerYAnchor.constraint(equalTo: tabMetadataContainerView.centerYAnchor),
            faviconImageView.widthAnchor.constraint(equalToConstant: UX.faviconSideLength),
            faviconImageView.heightAnchor.constraint(equalToConstant: UX.faviconSideLength),
            tabTitleLabel.widthAnchor.constraint(
                lessThanOrEqualTo: tabMetadataContainerView.widthAnchor,
                constant: UX.tabTitleMaximumWidthAdjustment
            ),
        ])
    }
    
    private func configureActions() {
        closeTabButton.addTarget(self, action: #selector(closeTabButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - State Rendering
    
    private func applyReorderState(animated: Bool) {
        let isLifted = reorderState == .lifted
        let previewInset = isLifted ? UX.webpagePreviewLiftedInset : UX.webpagePreviewRestingInset
        updateWebpagePreviewInsets(previewInset)
        
        let animations = {
            self.contentView.layoutIfNeeded()
            self.webpagePreviewShadowView.layer.shadowOpacity = isLifted
            ? UX.webpagePreviewLiftedShadowOpacity
            : UX.webpagePreviewRestingShadowOpacity
            self.webpagePreviewShadowView.layer.shadowRadius = isLifted
            ? UX.webpagePreviewLiftedShadowRadius
            : UX.webpagePreviewRestingShadowRadius
            self.webpagePreviewShadowView.layer.shadowOffset = isLifted
            ? UX.webpagePreviewLiftedShadowOffset
            : UX.webpagePreviewRestingShadowOffset
        }
        
        if animated {
            UIView.animate(
                withDuration: UX.reorderLiftAnimationDuration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: animations
            )
        } else {
            animations()
        }
    }
    
    private func updateWebpagePreviewInsets(_ inset: CGFloat) {
        webpagePreviewShadowTopConstraint.constant = inset
        webpagePreviewShadowLeadingConstraint.constant = inset
        webpagePreviewShadowTrailingConstraint.constant = -inset
        webpagePreviewShadowBottomConstraint.constant = -inset
        webpagePreviewTopConstraint.constant = inset
        webpagePreviewLeadingConstraint.constant = inset
        webpagePreviewTrailingConstraint.constant = -inset
        webpagePreviewBottomConstraint.constant = -inset
    }
    
    private func updateWebpagePreviewShadowColor() {
        webpagePreviewShadowView.layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark
        ? UIColor.white.cgColor
        : UIColor.black.cgColor
    }
    
    // MARK: - Actions
    
    @objc private func closeTabButtonTapped() {
        onClose?()
    }
}
