//
//  ToolBar.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import UIKit

protocol ToolBarDelegate: AnyObject {
    func backButtonClicked()
    func forwardButtonClicked()
    func reloadButtonClicked()
    func stopButtonClicked()
}

final class ToolBar: UIView {
    weak var toolbarDelegate: ToolBarDelegate?

    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadStopButton = UIButton(type: .system)
    private var isLoading = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .systemBackground

        backButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        reloadStopButton.translatesAutoresizingMaskIntoConstraints = false

        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        forwardButton.setImage(UIImage(systemName: "chevron.forward"), for: .normal)
        reloadStopButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)

        backButton.addTarget(self, action: #selector(backButtonClicked), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardButtonClicked), for: .touchUpInside)
        reloadStopButton.addTarget(self, action: #selector(reloadStopButtonClicked), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadStopButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.spacing = 16

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateReloadStopButton(isLoading: Bool) {
        guard isLoading != self.isLoading else { return }

        reloadStopButton.setImage(
            isLoading ? UIImage(systemName: "xmark") : UIImage(systemName: "arrow.clockwise"),
            for: .normal
        )
        self.isLoading = isLoading
    }

    func updateBackButton(canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardButton(canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    @objc private func reloadStopButtonClicked() {
        if isLoading {
            stopButtonClicked()
        } else {
            reloadButtonClicked()
        }
    }

    @objc func backButtonClicked() {
        toolbarDelegate?.backButtonClicked()
    }

    @objc func forwardButtonClicked() {
        toolbarDelegate?.forwardButtonClicked()
    }

    @objc func reloadButtonClicked() {
        toolbarDelegate?.reloadButtonClicked()
    }

    @objc func stopButtonClicked() {
        toolbarDelegate?.stopButtonClicked()
    }
}
