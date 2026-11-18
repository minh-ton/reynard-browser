//
//  ReaderSettingsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 15/9/26.
//

import UIKit

final class ReaderSettingsViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private enum UX {
        static let width: CGFloat = 360
        static let padding: CGFloat = 16
        static let spacing: CGFloat = 16
        static let readerCornerRadius: CGFloat = 24
        static let themeCheckmarkSize: CGFloat = 24
        static let glassCornerRadius: CGFloat = 40
        static let glassReaderCornerRadius: CGFloat = glassCornerRadius - padding
        static let hideReaderSpacing: CGFloat = 20
        static let actionSpacing: CGFloat = 8
        static let controlHeight: CGFloat = 48
        static let brightnessPillHeight: CGFloat = 52
        static let fontChevronSize: CGFloat = 12
        static let hideReaderFontSize: CGFloat = 16
        static let hideReaderSymbolSize: CGFloat = 16
        static let fontPillHeight: CGFloat = 28
        static let fontSize: CGFloat = 17
        static let titleSize: CGFloat = 19
        static let symbolSize: CGFloat = 20
        static let fontControlSymbolSize: CGFloat = 20
        static let themeCornerRadius: CGFloat = 22
        static let borderWidth: CGFloat = 0.5
        static let dotSize: CGFloat = 4
        static let dotSpacing: CGFloat = 6
        static let fadeDuration: TimeInterval = 0.2
        static let dotDelay: TimeInterval = 0.8
        static let brightnessThreshold: Float = 0.08
    }
    
    var onFindInPage: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    
    private let tabID: UUID
    private let tabManager: TabManager
    private let readerMode: ReaderModeController
    private let contentStack = UIStackView()
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private var materialContainers: [UIVisualEffectView] = []
    private let fontButton = UIButton(type: .system)
    private let brightnessSlider = UISlider()
    private let minimumSun = UIImageView(image: UIImage(named: "reynard.sun.min.fill"))
    private let maximumSun = UIImageView(image: UIImage(named: "reynard.sun.max.fill"))
    private let fontSizeDots = UIStackView()
    private var themeButtons: [UIButton] = []
    private var themeCheckmarks: [UIImageView] = []
    private var decreaseFontButton: UIButton!
    private var increaseFontButton: UIButton!
    private var fontSizeDotsDismissal: DispatchWorkItem?
    private var lastBrightnessEndpoint = 0
    private var usesGlassSheet = false
    
    // MARK: - Lifecycle
    
    init(tabID: UUID, tabManager: TabManager, readerMode: ReaderModeController) {
        self.tabID = tabID
        self.tabManager = tabManager
        self.readerMode = readerMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureContent()
        refreshAppearance()
        NotificationCenter.default.addObserver(self, selector: #selector(brightnessDidChange), name: UIScreen.brightnessDidChangeNotification, object: nil)
        brightnessDidChange()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onVisibilityChanged?(true)
    }
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        brightnessDidChange()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        let size = CGSize(width: width, height: contentHeight(for: width))
        guard preferredContentSize != size else { return }
        preferredContentSize = size
        if #available(iOS 16.0, *) {
            sheetPresentationController?.invalidateDetents()
        } else if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.detents = [._detent(withIdentifier: "reader", constant: Double(size.height))]
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if #available(iOS 26.0, *), usesGlassSheet {
            sheetPresentationController?.invalidateDetents()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        brightnessAdjustmentEnded()
        
        if isBeingDismissed || presentingViewController == nil {
            onVisibilityChanged?(false)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        fontSizeDotsDismissal?.cancel()
    }
    
    // MARK: - Presentation
    
    func configurePresentation(asPopover: Bool) {
        if #available(iOS 26.0, *) {
            usesGlassSheet = !asPopover
        }
        loadViewIfNeeded()
        preferredContentSize = CGSize(width: UX.width, height: contentHeight(for: UX.width))
        if #available(iOS 15.0, *), !asPopover {
            modalPresentationStyle = .pageSheet
            if let sheet = sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 0
                if #available(iOS 26.0, *) {
                    sheet.prefersGrabberVisible = false
                    sheet.preferredCornerRadius = UX.glassCornerRadius
                    sheet.setValue(UIVisualEffect(), forKey: "backgroundEffect")
                    view.backgroundColor = .clear
                    backgroundView.effect = UIGlassEffect.nonAdaptive(style: .regular)
                    backgroundView.layer.cornerCurve = .continuous
                    backgroundView.layer.cornerRadius = UX.glassCornerRadius
                    backgroundView.clipsToBounds = true
                    configureOpaqueMaterialContainers()
                }
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom(identifier: .init("reader")) { [weak self] context in
                        guard let self else { return nil }
                        let bottomInset = self.usesGlassSheet ? self.view.safeAreaInsets.bottom : 0
                        return min(self.preferredContentSize.height - bottomInset, context.maximumDetentValue)
                    }]
                } else {
                    sheet.detents = [._detent(withIdentifier: "reader", constant: Double(preferredContentSize.height))]
                }
            }
        } else {
            modalPresentationStyle = .popover
            if #available(iOS 26.0, *) {
                view.backgroundColor = .clear
                backgroundView.effect = nil
                configureOpaqueMaterialContainers()
            }
        }
    }
    
    nonisolated func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
    
    private func contentHeight(for width: CGFloat) -> CGFloat {
        return contentStack.systemLayoutSizeFitting(
            CGSize(width: width - UX.padding * 2, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + UX.padding * 2
    }
    
    // MARK: - Content
    
    private func configureContent() {
        configureRootView()
        
        let readerContainer = makeReaderContainer()
        contentStack.addArrangedSubview(readerContainer)
        contentStack.addArrangedSubview(makeBrightnessControl())
        
        let actionControls = makeActionControls()
        contentStack.addArrangedSubview(actionControls)
        contentStack.setCustomSpacing(UX.hideReaderSpacing, after: actionControls)
        contentStack.addArrangedSubview(makeHideReaderButton())
    }
    
    private func configureRootView() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        contentStack.axis = .vertical
        contentStack.spacing = UX.spacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        if usesGlassSheet {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: usesGlassSheet ? view.bottomAnchor : view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: UX.padding),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -UX.padding),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: UX.padding),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -UX.padding),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -UX.padding * 2)
        ])
    }
    
    private func makeReaderContainer() -> UIVisualEffectView {
        let reader = UIStackView()
        reader.axis = .vertical
        reader.spacing = UX.spacing
        
        let title = UILabel()
        title.text = NSLocalizedString("Reader", comment: "")
        title.font = .systemFont(ofSize: UX.titleSize, weight: .semibold)
        configureFontButton()
        
        let header = UIStackView(arrangedSubviews: [title, fontButton])
        header.spacing = UX.spacing
        reader.addArrangedSubview(header)
        reader.addArrangedSubview(makeThemePicker())
        let material = makeMaterialContainer(
            containing: reader,
            cornerRadius: usesGlassSheet ? UX.glassReaderCornerRadius : UX.readerCornerRadius,
            verticalInset: UX.padding
        )
        material.contentView.backgroundColor = .tertiarySystemFill
        return material
    }
    
    private func configureFontButton() {
        fontButton.setImage(UIImage(named: "reynard.chevron.up.chevron.down"), for: .normal)
        fontButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: UX.fontChevronSize, weight: .medium), forImageIn: .normal)
        fontButton.setTitleColor(.label, for: .normal)
        fontButton.semanticContentAttribute = .forceRightToLeft
        fontButton.tintColor = .secondaryLabel
        fontButton.backgroundColor = .tertiarySystemFill
        fontButton.layer.cornerRadius = UX.fontPillHeight / 2
        fontButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: UX.padding, bottom: 0, right: UX.padding)
        fontButton.heightAnchor.constraint(equalToConstant: UX.fontPillHeight).isActive = true
        fontButton.setContentHuggingPriority(.required, for: .horizontal)
        if #available(iOS 14.0, *) {
            fontButton.showsMenuAsPrimaryAction = true
        } else {
            fontButton.addTarget(self, action: #selector(showLegacyFontMenu), for: .touchUpInside)
        }
    }
    
    private func makeBrightnessControl() -> UIVisualEffectView {
        brightnessSlider.minimumTrackTintColor = .label
        brightnessSlider.addTarget(self, action: #selector(brightnessChanged), for: .valueChanged)
        brightnessSlider.addTarget(self, action: #selector(brightnessAdjustmentBegan), for: .touchDown)
        brightnessSlider.addTarget(self, action: #selector(brightnessAdjustmentEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let brightness = UIStackView(arrangedSubviews: [minimumSun, brightnessSlider, maximumSun])
        brightness.spacing = UX.spacing
        brightness.alignment = .center
        [minimumSun, maximumSun].forEach {
            $0.contentMode = .scaleAspectFit
            $0.tintColor = .label
            $0.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: UX.symbolSize)
            $0.widthAnchor.constraint(equalToConstant: UX.symbolSize).isActive = true
        }
        let brightnessPill = makeMaterialContainer(
            containing: brightness,
            cornerRadius: UX.brightnessPillHeight / 2,
            verticalInset: UX.padding / 2
        )
        brightnessPill.contentView.backgroundColor = .tertiarySystemFill
        brightnessPill.heightAnchor.constraint(equalToConstant: UX.brightnessPillHeight).isActive = true
        return brightnessPill
    }
    
    private func makeHideReaderButton() -> UIButton {
        let hide = makeButton(image: "reynard.text.page.slash.fill", label: NSLocalizedString("Hide Reader", comment: ""), action: #selector(hideReader))
        hide.setTitle(" " + NSLocalizedString("Hide Reader", comment: ""), for: .normal)
        hide.titleLabel?.font = .systemFont(ofSize: UX.hideReaderFontSize, weight: .regular)
        hide.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: UX.hideReaderSymbolSize, weight: .regular), forImageIn: .normal)
        hide.tintColor = .white
        hide.setTitleColor(.white, for: .normal)
        hide.backgroundColor = .systemBlue
        hide.layer.cornerRadius = UX.controlHeight / 2
        hide.heightAnchor.constraint(equalToConstant: UX.controlHeight).isActive = true
        return hide
    }
    
    private func makeThemePicker() -> UIView {
        let row = UIStackView()
        row.spacing = UX.spacing
        row.distribution = .fillEqually
        
        for (index, colorScheme) in ReaderViewColorScheme.allCases.enumerated() {
            let colors = themeColors(for: colorScheme)
            let button = UIButton(type: .custom)
            button.tag = index
            button.backgroundColor = colors.background
            button.layer.cornerRadius = UX.themeCornerRadius
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = UX.borderWidth
            button.layer.borderColor = colors.foreground.withAlphaComponent(0.18).cgColor
            button.addTarget(self, action: #selector(themeSelected(_:)), for: .touchUpInside)
            
            let check = UIImageView(image: UIImage(named: "reynard.checkmark"))
            check.tintColor = colors.foreground
            check.contentMode = .scaleAspectFit
            
            let label = UILabel()
            label.text = title(for: colorScheme)
            label.font = .systemFont(ofSize: UX.fontSize)
            label.textColor = colors.foreground
            
            let contents = UIStackView(arrangedSubviews: [check, label])
            contents.axis = .vertical
            contents.alignment = .center
            contents.spacing = UX.dotSpacing
            contents.isUserInteractionEnabled = false
            contents.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(contents)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalTo: button.widthAnchor),
                contents.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                contents.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                check.heightAnchor.constraint(equalToConstant: UX.themeCheckmarkSize),
                check.widthAnchor.constraint(equalTo: check.heightAnchor)
            ])
            themeButtons.append(button)
            themeCheckmarks.append(check)
            row.addArrangedSubview(button)
        }
        return row
    }
    
    private func makeActionControls() -> UIView {
        let find = makeButton(image: "reynard.text.page.badge.magnifyingglass", label: NSLocalizedString("Find in Page", comment: ""), action: #selector(findInPage))
        find.widthAnchor.constraint(equalToConstant: UX.controlHeight).isActive = true
        decreaseFontButton = makeButton(image: "reynard.textformat.size.smaller", label: NSLocalizedString("Decrease Font Size", comment: ""), action: #selector(decreaseFont))
        increaseFontButton = makeButton(image: "reynard.textformat.size.larger", label: NSLocalizedString("Increase Font Size", comment: ""), action: #selector(increaseFont))
        decreaseFontButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: UX.fontControlSymbolSize, weight: .regular), forImageIn: .normal)
        increaseFontButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: UX.fontControlSymbolSize, weight: .regular), forImageIn: .normal)
        
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: UX.controlHeight * 0.42).isActive = true
        
        let controls = UIStackView(arrangedSubviews: [decreaseFontButton, separator, increaseFontButton])
        controls.alignment = .center
        decreaseFontButton.widthAnchor.constraint(equalTo: increaseFontButton.widthAnchor).isActive = true
        decreaseFontButton.heightAnchor.constraint(equalToConstant: UX.controlHeight).isActive = true
        increaseFontButton.heightAnchor.constraint(equalToConstant: UX.controlHeight).isActive = true
        
        let findBackground = makeMaterialContainer(containing: find, cornerRadius: UX.controlHeight / 2, verticalInset: 0, horizontalInset: 0)
        let controlsBackground = makeMaterialContainer(containing: controls, cornerRadius: UX.controlHeight / 2, verticalInset: 0, horizontalInset: 0)
        findBackground.contentView.backgroundColor = .tertiarySystemFill
        controlsBackground.contentView.backgroundColor = .tertiarySystemFill
        
        let row = UIStackView(arrangedSubviews: [findBackground, controlsBackground])
        row.spacing = UX.actionSpacing
        row.heightAnchor.constraint(equalToConstant: UX.controlHeight).isActive = true
        
        fontSizeDots.spacing = UX.dotSpacing
        fontSizeDots.alpha = 0
        for _ in ReaderViewAppearance.minimumFontSizeStep...ReaderViewAppearance.maximumFontSizeStep {
            let dot = UIView()
            dot.layer.cornerRadius = UX.dotSize / 2
            dot.widthAnchor.constraint(equalToConstant: UX.dotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: UX.dotSize).isActive = true
            fontSizeDots.addArrangedSubview(dot)
        }
        fontSizeDots.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(fontSizeDots)
        NSLayoutConstraint.activate([
            fontSizeDots.centerXAnchor.constraint(equalTo: controlsBackground.centerXAnchor),
            fontSizeDots.centerYAnchor.constraint(equalTo: row.bottomAnchor, constant: UX.spacing / 2)
        ])
        return row
    }
    
    private func makeMaterialContainer(
        containing content: UIView,
        cornerRadius: CGFloat,
        verticalInset: CGFloat,
        horizontalInset: CGFloat = UX.padding
    ) -> UIVisualEffectView {
        let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        material.layer.cornerRadius = cornerRadius
        material.layer.cornerCurve = .continuous
        material.clipsToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        material.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: material.contentView.topAnchor, constant: verticalInset),
            content.bottomAnchor.constraint(equalTo: material.contentView.bottomAnchor, constant: -verticalInset),
            content.leadingAnchor.constraint(equalTo: material.contentView.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: material.contentView.trailingAnchor, constant: -horizontalInset)
        ])
        materialContainers.append(material)
        return material
    }
    
    private func configureOpaqueMaterialContainers() {
        materialContainers.forEach {
            $0.effect = nil
            $0.contentView.backgroundColor = .tertiarySystemFill
        }
    }
    
    private func makeButton(image: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: image), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: UX.symbolSize), forImageIn: .normal)
        button.tintColor = .label
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    // MARK: - Appearance
    
    private func title(for fontType: ReaderViewFontType) -> String {
        switch fontType {
        case .sansSerif:
            return NSLocalizedString("Sans Serif", comment: "Reader mode font")
        case .serif:
            return NSLocalizedString("Serif", comment: "Reader mode font")
        }
    }
    
    private func title(for colorScheme: ReaderViewColorScheme) -> String {
        switch colorScheme {
        case .light:
            return NSLocalizedString("Light", comment: "Reader mode background color")
        case .sepia:
            return NSLocalizedString("Sepia", comment: "Reader mode background color")
        case .dark:
            return NSLocalizedString("Dark", comment: "Reader mode background color")
        }
    }
    
    private func themeColors(for colorScheme: ReaderViewColorScheme) -> (background: UIColor, foreground: UIColor) {
        switch colorScheme {
        case .light:
            return (.white, .black)
        case .sepia:
            return (
                UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1),
                UIColor(red: 0.36, green: 0.32, blue: 0.26, alpha: 1)
            )
        case .dark:
            return (UIColor(white: 0.11, alpha: 1), UIColor(white: 0.9, alpha: 1))
        }
    }
    
    private func font(for type: ReaderViewFontType) -> UIFont {
        let descriptor = UIFont.systemFont(ofSize: UX.fontSize).fontDescriptor
        return UIFont(descriptor: descriptor.withDesign(type == .serif ? .serif : .default) ?? descriptor, size: UX.fontSize)
    }
    
    private func refreshAppearance() {
        refreshFontSelection()
        refreshThemeSelection()
        refreshFontSize()
    }
    
    private func refreshFontSelection() {
        let selectedFontType = Prefs.BrowsingSettings.readerViewFontType
        let actions = ReaderViewFontType.allCases.map { fontType in
            let title = title(for: fontType)
            let action = UIAction(title: title, state: selectedFontType == fontType ? .on : .off) { [weak self] _ in
                guard let self, self.isCurrentReader else { return }
                self.readerMode.setFontType(fontType, for: self.tabManager.selectedTab?.session)
                self.refreshAppearance()
            }
            if action.responds(to: Selector(("setAttributedTitle:"))) {
                action.attributedTitle = NSAttributedString(string: title, attributes: [.font: font(for: fontType)])
            }
            return action
        }
        fontButton.setTitle(title(for: selectedFontType) + " ", for: .normal)
        fontButton.titleLabel?.font = font(for: selectedFontType)
        if #available(iOS 14.0, *) {
            fontButton.menu = UIMenu(children: actions)
        }
    }
    
    private func refreshThemeSelection() {
        let selectedColorScheme = Prefs.BrowsingSettings.readerViewColorScheme
        for (index, colorScheme) in ReaderViewColorScheme.allCases.enumerated() {
            let selected = selectedColorScheme == colorScheme
            themeCheckmarks[index].alpha = selected ? 1 : 0
            themeButtons[index].accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }
    
    private func refreshFontSize() {
        let step = Prefs.BrowsingSettings.readerViewFontSizeStep
        decreaseFontButton.isEnabled = step > ReaderViewAppearance.minimumFontSizeStep
        increaseFontButton.isEnabled = step < ReaderViewAppearance.maximumFontSizeStep
        fontSizeDots.arrangedSubviews.enumerated().forEach { index, dot in
            dot.backgroundColor = index + ReaderViewAppearance.minimumFontSizeStep <= step ? .label : .quaternaryLabel
        }
    }
    
    private var isCurrentReader: Bool {
        guard let selectedTab = tabManager.selectedTab else { return false }
        return selectedTab.id == tabID && selectedTab.state.readerMode.isActive
    }
    
    // MARK: - Actions
    
    @objc private func themeSelected(_ sender: UIButton) {
        guard isCurrentReader else { return }
        readerMode.setColorScheme(
            ReaderViewColorScheme.allCases[sender.tag],
            for: tabManager.selectedTab?.session
        )
        refreshAppearance()
    }
    
    @objc private func showLegacyFontMenu() {
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for fontType in ReaderViewFontType.allCases {
            menu.addAction(UIAlertAction(title: title(for: fontType), style: .default) { [weak self] _ in
                guard let self, self.isCurrentReader else { return }
                self.readerMode.setFontType(fontType, for: self.tabManager.selectedTab?.session)
                self.refreshAppearance()
            })
        }
        menu.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        menu.popoverPresentationController?.sourceView = fontButton
        menu.popoverPresentationController?.sourceRect = fontButton.bounds
        present(menu, animated: true)
    }
    
    @objc private func brightnessAdjustmentBegan() {
        guard #available(iOS 15.0, *), modalPresentationStyle == .pageSheet else { return }
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.largestUndimmedDetentIdentifier = .init("reader")
        }
    }
    
    @objc private func brightnessAdjustmentEnded() {
        guard #available(iOS 15.0, *), modalPresentationStyle == .pageSheet else { return }
        guard let sheet = sheetPresentationController, sheet.largestUndimmedDetentIdentifier != nil else { return }
        sheet.animateChanges {
            sheet.largestUndimmedDetentIdentifier = nil
        }
    }
    
    @objc private func brightnessDidChange() {
        guard let screen = view.window?.windowScene?.screen else { return }
        brightnessSlider.value = Float(screen.brightness)
    }
    
    @objc private func brightnessChanged() {
        view.window?.windowScene?.screen.brightness = CGFloat(brightnessSlider.value)
        let reachedMinimum = brightnessSlider.value <= UX.brightnessThreshold
        let reachedMaximum = brightnessSlider.value >= 1 - UX.brightnessThreshold
        let endpoint = reachedMinimum ? -1 : (reachedMaximum ? 1 : 0)
        if #available(iOS 17.0, *), endpoint != 0, endpoint != lastBrightnessEndpoint, !UIAccessibility.isReduceMotionEnabled {
            (endpoint < 0 ? minimumSun : maximumSun).addSymbolEffect(.bounce)
        }
        lastBrightnessEndpoint = endpoint
    }
    
    @objc private func decreaseFont() {
        changeFontSize(by: -1)
    }
    
    @objc private func increaseFont() {
        changeFontSize(by: 1)
    }
    
    private func changeFontSize(by delta: Int) {
        guard isCurrentReader else { return }
        readerMode.setFontSizeStep(
            Prefs.BrowsingSettings.readerViewFontSizeStep + delta,
            for: tabManager.selectedTab?.session
        )
        refreshAppearance()
        fontSizeDotsDismissal?.cancel()
        UIView.animate(withDuration: UX.fadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.fontSizeDots.alpha = 1
        }
        let dismissal = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: UX.fadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self?.fontSizeDots.alpha = 0
            }
        }
        fontSizeDotsDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.dotDelay, execute: dismissal)
    }
    
    @objc private func findInPage() {
        guard isCurrentReader else { return }
        onFindInPage?()
        dismiss(animated: true)
    }
    
    @objc private func hideReader() {
        guard isCurrentReader, let selectedTab = tabManager.selectedTab else { return }
        _ = readerMode.exit(in: selectedTab)
        dismiss(animated: true)
    }
}
