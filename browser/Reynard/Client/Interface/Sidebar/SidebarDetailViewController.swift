//
//  SidebarDetailViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarDetailViewController: UIViewController {
    private let contentController: UIViewController
    private let detailTitle: String
    
    init(title: String, contentViewController: UIViewController) {
        self.detailTitle = title
        self.contentController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTitle()
        configureHierarchy()
        configureConstraints()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.leftBarButtonItem = nil
    }
    
    private func configureTitle() {
        title = detailTitle
    }
    
    private func configureHierarchy() {
        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)
        contentController.didMove(toParent: self)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
