//
//  SelectPickerMenuAnchorButton.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class SelectPickerMenuAnchorButton: UIButton {
    // MARK: - State

    var onMenuDismissed: (() -> Void)?

    // MARK: - Overrides

    @available(iOS 14.0, *)
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        let handler = onMenuDismissed
        if let animator {
            animator.addCompletion {
                handler?()
            }
        } else {
            handler?()
        }
    }
}
