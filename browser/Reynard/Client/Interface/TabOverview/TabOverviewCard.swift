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
        static let closeButtonTouchTargetScale: CGFloat = 2
        static let closeButtonCornerRadius: CGFloat = 12
        static let closeButtonSymbolPointSize: CGFloat = 12
        static let closeButtonBackgroundAlpha: CGFloat = 0.6
        static let tabMetadataTopSpacing: CGFloat = 4
        static let tabMetadataHorizontalInset: CGFloat = 6
        static let tabMetadataHeight: CGFloat = 18
        static let tabMetadataItemSpacing: CGFloat = 4
        static let faviconSideLength: CGFloat = 16
        static let faviconCornerRadius: CGFloat = 3
        static let tabTitleMaximumWidthAdjustment: CGFloat = -24
        static let tabTitleFontSize: CGFloat = 14
        static let reorderLiftAnimationDuration: TimeInterval = 0.18
        static let swipeDismissMaximumFade: CGFloat = 0.35
        static let borderWidth: CGFloat = 0.5
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
    private(set) var tabID: UUID?
    
    private static let fallbackFaviconImage = UIImage(named: "reynard.globe")
    private(set) var reorderState: ReorderState = .resting
    private(set) var previewImage: UIImage?
    
    private let webpagePreviewShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = UX.webpagePreviewCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.shadowOpacity = UX.webpagePreviewRestingShadowOpacity
        view.layer.shadowRadius = UX.webpagePreviewRestingShadowRadius
        view.layer.shadowOffset = UX.webpagePreviewRestingShadowOffset
        view.layer.shadowColor = UIColor.black.cgColor
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
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor
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
    
    private let closeTabButton: TabOverviewCardCloseTabButton = {
        let button = TabOverviewCardCloseTabButton(type: .system)
        if #available(iOS 13.4, *) {
            button.isPointerInteractionEnabled = true
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.touchTargetScale = UX.closeButtonTouchTargetScale
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
        imageView.layer.cornerRadius = UX.faviconCornerRadius
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
        applyReorderState(animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        tabID = nil
        previewImage = nil
        webpagePreviewImageView.image = nil
        faviconImageView.image = Self.fallbackFaviconImage
        onClose = nil
        setTransitionState(.visible)
        setReorderState(.resting, animated: false)
        setSwipeOffset(0, progress: 0)
    }
    
    // MARK: - Content
    
    func configure(
        with tab: Tab,
        visiblePreviewCropRect: CGRect?
    ) {
        tabID = tab.id
        tabTitleLabel.text = tab.title.isEmpty ? NSLocalizedString("Homepage", comment: "") : tab.title
        previewImage = tab.thumbnail
        webpagePreviewImageView.image = visiblePreviewImage(
            from: tab.thumbnail,
            cropRect: visiblePreviewCropRect
        )
        faviconImageView.image = tab.favicon ?? Self.fallbackFaviconImage
    }
    
    private func visiblePreviewImage(
        from image: UIImage?,
        cropRect: CGRect?
    ) -> UIImage? {
        guard let image,
              let cropRect,
              image.size.width > 0,
              let cgImage = image.cgImage else {
            return image
        }
        
        let pixelBounds = CGRect(
            x: 0,
            y: 0,
            width: cgImage.width,
            height: cgImage.height
        )
        let pixelRect = CGRect(
            x: cropRect.minX * pixelBounds.width,
            y: cropRect.minY * pixelBounds.height,
            width: cropRect.width * pixelBounds.width,
            height: cropRect.height * pixelBounds.height
        ).intersection(pixelBounds).integral
        guard pixelRect.width > 1, pixelRect.height > 1,
              let croppedImage = cgImage.cropping(to: pixelRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Transition Geometry
    
    func webpagePreviewRegionFrame(in targetView: UIView) -> CGRect {
        webpagePreviewRegionView.convert(webpagePreviewRegionView.bounds, to: targetView)
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
    
    func makeTransitionSnapshot() -> UIView {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        
        let snapshotBounds = contentView.bounds.insetBy(
            dx: -UX.cardTransitionSnapshotOutset,
            dy: -UX.cardTransitionSnapshotOutset
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = traitCollection.displayScale
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: snapshotBounds.size, format: rendererFormat)
        webpagePreviewRegionView.isHidden = true
        let snapshotImage = renderer.image { context in
            context.cgContext.translateBy(x: UX.cardTransitionSnapshotOutset, y: UX.cardTransitionSnapshotOutset)
            contentView.layer.render(in: context.cgContext)
        }
        webpagePreviewRegionView.isHidden = false
        
        let snapshotImageView = UIImageView(image: snapshotImage)
        snapshotImageView.contentMode = .scaleToFill
        snapshotImageView.clipsToBounds = false
        return snapshotImageView
    }
    
    func makeCloseButtonTransitionSnapshot(
        in targetView: UIView,
        containerFrame: CGRect
    ) -> UIView {
        layoutIfNeeded()
        contentView.layoutIfNeeded()
        
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = traitCollection.displayScale
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: closeTabButton.bounds.size, format: rendererFormat)
        let snapshotImage = renderer.image { _ in
            closeTabButton.drawHierarchy(in: closeTabButton.bounds, afterScreenUpdates: true)
        }
        
        let snapshotView = UIView(frame: containerFrame)
        snapshotView.isUserInteractionEnabled = false
        let closeButtonSnapshotView = UIImageView(image: snapshotImage)
        closeButtonSnapshotView.frame = closeTabButton
            .convert(closeTabButton.bounds, to: targetView)
            .offsetBy(dx: -containerFrame.minX, dy: -containerFrame.minY)
        snapshotView.addSubview(closeButtonSnapshotView)
        return snapshotView
    }
    
    // MARK: - State Updates
    
    func setTransitionState(_ state: TransitionState) {
        contentView.alpha = state == .visible ? 1 : 0
    }
    
    func setPreviewSurfaceHidden(_ hidden: Bool) {
        webpagePreviewShadowView.isHidden = hidden
        webpagePreviewClippingView.isHidden = hidden
    }
    
    func setReorderState(_ state: ReorderState, animated: Bool) {
        reorderState = state
        applyReorderState(animated: animated)
    }
    
    func isCloseButton(at point: CGPoint) -> Bool {
        let pointInButton = convert(point, to: closeTabButton)
        return closeTabButton.containsHitTarget(pointInButton)
    }
    
    func setSwipeOffset(_ offset: CGFloat, progress: CGFloat) {
        transform = CGAffineTransform(translationX: offset, y: 0)
        contentView.alpha = 1 - (min(max(progress, 0), 1) * UX.swipeDismissMaximumFade)
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
        webpagePreviewRegionView.addSubview(closeTabButton)
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
    
    // MARK: - Actions
    
    @objc private func closeTabButtonTapped() {
        onClose?()
    }
}
