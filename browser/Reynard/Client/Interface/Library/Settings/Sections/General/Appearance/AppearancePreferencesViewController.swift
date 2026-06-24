//
//  AppearancePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class AppearancePreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let swatchSize = CGSize(width: 22, height: 22)
        static let swatchInset: CGFloat = 2
        static let swatchCornerRadius: CGFloat = 4
        static let swatchStrokeWidth: CGFloat = 1
    }

    private enum Section: CaseIterable {
        case theme
        case accent
        case tabs
        
        var text: SettingsSectionText {
            switch self {
            case .theme:
                return SettingsSectionText(
                    headerTitle: "Theme",
                    footerTitle: "OLED Black uses true black surfaces when the interface is in dark appearance."
                )
            case .accent:
                return SettingsSectionText(
                    headerTitle: "Accent",
                    footerTitle: "Custom colors accept #RRGGBB hex values and must stay visible in light, dark, and OLED Black themes."
                )
            case .tabs:
                return SettingsSectionText(headerTitle: "Tabs")
            }
        }
    }
    
    private enum Row {
        case theme(BrowserThemeMode)
        case accent(BrowserAccentColor)
        case customAccent
        case browserChromePosition
        case landscapeTabBar
    }
    
    private let landscapeTabBarSwitch = UISwitch()
    
    private var displayedSections: [Section] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.theme, .accent]
        }

        return Section.allCases
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Appearance"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitch()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        return rows(for: displayedSections[section]).count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section),
              rows(for: displayedSections[indexPath.section]).indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        switch rows(for: displayedSections[indexPath.section])[indexPath.row] {
        case let .theme(mode):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = mode.displayName
            cell.accessoryType = mode == Prefs.AppearanceSettings.themeMode ? .checkmark : .none
            return cell
        case let .accent(accent):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = accent.displayName
            cell.imageView?.image = swatchImage(color: accent.color, shape: .circle)
            cell.accessoryType = accent == Prefs.AppearanceSettings.accentColor ? .checkmark : .none
            return cell
        case .customAccent:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            let hex = Prefs.AppearanceSettings.customAccentHex
            let isSelected = Prefs.AppearanceSettings.accentColor == .custom
            cell.textLabel?.text = "Custom"
            cell.detailTextLabel?.text = hex
            cell.imageView?.image = swatchImage(color: Prefs.AppearanceSettings.customAccentColor, shape: .square)
            cell.accessoryType = isSelected ? .checkmark : .none
            cell.accessibilityLabel = "Custom accent color"
            cell.accessibilityValue = "\(hex), \(isSelected ? "selected" : "not selected")"
            cell.accessibilityHint = "Opens custom accent color options."
            return cell
        case .browserChromePosition:
            let cell = BrowserChromePositionPickerCell(style: .default, reuseIdentifier: nil)
            cell.display(selectedPosition: Prefs.AppearanceSettings.addressBarPosition)
            cell.onPositionChanged = { position in
                Prefs.AppearanceSettings.addressBarPosition = position
            }
            return cell
        case .landscapeTabBar:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Landscape Tab Bar"
            cell.selectionStyle = .none
            cell.accessoryView = landscapeTabBarSwitch
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard displayedSections.indices.contains(indexPath.section),
              rows(for: displayedSections[indexPath.section]).indices.contains(indexPath.row) else {
            return
        }

        switch rows(for: displayedSections[indexPath.section])[indexPath.row] {
        case let .theme(mode):
            Prefs.AppearanceSettings.themeMode = mode
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        case let .accent(accent):
            Prefs.AppearanceSettings.accentColor = accent
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        case .customAccent:
            presentCustomAccentActions(from: tableView.cellForRow(at: indexPath))
        case .browserChromePosition, .landscapeTabBar:
            return
        }
    }
    
    private func configureSwitch() {
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchDidChange), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        landscapeTabBarSwitch.isOn = Prefs.AppearanceSettings.showsLandscapeTabBar
    }
    
    @objc private func landscapeTabBarSwitchDidChange() {
        Prefs.AppearanceSettings.showsLandscapeTabBar = landscapeTabBarSwitch.isOn
    }

    private func rows(for section: Section) -> [Row] {
        switch section {
        case .theme:
            return BrowserThemeMode.allCases.map(Row.theme)
        case .accent:
            return BrowserAccentColor.presetCases.map(Row.accent) + [.customAccent]
        case .tabs:
            return [.browserChromePosition, .landscapeTabBar]
        }
    }

    private enum SwatchShape {
        case circle
        case square
    }

    private func swatchImage(color: UIColor, shape: SwatchShape) -> UIImage {
        let size = UX.swatchSize
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: UX.swatchInset, dy: UX.swatchInset)
            let path: UIBezierPath
            switch shape {
            case .circle:
                path = UIBezierPath(ovalIn: rect)
            case .square:
                path = UIBezierPath(roundedRect: rect, cornerRadius: UX.swatchCornerRadius)
            }
            color.setFill()
            path.fill()
            UIColor.separator.setStroke()
            path.lineWidth = UX.swatchStrokeWidth
            path.stroke()
        }
    }

    private func presentCustomAccentActions(from sourceView: UIView?) {
        let hex = Prefs.AppearanceSettings.customAccentHex
        let alert = UIAlertController(
            title: "Custom Accent",
            message: "Current color: \(hex)",
            preferredStyle: .actionSheet
        )

        if #available(iOS 14.0, *) {
            alert.addAction(UIAlertAction(title: "Choose Custom Color", style: .default) { [weak self] _ in
                self?.presentCustomColorPicker(sourceView: sourceView)
            })
        }

        alert.addAction(UIAlertAction(title: "Enter Hex Code", style: .default) { [weak self] _ in
            self?.presentCustomHexEntry()
        })
        alert.addAction(UIAlertAction(title: "Use Current Custom Color", style: .default) { [weak self] _ in
            self?.commitCustomAccent(hex: hex, showsError: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController,
           let sourceView {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }

        present(alert, animated: true)
    }

    @available(iOS 14.0, *)
    private func presentCustomColorPicker(sourceView: UIView?) {
        let picker = UIColorPickerViewController()
        picker.title = "Choose Custom Color"
        picker.selectedColor = Prefs.AppearanceSettings.customAccentColor
        picker.supportsAlpha = false
        picker.delegate = self
        picker.modalPresentationStyle = .popover

        if let popover = picker.popoverPresentationController,
           let sourceView {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }

        present(picker, animated: true)
    }

    private func presentCustomHexEntry() {
        let alert = UIAlertController(
            title: "Custom Accent Hex",
            message: "Enter a 6-digit color value.",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = Prefs.AppearanceSettings.customAccentHex
            textField.placeholder = BrowserAccentColor.defaultCustomHex
            textField.keyboardType = .asciiCapable
            textField.autocapitalizationType = .allCharacters
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
            textField.accessibilityLabel = "Custom accent hex code"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self, weak alert] _ in
            let hex = alert?.textFields?.first?.text ?? ""
            self?.commitCustomAccent(hex: hex, showsError: true)
        })
        present(alert, animated: true)
    }

    @discardableResult
    private func commitCustomAccent(hex: String, showsError: Bool) -> Bool {
        guard let normalizedHex = BrowserAccentColor.normalizedCustomHex(hex) else {
            showCustomAccentError("Enter a 6-digit hex color such as #007AFF.", showsError: showsError)
            return false
        }

        let validationMessage = BrowserAccentColor.validationMessage(forCustomHex: normalizedHex)
        guard validationMessage == nil else {
            showCustomAccentError(validationMessage, showsError: showsError)
            return false
        }

        Prefs.AppearanceSettings.customAccentHex = normalizedHex
        Prefs.AppearanceSettings.accentColor = .custom
        reloadAccentSection()
        return true
    }

    @discardableResult
    private func commitCustomAccent(color: UIColor, showsError: Bool) -> Bool {
        let validationMessage = BrowserAccentColor.validationMessage(forCustomColor: color)
        guard validationMessage == nil else {
            showCustomAccentError(validationMessage, showsError: showsError)
            return false
        }

        Prefs.AppearanceSettings.customAccentHex = color.toHexString().uppercased()
        Prefs.AppearanceSettings.accentColor = .custom
        reloadAccentSection()
        return true
    }

    private func showCustomAccentError(_ message: String?, showsError: Bool) {
        guard showsError else { return }
        AlertPresenter.show(
            title: "Invalid Accent Color",
            message: message ?? "Choose a different custom accent color."
        )
    }

    private func reloadAccentSection() {
        guard let section = displayedSections.firstIndex(of: .accent) else {
            tableView.reloadData()
            return
        }

        tableView.reloadSections(IndexSet(integer: section), with: .automatic)
    }
}

@available(iOS 14.0, *)
extension AppearancePreferencesViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        commitCustomAccent(color: viewController.selectedColor, showsError: false)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        commitCustomAccent(color: viewController.selectedColor, showsError: true)
    }
}
