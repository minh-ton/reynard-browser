//
//  SearchBar.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import UIKit

protocol SearchBarDelegate: AnyObject {
    func openBrowser(searchTerm: String)
}

final class SearchBar: UIView {
    private weak var browserDelegate: SearchBarDelegate?

    private let urlField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.placeholder = "Enter URL"
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .URL
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        return field
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        setupSearchBar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(browserDelegate: SearchBarDelegate) {
        self.browserDelegate = browserDelegate
        urlField.delegate = self
    }

    func setSearchBarText(_ text: String?) {
        urlField.text = text?.lowercased()
    }

    func getSearchBarText() -> String? {
        urlField.text?.lowercased()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        urlField.becomeFirstResponder()
        return super.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        urlField.resignFirstResponder()
        return super.resignFirstResponder()
    }

    private func setupSearchBar() {
        addSubview(urlField)

        NSLayoutConstraint.activate([
            urlField.topAnchor.constraint(equalTo: topAnchor),
            urlField.bottomAnchor.constraint(equalTo: bottomAnchor),
            urlField.leadingAnchor.constraint(equalTo: leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

extension SearchBar: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let searchText = textField.text?.lowercased(), !searchText.isEmpty else {
            return false
        }

        browserDelegate?.openBrowser(searchTerm: searchText)
        return true
    }
}
