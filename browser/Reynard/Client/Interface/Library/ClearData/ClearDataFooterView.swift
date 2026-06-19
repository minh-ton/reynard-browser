//
//  ClearDataFooterView.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class ClearDataFooterView: UIView {
    private enum UX {
        static let height: CGFloat = 88
        static let buttonCornerRadius: CGFloat = 25
        static let buttonTopInset: CGFloat = 24
        static let buttonHeight: CGFloat = 50
    }
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    
    private let clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .systemRed
        button.tintColor = .white
        button.layer.cornerRadius = UX.buttonCornerRadius
        button.layer.cornerCurve = .continuous
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        return button
    }()
    
    init(title: String, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: UX.height))
        clearButton.setTitle(title, for: .normal)
        clearButton.addTarget(target, action: action, for: .touchUpInside)
        installLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func alignClearButton(to rowRect: CGRect, tableViewWidth: CGFloat) {
        guard rowRect.width > 0 else {
            return
        }
        
        leadingConstraint?.constant = rowRect.minX
        trailingConstraint?.constant = -(tableViewWidth - rowRect.maxX)
    }
    
    private func installLayout() {
        addSubview(clearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        leadingConstraint = clearButton.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailingConstraint = clearButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        
        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: topAnchor, constant: UX.buttonTopInset),
            leadingConstraint!,
            trailingConstraint!,
            clearButton.heightAnchor.constraint(equalToConstant: UX.buttonHeight),
        ])
    }
}
