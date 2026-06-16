//
//  SidebarEmptyBackgroundView.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class SidebarEmptyBackgroundView: UIView {
    // MARK: - UX

    private enum UX {
        static let messageFont = UIFont.systemFont(ofSize: 16, weight: .medium)
    }

    // MARK: - State

    private var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != contentInsets else {
                return
            }

            setNeedsLayout()
        }
    }

    var message: String? {
        get {
            messageLabel.text
        }
        set {
            messageLabel.text = newValue
            setNeedsLayout()
        }
    }

    // MARK: - Views

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UX.messageFont
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    // MARK: - Lifecycle

    init(message: String) {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        setMessage(message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMessageLabel()
    }

    // MARK: - Layout

    func updateContentInsets(from tableView: UITableView) {
        let contentFrame = tableView.layoutMarginsGuide.layoutFrame
        contentInsets = UIEdgeInsets(
            top: 0,
            left: contentFrame.minX,
            bottom: 0,
            right: max(tableView.bounds.width - contentFrame.maxX, 0)
        )
    }

    private func layoutMessageLabel() {
        let availableWidth = max(bounds.width - contentInsets.left - contentInsets.right, 0)
        let fittingSize = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = messageLabel.sizeThatFits(fittingSize)
        messageLabel.frame = CGRect(
            x: contentInsets.left,
            y: (bounds.height - labelSize.height) / 2,
            width: availableWidth,
            height: labelSize.height
        ).integral
    }

    // MARK: - View Setup

    private func configureAppearance() {
        isUserInteractionEnabled = false
    }

    private func configureHierarchy() {
        addSubview(messageLabel)
    }

    private func setMessage(_ message: String) {
        messageLabel.text = message
    }
}
