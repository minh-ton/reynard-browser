//
//  PageZoomActionBar.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import UIKit

final class PageZoomActionBar: UIView {
    private enum UX {
        static let backgroundHeight: CGFloat = 62
        static let controlsHeight: CGFloat = 38
        static let controlsWidth: CGFloat = 184
        static let controlButtonWidth: CGFloat = 55
        static let separatorWidth: CGFloat = 1
        static let controlsCornerRadius: CGFloat = 19
        static let closeButtonSize: CGFloat = 28
        static let closeButtonCornerRadius: CGFloat = 14
        static let horizontalInset: CGFloat = 13
        static let percentFontSize: CGFloat = 16
        static let controlSymbolPointSize: CGFloat = 14
        static let closeSymbolPointSize: CGFloat = 10
        static let animationDuration: TimeInterval = 0.12
        static let backgroundAlpha: CGFloat = 0.34
        static let disabledAlpha: CGFloat = 0.32
        static let shadowOpacity: Float = 0.14
        static let shadowRadius: CGFloat = 8
        static let shadowOffset = CGSize(width: 0, height: 3)
        static let borderWidth: CGFloat = 0.5
    }
    
    static let zoomLevels = PageZoomLevels.all
    
    var onZoomOut: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onReset: (() -> Void)?
    var onClose: (() -> Void)?
    
    private(set) var zoomLevel = Prefs.AppearanceSettings.defaultPageZoomLevel
    private var maximumZoomLevel = PageZoomActionBar.zoomLevels.last!
    
    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        return view
    }()
    
    private let controlsShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        return view
    }()
    
    private let controlsBackground: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var zoomOutButton = makeControlButton(named: "reynard.minus", action: #selector(zoomOutTapped))
    private lazy var zoomInButton = makeControlButton(named: "reynard.plus", action: #selector(zoomInTapped))
    
    private lazy var resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = UIFont.systemFont(ofSize: UX.percentFontSize, weight: .regular)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        return button
    }()
    
    private let closeShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.closeButtonCornerRadius
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        return view
    }()
    
    private let closeBackground: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.closeButtonCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.closeSymbolPointSize, weight: .regular)
        button.setImage(UIImage(named: "reynard.xmark", in: .main, with: configuration), for: .normal)
        button.tintColor = .secondaryLabel
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()
    
    private let leadingSeparator = PageZoomActionBar.makeSeparator()
    private let trailingSeparator = PageZoomActionBar.makeSeparator()
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        updateShadowColor()
        updateBorderColor()
        setZoomLevel(zoomLevel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        controlsShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: controlsShadowView.bounds,
            cornerRadius: UX.controlsCornerRadius
        ).cgPath
        closeShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: closeShadowView.bounds,
            cornerRadius: UX.closeButtonCornerRadius
        ).cgPath
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        
        updateShadowColor()
        updateBorderColor()
    }
    
    // MARK: - Updates
    
    func setZoomLevel(_ level: Int) {
        zoomLevel = PageZoomActionBar.zoomLevels.contains(level) ? level : Prefs.AppearanceSettings.defaultPageZoomLevel
        zoomLevel = min(zoomLevel, maximumZoomLevel)
        updateControls()
    }

    func setMaximumZoomLevel(_ level: Int) {
        maximumZoomLevel = PageZoomActionBar.zoomLevels.contains(level)
            ? level
            : PageZoomActionBar.zoomLevels.last!
        zoomLevel = min(zoomLevel, maximumZoomLevel)
        updateControls()
    }

    private func updateControls() {
        resetButton.setTitle(PageZoomLevels.displayText(for: zoomLevel), for: .normal)
        zoomOutButton.isEnabled = zoomLevel > PageZoomActionBar.zoomLevels.first!
        zoomInButton.isEnabled = zoomLevel < maximumZoomLevel
        zoomOutButton.alpha = zoomOutButton.isEnabled ? 1 : UX.disabledAlpha
        zoomInButton.alpha = zoomInButton.isEnabled ? 1 : UX.disabledAlpha
    }
    
    func nextZoomLevel() -> Int {
        guard let index = PageZoomActionBar.zoomLevels.firstIndex(of: zoomLevel) else {
            return Prefs.AppearanceSettings.defaultPageZoomLevel
        }
        let maximumIndex = PageZoomActionBar.zoomLevels.firstIndex(of: maximumZoomLevel)
            ?? PageZoomActionBar.zoomLevels.index(before: PageZoomActionBar.zoomLevels.endIndex)
        return PageZoomActionBar.zoomLevels[min(index + 1, maximumIndex)]
    }
    
    func previousZoomLevel() -> Int {
        guard let index = PageZoomActionBar.zoomLevels.firstIndex(of: zoomLevel) else {
            return Prefs.AppearanceSettings.defaultPageZoomLevel
        }
        return PageZoomActionBar.zoomLevels[max(index - 1, 0)]
    }
    
    // MARK: - Actions
    
    @objc private func zoomOutTapped() {
        onZoomOut?()
    }
    
    @objc private func zoomInTapped() {
        onZoomIn?()
    }
    
    @objc private func resetTapped() {
        onReset?()
    }
    
    @objc private func closeTapped() {
        onClose?()
    }

    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        addSubview(controlsShadowView)
        addSubview(closeShadowView)
        controlsShadowView.addSubview(controlsBackground)
        closeShadowView.addSubview(closeBackground)
        closeShadowView.addSubview(closeButton)
        [zoomOutButton, leadingSeparator, resetButton, trailingSeparator, zoomInButton].forEach {
            controlsBackground.contentView.addSubview($0)
        }
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UX.backgroundHeight),
            
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            controlsShadowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlsShadowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlsShadowView.widthAnchor.constraint(equalToConstant: UX.controlsWidth),
            controlsShadowView.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
            
            controlsBackground.topAnchor.constraint(equalTo: controlsShadowView.topAnchor),
            controlsBackground.leadingAnchor.constraint(equalTo: controlsShadowView.leadingAnchor),
            controlsBackground.trailingAnchor.constraint(equalTo: controlsShadowView.trailingAnchor),
            controlsBackground.bottomAnchor.constraint(equalTo: controlsShadowView.bottomAnchor),
            
            zoomOutButton.leadingAnchor.constraint(equalTo: controlsBackground.contentView.leadingAnchor),
            zoomOutButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            zoomOutButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
            
            leadingSeparator.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor),
            leadingSeparator.centerYAnchor.constraint(equalTo: controlsBackground.contentView.centerYAnchor),
            leadingSeparator.widthAnchor.constraint(equalToConstant: UX.separatorWidth),
            leadingSeparator.heightAnchor.constraint(equalTo: controlsBackground.contentView.heightAnchor, multiplier: 0.42),
            
            resetButton.leadingAnchor.constraint(equalTo: leadingSeparator.trailingAnchor),
            resetButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            resetButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            
            trailingSeparator.leadingAnchor.constraint(equalTo: resetButton.trailingAnchor),
            trailingSeparator.centerYAnchor.constraint(equalTo: controlsBackground.contentView.centerYAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: UX.separatorWidth),
            trailingSeparator.heightAnchor.constraint(equalTo: controlsBackground.contentView.heightAnchor, multiplier: 0.42),
            
            zoomInButton.leadingAnchor.constraint(equalTo: trailingSeparator.trailingAnchor),
            zoomInButton.trailingAnchor.constraint(equalTo: controlsBackground.contentView.trailingAnchor),
            zoomInButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            zoomInButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
            
            closeShadowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.horizontalInset),
            closeShadowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeShadowView.widthAnchor.constraint(equalToConstant: UX.closeButtonSize),
            closeShadowView.heightAnchor.constraint(equalToConstant: UX.closeButtonSize),
            
            closeBackground.topAnchor.constraint(equalTo: closeShadowView.topAnchor),
            closeBackground.leadingAnchor.constraint(equalTo: closeShadowView.leadingAnchor),
            closeBackground.trailingAnchor.constraint(equalTo: closeShadowView.trailingAnchor),
            closeBackground.bottomAnchor.constraint(equalTo: closeShadowView.bottomAnchor),
            
            closeButton.topAnchor.constraint(equalTo: closeShadowView.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: closeShadowView.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: closeShadowView.trailingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: closeShadowView.bottomAnchor),
        ])
    }
    
    private func updateShadowColor() {
        let color: UIColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
        controlsShadowView.layer.shadowColor = color.cgColor
        closeShadowView.layer.shadowColor = color.cgColor
    }
    
    private func updateBorderColor() {
        let color = UIColor.separator.withAlphaComponent(0.2)
        controlsBackground.layer.borderColor = color.cgColor
        closeBackground.layer.borderColor = color.cgColor
    }
    
    private func makeControlButton(named: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.controlSymbolPointSize, weight: .regular)
        button.setImage(UIImage(named: named, in: .main, with: configuration), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    private static func makeSeparator() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }
}
