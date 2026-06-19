//
//  CustomSearchTemplateCell.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class CustomSearchTemplateCell: UITableViewCell {
    private enum UX {
        static let verticalInset: CGFloat = 12
    }
    
    let textField = UITextField()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureCell()
        configureTextField()
        installTextField()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureCell() {
        selectionStyle = .none
    }
    
    private func configureTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
    }
    
    private func installTextField() {
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.verticalInset),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.verticalInset),
        ])
    }
}
