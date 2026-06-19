//
//  TabOverviewToolbarButton.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewToolbarButton: UIButton {
    private enum UX {
        static let toolbarButtonSideLength: CGFloat = 42
        static let toolbarButtonCornerRadius: CGFloat = 21
        static let toolbarButtonBorderWidth: CGFloat = 1
        static let toolbarButtonSymbolPointSize: CGFloat = 17
        static let disabledToolbarButtonAlpha: CGFloat = 0.35
    }
    
    enum Action {
        case clear
        case add
        case done
    }
    
    private let action: Action
    
    init(action: Action) {
        self.action = action
        super.init(frame: .zero)
        configureAppearance()
        configureImage()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setActionEnabled(_ enabled: Bool) {
        isEnabled = enabled
        alpha = enabled ? 1 : UX.disabledToolbarButtonAlpha
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = action == .done ? .systemBackground : .label
        backgroundColor = action == .done ? .label : .quaternarySystemFill
        layer.borderWidth = action == .done ? 0 : UX.toolbarButtonBorderWidth
        layer.borderColor = action == .done ? UIColor.clear.cgColor : UIColor.systemFill.cgColor
        layer.cornerCurve = .continuous
        layer.cornerRadius = UX.toolbarButtonCornerRadius
    }
    
    private func configureImage() {
        setImage(UIImage(named: symbolName), for: .normal)
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.toolbarButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UX.toolbarButtonSideLength),
            heightAnchor.constraint(equalTo: widthAnchor),
        ])
    }
    
    private var symbolName: String {
        switch action {
        case .clear: return "reynard.trash"
        case .add: return "reynard.plus"
        case .done: return "reynard.checkmark"
        }
    }
}
