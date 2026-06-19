//
//  AddressBarDismissButton.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class AddressBarDismissButton: UIButton {
    private enum UX {
        static let dismissButtonCornerRadiusDivisor: CGFloat = 2
        static let dismissButtonShadowOpacity: Float = 0.2
        static let dismissButtonDarkModeShadowAlpha: CGFloat = 0.3
        static let dismissButtonShadowRadius: CGFloat = 12
        static let dismissButtonShadowOffset = CGSize(width: 0, height: 4)
        static let dismissButtonSymbolPointSize: CGFloat = 20
    }
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = bounds.height / UX.dismissButtonCornerRadiusDivisor
        layer.shadowPath = layer.shadowOpacity > 0
        ? UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        : nil
    }
    
    // MARK: - Appearance
    
    func setShadowVisible(_ visible: Bool) {
        layer.shadowOpacity = visible ? UX.dismissButtonShadowOpacity : 0
        setNeedsLayout()
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        isHidden = true
        backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        tintColor = .label
        layer.cornerCurve = .continuous
        layer.shadowColor = UITraitCollection.current.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(UX.dismissButtonDarkModeShadowAlpha).cgColor
        : UIColor.black.cgColor
        layer.shadowRadius = UX.dismissButtonShadowRadius
        layer.shadowOffset = UX.dismissButtonShadowOffset
        layer.masksToBounds = false
        setImage(UIImage(named: "reynard.xmark"), for: .normal)
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.dismissButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
    }
}
