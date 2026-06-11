//
//  ChromeOverlayContentView.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class ChromeOverlayContentView: UIView {
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

    // MARK: - State

    private(set) var presentation: PresentationState = .hidden
    private(set) var heightMode: HeightMode = .default
    private(set) var contentHeight: CGFloat = 0
    private(set) var availableContentHeight: CGFloat = 0
    private var pageControllers: [Page: UIViewController] = [:]

    // MARK: - Views

    private let homepageView = UIView()
    private let searchView = UIView()

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
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 24).cgPath
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
        layer.shadowOpacity = 0.16
        layer.shadowOffset = CGSize(width: 0, height: 8)
        updateShadowColor()

        if #available(iOS 26.0, *) {
            layer.cornerRadius = 36
            layer.shadowRadius = 36
        } else {
            layer.cornerRadius = 12
            layer.shadowRadius = 12
        }
    }

    private func configureHierarchy() {
        [homepageView, searchView].forEach { contentView in
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentView.backgroundColor = .clear
            addSubview(contentView)
        }
    }

    private func configureConstraints() {
        [homepageView, searchView].forEach { contentView in
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

    // MARK: - State

    func setPresentation(_ presentation: PresentationState) {
        guard self.presentation != presentation else {
            return
        }

        self.presentation = presentation
        applyPresentation()
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
        let maximumHeight = availableContentHeight * (9.0 / 10.0)
        switch heightMode {
        case .default:
            return maximumHeight
        case .content:
            return min(contentHeight, maximumHeight)
        }
    }

    private func applyPresentation() {
        isHidden = presentation == .hidden
        homepageView.isHidden = presentation != .visible(.homepage)
        searchView.isHidden = presentation != .visible(.search)
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
            return searchView
        }
    }
}
