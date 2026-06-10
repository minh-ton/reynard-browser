//
//  KeyboardDismissButton.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class KeyboardDismissButton {
    let button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.alpha = 0
        button.isHidden = true
        button.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        button.tintColor = .label
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 21
        button.layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.3).cgColor : UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.masksToBounds = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
            forImageIn: .normal
        )
        return button
    }()
    
    var trailingPhoneConstraint: NSLayoutConstraint!
    var trailingPadConstraint: NSLayoutConstraint!
    var trailingCompactPadConstraint: NSLayoutConstraint!
    var centerYConstraint: NSLayoutConstraint!
    var widthConstraint: NSLayoutConstraint!
    var heightConstraint: NSLayoutConstraint!
}
