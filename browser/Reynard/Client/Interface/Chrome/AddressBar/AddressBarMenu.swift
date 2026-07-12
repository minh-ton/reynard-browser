//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit
import GeckoView

enum AddressBarMenu {
    private struct Identifier {
        static let addressBarMenu = UIMenu.Identifier("com.minh-ton.Reynard.AddressBarMenu")
    }
    
    struct AddonItem {
        let menuItem: AddonMenuItem
        let image: UIImage?
    }

    struct Item {
        let title: String
        let image: UIImage?
        let startsSection: Bool
        let action: () -> Void
    }

    static func makeItems(
        selectedURL: String?,
        usesDesktopWebsite: Bool?,
        onShowAddons: @escaping () -> Void,
        onChangeWebsiteMode: @escaping () -> Void,
        onWebsiteSettings: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onBookmark: @escaping (Bool) -> Void
    ) -> [Item] {
        let url = selectedURL.flatMap(URL.init(string:))
        var items: [Item] = []
        if let url, url.host != nil {
            let title = BookmarkStore.shared.bookmark(savedFor: url) == nil
                ? NSLocalizedString("Add Bookmark", comment: "")
                : NSLocalizedString("Edit Bookmark", comment: "")
            items.append(Item(title: title, image: UIImage(named: "reynard.book"), startsSection: false) {
                onBookmark(false)
            })
            if !BookmarkStore.shared.isSavedInFavorites(url) {
                items.append(Item(title: "Add to Favorites", image: UIImage(named: "reynard.star"), startsSection: false) {
                    onBookmark(true)
                })
            }
        }
        items.append(Item(
            title: "Add-ons",
            image: UIImage(named: "reynard.puzzlepiece.extension"),
            startsSection: !items.isEmpty,
            action: onShowAddons
        ))
        if let isDesktop = usesDesktopWebsite {
            items.append(Item(
                title: isDesktop
                    ? NSLocalizedString("Request Mobile Website", comment: "")
                    : NSLocalizedString("Request Desktop Website", comment: ""),
                image: UIImage(named: isDesktop ? "reynard.smartphone" : "reynard.desktopcomputer"),
                startsSection: false,
                action: onChangeWebsiteMode
            ))
        }
        if url?.host != nil {
            items.append(Item(
                title: "Website Settings",
                image: UIImage(named: "reynard.gear"),
                startsSection: true,
                action: onWebsiteSettings
            ))
        }
        items.append(Item(
            title: "Settings",
            image: UIImage(named: "reynard.gear"),
            startsSection: url?.host == nil,
            action: onSettings
        ))
        return items
    }

    static func makeMenu(
        selectedURL: String?,
        usesDesktopWebsite: Bool?,
        addonItems: [AddonItem],
        onShowAddons: @escaping () -> Void,
        onPageZoom: @escaping () -> Void,
        onChangeWebsiteMode: @escaping () -> Void,
        onWebsiteSettings: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onBookmark: @escaping (Bool) -> Void
    ) -> UIMenu {
        var tabActions: [UIMenuElement] = []
        
        let url = selectedURL.flatMap(URL.init(string:))
        if let url, url.host != nil {
            let title = BookmarkStore.shared.bookmark(savedFor: url) == nil ? NSLocalizedString("Add Bookmark", comment: "") : NSLocalizedString("Edit Bookmark", comment: "")
            tabActions.append(UIAction(title: title, image: UIImage(named: "reynard.book")) { _ in
                onBookmark(false)
            })
            
            if !BookmarkStore.shared.isSavedInFavorites(url) {
                tabActions.append(UIAction(title: NSLocalizedString("Add to Favorites", comment: ""), image: UIImage(named: "reynard.star")) { _ in
                    onBookmark(true)
                })
            }
        }
        
        var pageActions: [UIMenuElement] = [
            UIAction(
                title: NSLocalizedString("Add-ons", comment: ""),
                image: UIImage(named: "reynard.puzzlepiece.extension")
            ) { _ in
                onShowAddons()
            }
        ]
        
        if url?.host != nil {
            pageActions.append(UIAction(title: NSLocalizedString("Page Zoom", comment: ""), image: UIImage(named: "reynard.textformat.size")) { _ in
                onPageZoom()
            })
        }
        
        if let isDesktop = usesDesktopWebsite {
            let title = isDesktop ? NSLocalizedString("Request Mobile Website", comment: "") : NSLocalizedString("Request Desktop Website", comment: "")
            let imageName = isDesktop ? "reynard.smartphone" : "reynard.desktopcomputer"
            pageActions.append(UIAction(title: title, image: UIImage(named: imageName)) { _ in
                onChangeWebsiteMode()
            })
        }
        
        var settingsActions: [UIMenuElement] = []
        if url?.host != nil {
            settingsActions.append(UIAction(title: NSLocalizedString("Website Settings", comment: ""), image: UIImage(named: "reynard.gear")) { _ in
                onWebsiteSettings()
            })
        }
        settingsActions.append(UIAction(title: "Settings", image: UIImage(named: "reynard.gear")) { _ in
            onSettings()
        })
        
        let children = tabActions + [UIMenu(options: .displayInline, children: pageActions)] + [UIMenu(options: .displayInline, children: settingsActions)]
        
        let menu = UIMenu(title: "", image: nil, identifier: Identifier.addressBarMenu, options: [], children: children)
        return menu
    }
}

final class AddressBarPageMenuView: UIControl {
    private enum UX {
        static let maximumWidth: CGFloat = 286
        static let relativeWidth: CGFloat = 0.7
        static let rowHeight: CGFloat = 44
        static let zoomHeight: CGFloat = 46
        static let separatorHeight = 1 / UIScreen.main.scale
        static let screenInset: CGFloat = 12
        static let anchorSpacing: CGFloat = 8
    }

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let zoomControl: AddressBarMenuZoomControl
    private let items: [AddressBarMenu.Item]
    private var rowViews: [(UIView, Bool)] = []
    private var isDismissing = false
    private var dismissalCompletions: [() -> Void] = []

    init(
        zoomLevel: Int,
        items: [AddressBarMenu.Item],
        onZoomLevel: @escaping (Int) -> Void
    ) {
        self.items = items
        zoomControl = AddressBarMenuZoomControl(level: zoomLevel, onLevel: onZoomLevel)
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.08)
        addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)

        panel.backgroundColor = .secondarySystemBackground
        panel.layer.cornerRadius = 12
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.24
        panel.layer.shadowRadius = 18
        panel.layer.shadowOffset = CGSize(width: 0, height: 8)
        panel.clipsToBounds = false
        addSubview(panel)

        scrollView.showsVerticalScrollIndicator = true
        scrollView.layer.cornerRadius = 12
        scrollView.clipsToBounds = true
        panel.addSubview(scrollView)
        scrollView.addSubview(zoomControl)

        for item in items {
            let button = AddressBarMenuActionButton(item: item) { [weak self] in
                self?.dismiss(animated: true, completion: item.action)
            }
            scrollView.addSubview(button)
            rowViews.append((button, item.startsSection))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(in window: UIWindow, anchorRect: CGRect) {
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)

        let contentHeight = UX.zoomHeight + CGFloat(items.count) * UX.rowHeight
            + CGFloat(rowViews.filter { $0.1 }.count) * UX.separatorHeight
        let safeFrame = window.bounds.inset(by: window.safeAreaInsets).insetBy(
            dx: UX.screenInset,
            dy: UX.screenInset
        )
        let panelWidth = min(UX.maximumWidth, safeFrame.width * UX.relativeWidth)
        let panelHeight = min(contentHeight, safeFrame.height)
        let proposedX = anchorRect.minX - UX.screenInset
        let panelX = min(max(safeFrame.minX, proposedX), safeFrame.maxX - panelWidth)
        let spaceBelow = safeFrame.maxY - anchorRect.maxY - UX.anchorSpacing
        let panelY: CGFloat
        if spaceBelow >= panelHeight {
            panelY = anchorRect.maxY + UX.anchorSpacing
        } else {
            panelY = max(safeFrame.minY, anchorRect.minY - UX.anchorSpacing - panelHeight)
        }
        panel.frame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        scrollView.frame = panel.bounds
        layoutRows(width: panelWidth, contentHeight: contentHeight)

        panel.alpha = 0
        panel.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.18) {
            self.panel.alpha = 1
            self.panel.transform = .identity
        }
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        if let completion {
            dismissalCompletions.append(completion)
        }

        guard superview != nil else {
            runDismissalCompletions()
            return
        }
        guard !isDismissing else { return }
        isDismissing = true

        let finish = { [weak self] in
            guard let self else { return }
            self.removeFromSuperview()
            self.isDismissing = false
            self.runDismissalCompletions()
        }
        guard animated else {
            finish()
            return
        }
        UIView.animate(withDuration: 0.15, animations: {
            self.panel.alpha = 0
            self.panel.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }) { _ in
            finish()
        }
    }

    private func runDismissalCompletions() {
        guard !dismissalCompletions.isEmpty else { return }
        let completions = dismissalCompletions
        dismissalCompletions.removeAll()
        DispatchQueue.main.async {
            completions.forEach { $0() }
        }
    }

    private func layoutRows(width: CGFloat, contentHeight: CGFloat) {
        var y: CGFloat = 0
        zoomControl.frame = CGRect(x: 0, y: y, width: width, height: UX.zoomHeight)
        y += UX.zoomHeight
        for (view, startsSection) in rowViews {
            if startsSection {
                let separator = UIView(frame: CGRect(x: 0, y: y, width: width, height: UX.separatorHeight))
                separator.backgroundColor = .separator
                scrollView.insertSubview(separator, belowSubview: view)
                y += UX.separatorHeight
            }
            view.frame = CGRect(x: 0, y: y, width: width, height: UX.rowHeight)
            y += UX.rowHeight
        }
        scrollView.contentSize = CGSize(width: width, height: max(contentHeight, y))
    }

    @objc private func backgroundTapped() {
        dismiss(animated: true)
    }
}

private final class AddressBarMenuZoomControl: UIView {
    private let levels = PageZoomLevels.all
    private var level: Int
    private let onLevel: (Int) -> Void
    private let percentageButton = UIButton(type: .system)

    init(level: Int, onLevel: @escaping (Int) -> Void) {
        self.level = level
        self.onLevel = onLevel
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemBackground

        let decrease = UIButton(type: .system)
        decrease.setTitle("A", for: .normal)
        decrease.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        decrease.accessibilityLabel = NSLocalizedString("Zoom Out", comment: "")
        decrease.addTarget(self, action: #selector(decreaseTapped), for: .touchUpInside)

        percentageButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        percentageButton.accessibilityLabel = NSLocalizedString("Reset Page Zoom", comment: "")
        percentageButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let increase = UIButton(type: .system)
        increase.setTitle("A", for: .normal)
        increase.titleLabel?.font = .systemFont(ofSize: 21, weight: .medium)
        increase.accessibilityLabel = NSLocalizedString("Zoom In", comment: "")
        increase.addTarget(self, action: #selector(increaseTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [decrease, percentageButton, increase])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updatePercentage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func decreaseTapped() {
        guard let index = levels.firstIndex(of: level), index > levels.startIndex else { return }
        setLevel(levels[levels.index(before: index)])
    }

    @objc private func increaseTapped() {
        guard let index = levels.firstIndex(of: level), index < levels.index(before: levels.endIndex) else { return }
        setLevel(levels[levels.index(after: index)])
    }

    @objc private func resetTapped() {
        setLevel(PageZoomLevels.defaultLevel)
    }

    private func setLevel(_ newLevel: Int) {
        level = newLevel
        updatePercentage()
        UISelectionFeedbackGenerator().selectionChanged()
        onLevel(newLevel)
    }

    private func updatePercentage() {
        percentageButton.setTitle(PageZoomLevels.displayText(for: level), for: .normal)
    }
}

private final class AddressBarMenuActionButton: UIButton {
    private let actionHandler: () -> Void

    init(item: AddressBarMenu.Item, action: @escaping () -> Void) {
        actionHandler = action
        super.init(frame: .zero)
        contentHorizontalAlignment = .left
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        setTitle(item.title, for: .normal)
        setTitleColor(.label, for: .normal)
        setImage(item.image, for: .normal)
        tintColor = .label
        titleLabel?.font = .systemFont(ofSize: 16)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        actionHandler()
    }
}
