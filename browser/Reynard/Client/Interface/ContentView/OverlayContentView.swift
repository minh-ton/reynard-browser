//
//  OverlayContentView.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class OverlayContentView: UIView {
    enum Page: Hashable {
        case homepage
        case search
    }

    enum PresentationState: Equatable {
        case hidden
        case visible(Page)
    }

    // MARK: - State

    private(set) var presentation: PresentationState = .hidden
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

    // MARK: - Configuration

    private func configureAppearance() {
        backgroundColor = .clear
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

    // MARK: - State

    func setPresentation(_ presentation: PresentationState) {
        guard self.presentation != presentation else {
            return
        }

        self.presentation = presentation
        applyPresentation()
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
