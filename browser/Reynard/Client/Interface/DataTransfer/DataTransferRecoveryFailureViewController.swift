//
//  DataTransferRecoveryFailureViewController.swift
//  Reynard
//

import UIKit

final class DataTransferRecoveryFailureViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = NSLocalizedString("Import Failed", comment: "")

        let messageLabel = UILabel()
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        let recoveryMessage = NSLocalizedString(
            "Automatic recovery couldn’t finish. Your recovery files were kept.",
            comment: ""
        )
        let retryMessage = NSLocalizedString(
            "Reynard couldn’t finish the data transfer. Close and reopen Reynard to try again.",
            comment: ""
        )
        messageLabel.text = "\(recoveryMessage)\n\n\(retryMessage)"

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
