//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit
import GeckoView

enum AddressBarMenu {
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
                items.append(Item(title: NSLocalizedString("Add to Favorites", comment: ""), image: UIImage(named: "reynard.star"), startsSection: false) {
                    onBookmark(true)
                })
            }
        }
        items.append(Item(
            title: NSLocalizedString("Add-ons", comment: ""),
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
                title: NSLocalizedString("Website Settings", comment: ""),
                image: UIImage(named: "reynard.gear"),
                startsSection: true,
                action: onWebsiteSettings
            ))
        }
        items.append(Item(
            title: NSLocalizedString("Settings", comment: ""),
            image: UIImage(named: "reynard.gear"),
            startsSection: url?.host == nil,
            action: onSettings
        ))
        return items
    }
}

final class AddressBarPageMenuView: UIControl {
    private enum UX {
        static let cornerRadius: CGFloat = 14
    }

    private let panel = UIView()
    private let materialView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let scrollView = UIScrollView()
    private let zoomControl: AddressBarMenuZoomControl
    private let items: [AddressBarMenu.Item]
    private var rowViews: [(view: UIView, sectionDivider: UIView?)] = []
    private var isDismissing = false
    private var dismissalCompletions: [() -> Void] = []

    private var rowHeight: CGFloat {
        max(
            AddressBarPageMenuLayoutPolicy.minimumRowHeight,
            ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight + 28)
        )
    }

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

        panel.backgroundColor = .clear
        panel.layer.cornerRadius = UX.cornerRadius
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.28
        panel.layer.shadowRadius = 22
        panel.layer.shadowOffset = CGSize(width: 0, height: 10)
        panel.clipsToBounds = false
        panel.accessibilityViewIsModal = true
        addSubview(panel)

        materialView.layer.cornerRadius = UX.cornerRadius
        materialView.layer.cornerCurve = .continuous
        materialView.clipsToBounds = true
        panel.addSubview(materialView)

        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        materialView.contentView.addSubview(scrollView)
        scrollView.addSubview(zoomControl)

        for (index, item) in items.enumerated() {
            let nextStartsSection = items.indices.contains(index + 1)
                && items[index + 1].startsSection
            let row = AddressBarMenuActionRow(
                item: item,
                showsSeparator: index < items.count - 1 && !nextStartsSection
            ) { [weak self] in
                self?.dismiss(animated: true, completion: item.action)
            }
            let sectionDivider: UIView?
            if item.startsSection {
                let divider = UIView()
                divider.backgroundColor = UIColor.separator.withAlphaComponent(0.16)
                scrollView.addSubview(divider)
                sectionDivider = divider
            } else {
                sectionDivider = nil
            }
            scrollView.addSubview(row)
            rowViews.append((row, sectionDivider))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(in window: UIWindow, anchorRect: CGRect) {
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)

        let contentHeight = AddressBarPageMenuLayoutPolicy.zoomHeight
            + CGFloat(items.count) * rowHeight
            + CGFloat(rowViews.filter { $0.sectionDivider != nil }.count)
                * AddressBarPageMenuLayoutPolicy.sectionSpacing
        panel.frame = AddressBarPageMenuLayoutPolicy.panelFrame(
            containerBounds: window.bounds,
            safeAreaInsets: AddressBarPageMenuSafeAreaInsets(
                top: window.safeAreaInsets.top,
                left: window.safeAreaInsets.left,
                bottom: window.safeAreaInsets.bottom,
                right: window.safeAreaInsets.right
            ),
            anchorRect: anchorRect,
            contentHeight: contentHeight
        )
        materialView.frame = panel.bounds
        scrollView.frame = panel.bounds
        layoutRows(width: panel.bounds.width, contentHeight: contentHeight)

        panel.alpha = 0
        panel.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.18, animations: {
            self.panel.alpha = 1
            self.panel.transform = .identity
        }) { _ in
            UIAccessibility.post(notification: .screenChanged, argument: self.zoomControl)
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
        zoomControl.frame = CGRect(
            x: 0,
            y: y,
            width: width,
            height: AddressBarPageMenuLayoutPolicy.zoomHeight
        )
        y += AddressBarPageMenuLayoutPolicy.zoomHeight
        for row in rowViews {
            if let sectionDivider = row.sectionDivider {
                sectionDivider.frame = CGRect(
                    x: 0,
                    y: y,
                    width: width,
                    height: AddressBarPageMenuLayoutPolicy.sectionSpacing
                )
                y += AddressBarPageMenuLayoutPolicy.sectionSpacing
            }
            row.view.frame = CGRect(x: 0, y: y, width: width, height: rowHeight)
            y += rowHeight
        }
        scrollView.contentSize = CGSize(width: width, height: max(contentHeight, y))
    }

    @objc private func backgroundTapped() {
        dismiss(animated: true)
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss(animated: true)
        return true
    }
}

private final class AddressBarMenuZoomControl: UIView {
    private let levels = PageZoomLevels.all
    private var level: Int
    private let onLevel: (Int) -> Void
    private let decreaseButton = UIButton(type: .system)
    private let percentageButton = UIButton(type: .system)
    private let increaseButton = UIButton(type: .system)

    init(level: Int, onLevel: @escaping (Int) -> Void) {
        self.level = level
        self.onLevel = onLevel
        super.init(frame: .zero)
        backgroundColor = .clear

        configure(
            decreaseButton,
            title: "A",
            font: .systemFont(ofSize: 15, weight: .medium),
            accessibilityLabel: NSLocalizedString("Zoom Out", comment: ""),
            action: #selector(decreaseTapped)
        )

        configure(
            percentageButton,
            title: nil,
            font: .systemFont(ofSize: 17, weight: .regular),
            accessibilityLabel: NSLocalizedString("Reset Page Zoom", comment: ""),
            action: #selector(resetTapped)
        )

        configure(
            increaseButton,
            title: "A",
            font: .systemFont(ofSize: 22, weight: .medium),
            accessibilityLabel: NSLocalizedString("Zoom In", comment: ""),
            action: #selector(increaseTapped)
        )

        let stack = UIStackView(
            arrangedSubviews: [decreaseButton, percentageButton, increaseButton]
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        addSubview(stack)

        let firstDivider = makeDivider()
        let secondDivider = makeDivider()
        let bottomDivider = makeDivider()
        addSubview(firstDivider)
        addSubview(secondDivider)
        addSubview(bottomDivider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            firstDivider.centerXAnchor.constraint(equalTo: decreaseButton.trailingAnchor),
            firstDivider.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            firstDivider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            firstDivider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            secondDivider.centerXAnchor.constraint(equalTo: percentageButton.trailingAnchor),
            secondDivider.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            secondDivider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            secondDivider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        updateControls()
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
        updateControls()
        UISelectionFeedbackGenerator().selectionChanged()
        onLevel(newLevel)
    }

    private func updateControls() {
        let displayText = PageZoomLevels.displayText(for: level)
        percentageButton.setTitle(displayText, for: .normal)
        percentageButton.accessibilityValue = displayText
        if let index = levels.firstIndex(of: level) {
            decreaseButton.isEnabled = index > levels.startIndex
            increaseButton.isEnabled = index < levels.index(before: levels.endIndex)
        }
        decreaseButton.alpha = decreaseButton.isEnabled ? 1 : 0.32
        increaseButton.alpha = increaseButton.isEnabled ? 1 : 0.32
    }

    private func configure(
        _ button: UIButton,
        title: String?,
        font: UIFont,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        divider.isUserInteractionEnabled = false
        return divider
    }
}

private final class AddressBarMenuActionRow: UIControl {
    private let actionHandler: () -> Void
    private let titleView = UILabel()
    private let iconView = UIImageView()

    init(
        item: AddressBarMenu.Item,
        showsSeparator: Bool,
        action: @escaping () -> Void
    ) {
        actionHandler = action
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = item.title
        accessibilityTraits = .button

        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.text = item.title
        titleView.textColor = .label
        titleView.font = .preferredFont(forTextStyle: .body)
        titleView.adjustsFontForContentSizeCategory = true
        titleView.lineBreakMode = .byTruncatingTail
        addSubview(titleView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.image = item.image?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .label
        iconView.isHidden = item.image == nil
        addSubview(iconView)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        separator.isHidden = !showsSeparator
        separator.isUserInteractionEnabled = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            titleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleView.trailingAnchor.constraint(
                lessThanOrEqualTo: iconView.leadingAnchor,
                constant: -16
            ),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
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

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.08)
                : .clear
        }
    }
}
