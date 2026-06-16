//
//  SidebarHostedSectionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarHostedSectionViewController: UIViewController {
    // MARK: - State

    private let hostedView: UIView

    // MARK: - Lifecycle

    init(hostedView: UIView) {
        self.hostedView = hostedView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }

    // MARK: - View Setup

    private func configureAppearance() {
        view.backgroundColor = .systemGray6
    }

    private func configureHierarchy() {
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostedView)
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}
