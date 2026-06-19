//
//  ChromeOverlayContentView.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class ChromeOverlayContentView: UIView {
    private enum UX {
        static let presentationAnimationDuration: TimeInterval = 0.12
        static let maximumContentHeightRatio: CGFloat = 9.0 / 10.0
        static let modernCornerRadius: CGFloat = 36
        static let cornerRadius: CGFloat = 12
        static let backgroundAlpha: CGFloat = 0.28
        static let shadowOpacity: Float = 0.16
        static let shadowOffset = CGSize(width: 0, height: 8)
    }
    
    enum Page: Hashable {
        case homepage
        case search
    }
    
    enum PresentationState: Equatable {
        case hidden
        case visible(Page)
    }
    
    enum HeightMode: Equatable {
        case `default`
        case content
    }
    
    private(set) var presentation: PresentationState = .hidden
    private(set) var heightMode: HeightMode = .default
    private(set) var contentHeight: CGFloat = 0
    private(set) var availableContentHeight: CGFloat = 0
    private var pageControllers: [Page: UIViewController] = [:]
    
    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private let homepageView = UIView()
    private let searchSuggestionView = UIView()
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        applyPresentation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = overlayCornerRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        backgroundView.layer.cornerRadius = cornerRadius
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        
        updateShadowColor()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.cornerCurve = .continuous
        layer.shadowOpacity = UX.shadowOpacity
        layer.shadowOffset = UX.shadowOffset
        updateShadowColor()
        
        if #available(iOS 26.0, *) {
            layer.cornerRadius = UX.modernCornerRadius
            layer.shadowRadius = UX.modernCornerRadius
        } else {
            layer.cornerRadius = UX.cornerRadius
            layer.shadowRadius = UX.cornerRadius
        }
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        [homepageView, searchSuggestionView].forEach { contentView in
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentView.backgroundColor = .clear
            addSubview(contentView)
        }
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        [homepageView, searchSuggestionView].forEach { contentView in
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
    
    private func updateShadowColor() {
        layer.shadowColor = (traitCollection.userInterfaceStyle == .dark ? UIColor.white : .black).cgColor
    }
    
    private var overlayCornerRadius: CGFloat {
        if #available(iOS 26.0, *) {
            return UX.modernCornerRadius
        }
        
        return UX.cornerRadius
    }
    
    // MARK: - Presentation
    
    func setPresentation(
        _ presentation: PresentationState,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard self.presentation != presentation else {
            completion?()
            return
        }
        
        let previousPresentation = self.presentation
        self.presentation = presentation
        applyPresentation(
            previousPresentation: previousPresentation,
            animated: animated,
            completion: completion
        )
    }
    
    func setHeightMode(_ heightMode: HeightMode) {
        self.heightMode = heightMode
    }
    
    func setContentHeight(_ contentHeight: CGFloat) {
        self.contentHeight = max(0, contentHeight)
    }
    
    func setAvailableContentHeight(_ availableContentHeight: CGFloat) {
        self.availableContentHeight = max(0, availableContentHeight)
    }
    
    var resolvedHeight: CGFloat {
        let maximumHeight = availableContentHeight * UX.maximumContentHeightRatio
        switch heightMode {
        case .default:
            return maximumHeight
        case .content:
            return min(contentHeight, maximumHeight)
        }
    }
    
    private func applyPresentation() {
        applyPresentation(previousPresentation: nil, animated: false, completion: nil)
    }
    
    private func applyPresentation(
        previousPresentation: PresentationState?,
        animated: Bool,
        completion: (() -> Void)?
    ) {
        layer.removeAllAnimations()
        homepageView.isHidden = presentation != .visible(.homepage)
        searchSuggestionView.isHidden = presentation != .visible(.search)
        
        switch presentation {
        case .hidden:
            let finish = { [weak self] in
                guard let self else { return }
                self.isHidden = true
                self.removeController(for: self.visiblePage(from: previousPresentation))
                completion?()
            }
            
            guard animated else {
                alpha = 0
                finish()
                return
            }
            
            UIView.animate(withDuration: UX.presentationAnimationDuration, animations: {
                self.alpha = 0
            }) { _ in
                finish()
            }
        case .visible:
            isHidden = false
            let animations = {
                self.alpha = 1
            }
            
            guard animated else {
                animations()
                completion?()
                return
            }
            
            alpha = 0
            UIView.animate(withDuration: UX.presentationAnimationDuration, animations: animations) { _ in
                completion?()
            }
        }
    }
    
    // MARK: - Hosted Content
    
    func setController(_ viewController: UIViewController, for page: Page, in parentViewController: UIViewController) {
        if pageControllers[page] === viewController {
            return
        }
        
        removeController(for: page)
        detachIfNeeded(viewController)
        
        let containerView = containerView(for: page)
        parentViewController.addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        viewController.didMove(toParent: parentViewController)
        pageControllers[page] = viewController
    }
    
    func removeController(for page: Page) {
        removeController(for: Optional(page))
    }
    
    private func removeController(for page: Page?) {
        guard let page else {
            return
        }
        
        guard let viewController = pageControllers.removeValue(forKey: page) else {
            return
        }
        
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }
    
    private func detachIfNeeded(_ viewController: UIViewController) {
        guard viewController.parent != nil else {
            return
        }
        
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }
    
    private func containerView(for page: Page) -> UIView {
        switch page {
        case .homepage:
            return homepageView
        case .search:
            return searchSuggestionView
        }
    }
    
    private func visiblePage(from presentation: PresentationState?) -> Page? {
        guard case let .visible(page) = presentation else {
            return nil
        }
        
        return page
    }
}
