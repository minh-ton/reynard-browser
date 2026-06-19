//
//  LibraryActionButton.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class LibraryActionButton: UIButton {
    private enum UX {
        static let cornerRadiusDivisor: CGFloat = 2
    }
    
    static let bookmarksNavigationActionTag = 8701
    static let historyNavigationActionTag = 8702
    static let downloadsNavigationActionTag = 8703
    
    private static let navigationActionTags: Set<Int> = [
        bookmarksNavigationActionTag,
        historyNavigationActionTag,
        downloadsNavigationActionTag,
    ]
    
    // MARK: - Lifecycle
    
    init(target: AnyObject, iconName: String, action: Selector) {
        super.init(frame: .zero)
        configureAppearance()
        addTarget(target, action: action, for: .touchUpInside)
        setIcon(named: iconName)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard #unavailable(iOS 26.0) else {
            return
        }
        
        layer.cornerRadius = bounds.height / UX.cornerRadiusDivisor
    }
    
    // MARK: - Updates
    
    func setIcon(named iconName: String) {
        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = UIImage(named: iconName)
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            self.configuration = configuration
        } else {
            setImage(UIImage(named: iconName), for: .normal)
            backgroundColor = .quaternarySystemFill
        }
    }
    
    // MARK: - Navigation Items
    
    static func installNavigationAction(_ actionItem: UIBarButtonItem, in navigationItem: UINavigationItem) {
        navigationItem.leftItemsSupplementBackButton = true
        let retainedItems = navigationItem.leftBarButtonItems?.filter {
            !navigationActionTags.contains($0.tag)
        } ?? []
        navigationItem.leftBarButtonItems = retainedItems + [actionItem]
    }
    
    static func removeNavigationActions(from navigationItem: UINavigationItem) {
        let retainedItems = navigationItem.leftBarButtonItems?.filter {
            !navigationActionTags.contains($0.tag)
        }
        navigationItem.leftBarButtonItems = retainedItems?.isEmpty == true ? nil : retainedItems
    }
    
    static func makeSheetCloseButton(target: AnyObject, action: Selector) -> UIBarButtonItem {
        if #available(iOS 26.0, *) {
            let item = UIBarButtonItem(barButtonSystemItem: .cancel, target: target, action: action)
            item.tintColor = .label
            return item
        }
        
        return UIBarButtonItem(barButtonSystemItem: .done, target: target, action: action)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = .label
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }
}
