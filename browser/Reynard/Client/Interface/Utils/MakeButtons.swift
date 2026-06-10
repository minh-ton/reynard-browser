//
//  MakeButtons.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit
import Darwin
import Symbols

enum MakeButtons {
    static let hasLiquidGlass = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_UISolariumEnabled") != nil && _UISolariumEnabled()
    static let bookmarksLibraryActionBarButtonTag = 8701
    static let historyLibraryActionBarButtonTag = 8702
    static let downloadsLibraryActionBarButtonTag = 8703
    static let libraryActionBarButtonTags: Set<Int> = [
        bookmarksLibraryActionBarButtonTag,
        historyLibraryActionBarButtonTag,
        downloadsLibraryActionBarButtonTag,
    ]
    
    private static func toolbarImage(for imageName: String) -> UIImage? {
        if let image = UIImage(systemName: imageName) {
            return image
        }
        
        if let image = UIImage(named: imageName) {
            return image
        }
        
        return nil
    }
    
    static func makeLibraryActionsButton(target: AnyObject, imageName: String, action: Selector) -> UIButton {
        let button = LibraryActionsButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        button.layer.cornerCurve = .continuous
        button.layer.masksToBounds = true
        button.addTarget(target, action: action, for: .touchUpInside)
        updateLibraryActionsButton(button, imageName: imageName)
        return button
    }
    
    static func updateLibraryActionsButton(_ button: UIButton, imageName: String) {
        if hasLiquidGlass, #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = toolbarImage(for: imageName)
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            button.configuration = configuration
        } else {
            button.setImage(toolbarImage(for: imageName), for: .normal)
            button.backgroundColor = .quaternarySystemFill
        }
    }
    
    static func installLibraryActionBarButton(_ item: UIBarButtonItem, in navigationItem: UINavigationItem) {
        navigationItem.leftItemsSupplementBackButton = true
        let existingItems = navigationItem.leftBarButtonItems?.filter {
            !libraryActionBarButtonTags.contains($0.tag)
        } ?? []
        navigationItem.leftBarButtonItems = existingItems + [item]
    }
    
    static func removeLibraryActionBarButtons(from navigationItem: UINavigationItem) {
        let remainingItems = navigationItem.leftBarButtonItems?.filter {
            !libraryActionBarButtonTags.contains($0.tag)
        }
        navigationItem.leftBarButtonItems = remainingItems?.isEmpty == true ? nil : remainingItems
    }
    
    static func makeTabOverviewBarButton(controller: BrowserViewController, imageName: String, isFilled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(toolbarImage(for: imageName), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = isFilled ? .systemBackground : .label
        button.backgroundColor = isFilled ? .label : .quaternarySystemFill
        button.layer.borderWidth = isFilled ? 0 : 1
        button.layer.borderColor = isFilled ? UIColor.clear.cgColor : UIColor.systemFill.cgColor
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 21
        button.addTarget(controller, action: action, for: .touchUpInside)
        return button
    }
    
    static func makeTabOverviewBarButtonItem(controller: BrowserViewController, systemItem: UIBarButtonItem.SystemItem, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: systemItem, target: controller, action: action)
        item.tintColor = .label
        return item
    }
}

private final class LibraryActionsButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard !MakeButtons.hasLiquidGlass else {
            return
        }
        
        layer.cornerRadius = bounds.height / 2
    }
}
