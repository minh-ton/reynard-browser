//
//  BrowserChromePositionOptionControl.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class BrowserChromePositionOptionControl: UIControl {
    private enum UX {
        static let topInset: CGFloat = 12
        static let previewHeight: CGFloat = 102
        static let previewSymbolSize: CGFloat = 78
        static let labelFontSize: CGFloat = 13
        static let labelHorizontalInset: CGFloat = 8
        static let indicatorTopSpacing: CGFloat = 6
        static let indicatorSize: CGFloat = 26
        static let indicatorSymbolSize: CGFloat = 22
        static let bottomInset: CGFloat = 12
    }
    
    let position: BrowserChromePosition
    
    private let previewImageView = UIImageView()
    private let nameLabel = UILabel()
    private let selectionIndicatorView = UIImageView()
    
    init(position: BrowserChromePosition, symbolName: String, title: String) {
        self.position = position
        super.init(frame: .zero)
        configureAccessibility(title: title)
        configurePreview(symbolName: symbolName)
        configureNameLabel(title: title)
        configureSelectionIndicator()
        installViews()
        activateConstraints()
        displaySelection(selected: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func displaySelection(selected: Bool) {
        let accent = tintColor ?? .systemBlue
        let secondary = UIColor.secondaryLabel
        previewImageView.tintColor = selected ? accent : secondary
        nameLabel.textColor = .label
        let radioConfig = UIImage.SymbolConfiguration(pointSize: UX.indicatorSymbolSize, weight: .regular)
        selectionIndicatorView.image = UIImage(
            named: selected ? "reynard.checkmark.circle.fill" : "reynard.circle", in: .main,
            with: radioConfig
        )
        selectionIndicatorView.tintColor = selected ? accent : secondary
    }
    
    private func configureAccessibility(title: String) {
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = [.button]
    }
    
    private func configurePreview(symbolName: String) {
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFit
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: UX.previewSymbolSize, weight: .ultraLight)
        previewImageView.image = UIImage(named: symbolName)?.applyingSymbolConfiguration(symbolConfiguration)
    }
    
    private func configureNameLabel(title: String) {
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: UX.labelFontSize, weight: .regular)
        nameLabel.textAlignment = .center
        nameLabel.text = title
    }
    
    private func configureSelectionIndicator() {
        selectionIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicatorView.contentMode = .scaleAspectFit
    }
    
    private func installViews() {
        addSubview(previewImageView)
        addSubview(nameLabel)
        addSubview(selectionIndicatorView)
    }
    
    private func activateConstraints() {
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: topAnchor, constant: UX.topInset),
            previewImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewImageView.heightAnchor.constraint(equalToConstant: UX.previewHeight),
            
            nameLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.labelHorizontalInset),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.labelHorizontalInset),
            
            selectionIndicatorView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: UX.indicatorTopSpacing),
            selectionIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionIndicatorView.widthAnchor.constraint(equalToConstant: UX.indicatorSize),
            selectionIndicatorView.heightAnchor.constraint(equalToConstant: UX.indicatorSize),
            selectionIndicatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UX.bottomInset),
        ])
    }
}
