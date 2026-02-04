//
//  ReynardViewController.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//


import UIKit
import GeckoWrapper

class ReynardViewController: UIViewController, UITextFieldDelegate {
    private var geckoView: GeckoView!
    private var geckoSession: GeckoSession!
    private let topBar = UIView()
    private let bottomBar = UIView()
    private let urlField = UITextField()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        urlField.translatesAutoresizingMaskIntoConstraints = false

        topBar.backgroundColor = .systemBackground
        bottomBar.backgroundColor = .systemBackground

        urlField.borderStyle = .roundedRect
        urlField.placeholder = "Enter URL"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.textContentType = .URL
        urlField.returnKeyType = .go
        urlField.clearButtonMode = .whileEditing
        urlField.delegate = self

        view.addSubview(topBar)
        topBar.addSubview(urlField)

        let bottomStack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadButton])
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.axis = .horizontal
        bottomStack.distribution = .fillEqually
        bottomStack.alignment = .center
        bottomStack.spacing = 16
        bottomBar.addSubview(bottomStack)
        view.addSubview(bottomBar)

        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        forwardButton.setImage(UIImage(systemName: "chevron.forward"), for: .normal)
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)

        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .touchUpInside)
        reloadButton.addTarget(self, action: #selector(didTapReload), for: .touchUpInside)

        geckoView = GeckoView(frame: .zero)
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)
        
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            urlField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            urlField.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            urlField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 50),

            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            bottomStack.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            geckoView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)
        ])

        geckoSession = GeckoSession()
        geckoSession.open()
        
        geckoView.session = geckoSession
        geckoSession.setActive(true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let initialUrl = "https://www.google.com/"
            self?.urlField.text = initialUrl
            self?.geckoSession.load(initialUrl)
        }
    }

    @objc private func didTapBack() {
        geckoSession.goBack()
    }

    @objc private func didTapForward() {
        geckoSession.goForward()
    }

    @objc private func didTapReload() {
        geckoSession.reload()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        loadFromUrlField()
        return true
    }

    private func loadFromUrlField() {
        guard let rawText = urlField.text else { return }
        let urlString = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        urlField.text = urlString
        geckoSession.load(urlString)
    }
}
