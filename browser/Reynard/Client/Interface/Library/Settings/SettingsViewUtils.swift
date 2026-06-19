//
//  SettingsViewUtils.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

struct SettingsSectionText {
    let headerTitle: String?
    let footerTitle: String?
    
    init(headerTitle: String? = nil, footerTitle: String? = nil) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
    }
}

enum SettingsViewUtils {
    private enum UX {
        static let minimumProgressTopSpacing: CGFloat = 12
        static let alertContentSpacing: CGFloat = 16
        static let fallbackProgressTopSpacing: CGFloat = 20
    }
    
    // MARK: - Cells
    
    static func disclosureCell(title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    static func actionCell(title: String, tintColor: UIColor?) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.textColor = tintColor
        return cell
    }
    
    // MARK: - Alerts
    
    static func dismissPresentedAlert(
        _ alert: UIAlertController,
        from viewController: UIViewController,
        completion: @escaping () -> Void
    ) {
        guard viewController.presentedViewController === alert else {
            completion()
            return
        }
        
        alert.dismiss(animated: true, completion: completion)
    }
    
    static func addProgressView(_ progressView: UIProgressView, to alert: UIAlertController) {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else {
            return
        }
        
        alert.view.addSubview(progressView)
        
        let cancelAnchorView = alert.view.firstDescendantButton(withTitle: "Cancel") ??
        alert.view.firstDescendantView(containingLabelText: "Cancel")
        var constraints = [
            progressView.widthAnchor.constraint(equalTo: messageLabel.widthAnchor),
            progressView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            progressView.topAnchor.constraint(
                greaterThanOrEqualTo: messageLabel.bottomAnchor,
                constant: UX.minimumProgressTopSpacing
            ),
        ]
        
        if let cancelAnchorView {
            let verticalGuide = UILayoutGuide()
            alert.view.addLayoutGuide(verticalGuide)
            constraints.append(contentsOf: [
                verticalGuide.topAnchor.constraint(
                    equalTo: messageLabel.bottomAnchor,
                    constant: UX.alertContentSpacing
                ),
                verticalGuide.bottomAnchor.constraint(
                    equalTo: cancelAnchorView.topAnchor,
                    constant: -UX.alertContentSpacing
                ),
                progressView.centerYAnchor.constraint(equalTo: verticalGuide.centerYAnchor),
            ])
        } else {
            constraints.append(
                progressView.topAnchor.constraint(
                    equalTo: messageLabel.bottomAnchor,
                    constant: UX.fallbackProgressTopSpacing
                )
            )
        }
        
        NSLayoutConstraint.activate(constraints)
    }
}
