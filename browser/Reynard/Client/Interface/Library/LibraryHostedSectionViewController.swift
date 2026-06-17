//
//  LibraryHostedSectionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class LibraryHostedSectionViewController: UIViewController {
    // MARK: - State

    private let buildContentView: () -> UIView

    // MARK: - Lifecycle

    init(buildContentView: @escaping () -> UIView) {
        self.buildContentView = buildContentView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGray6
        installHostedView()
    }

    // MARK: - View Setup

    private func installHostedView() {
        let hostedView = buildContentView()

        hostedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
