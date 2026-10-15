//
//  SyncDebugLogViewController.swift
//  Reynard
//
//  Shows the Mozilla account / Sync debug log so sign-in problems can be
//  reported. The log never contains tokens, codes or passwords.
//

import UIKit

final class SyncDebugLogViewController: UIViewController {
    private let textView = UITextView()

    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Sync Debug Log", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: NSLocalizedString("Share", comment: ""),
                style: .plain,
                target: self,
                action: #selector(shareLog)
            ),
            UIBarButtonItem(
                title: NSLocalizedString("Clear", comment: ""),
                style: .plain,
                target: self,
                action: #selector(clearLog)
            ),
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        textView.text = FxADebugLog.shared.contents()
        let end = NSRange(location: max(0, (textView.text as NSString).length - 1), length: 1)
        textView.scrollRangeToVisible(end)
    }

    @objc private func shareLog() {
        let controller = UIActivityViewController(activityItems: [FxADebugLog.shared.contents()], applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(controller, animated: true)
    }

    @objc private func clearLog() {
        FxADebugLog.shared.clear()
        reload()
    }
}
