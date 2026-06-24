//
//  BrowserAppearance.swift
//  Reynard
//
//  Created by Reynard on 23/6/26.
//

import UIKit

enum BrowserThemeMode: String, CaseIterable {
    case system
    case light
    case dark
    case oledBlack

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .oledBlack:
            return "OLED Black"
        }
    }

    var overrideStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark, .oledBlack:
            return .dark
        }
    }
}

enum BrowserAccentColor: String, CaseIterable {
    case highContrast
    case blue
    case orange
    case green
    case purple
    case custom

    static let defaultCustomHex = "#007AFF"
    private static let minimumCustomContrastRatio: CGFloat = 1.35

    static var presetCases: [BrowserAccentColor] {
        [.highContrast, .blue, .orange, .green, .purple]
    }

    var displayName: String {
        switch self {
        case .highContrast:
            return "High Contrast"
        case .blue:
            return "Blue"
        case .orange:
            return "Orange"
        case .green:
            return "Green"
        case .purple:
            return "Purple"
        case .custom:
            return "Custom"
        }
    }

    var color: UIColor {
        switch self {
        case .highContrast:
            return .label
        case .blue:
            return .systemBlue
        case .orange:
            return .systemOrange
        case .green:
            return .systemGreen
        case .purple:
            return .systemPurple
        case .custom:
            return Prefs.AppearanceSettings.customAccentColor
        }
    }

    static func normalizedCustomHex(_ hexString: String) -> String? {
        UIColor(hexString: hexString)?.toHexString().uppercased()
    }

    static func validationMessage(forCustomHex hexString: String) -> String? {
        guard let color = UIColor(hexString: hexString) else {
            return "Enter a 6-digit hex color such as #007AFF."
        }

        return validationMessage(forCustomColor: color)
    }

    static func validationMessage(forCustomColor color: UIColor) -> String? {
        guard let components = color.rgbaComponents(in: .current) else {
            return "Choose a standard RGB color."
        }

        guard components.alpha >= 0.95 else {
            return "Accent colors must be opaque."
        }

        let backgrounds: [(String, UIColor, UITraitCollection)] = [
            ("Light", .systemBackground, UITraitCollection(userInterfaceStyle: .light)),
            ("Dark", .systemBackground, UITraitCollection(userInterfaceStyle: .dark)),
            ("OLED Black", .black, UITraitCollection(userInterfaceStyle: .dark)),
        ]

        for (name, background, traitCollection) in backgrounds {
            guard let contrast = contrastRatio(
                foreground: color,
                background: background,
                traitCollection: traitCollection
            ) else {
                continue
            }

            if contrast < minimumCustomContrastRatio {
                return "Choose a color with more contrast against \(name) backgrounds, or use High Contrast."
            }
        }

        return nil
    }

    private static func contrastRatio(
        foreground: UIColor,
        background: UIColor,
        traitCollection: UITraitCollection
    ) -> CGFloat? {
        guard let foregroundComponents = foreground.rgbaComponents(in: traitCollection),
              let backgroundComponents = background.rgbaComponents(in: traitCollection) else {
            return nil
        }

        let foregroundLuminance = relativeLuminance(
            red: foregroundComponents.red,
            green: foregroundComponents.green,
            blue: foregroundComponents.blue
        )
        let backgroundLuminance = relativeLuminance(
            red: backgroundComponents.red,
            green: backgroundComponents.green,
            blue: backgroundComponents.blue
        )
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func component(_ value: CGFloat) -> CGFloat {
            value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * component(red) + 0.7152 * component(green) + 0.0722 * component(blue)
    }
}

enum BrowserAppearance {
    static func apply(to window: UIWindow?) {
        guard let window else { return }
        window.overrideUserInterfaceStyle = Prefs.AppearanceSettings.themeMode.overrideStyle
        window.tintColor = accentColor
        window.rootViewController?.view.tintColor = accentColor
    }

    static var accentColor: UIColor {
        Prefs.AppearanceSettings.accentColor.color
    }

    static var backgroundColor: UIColor {
        dynamicColor(oled: .black, standard: .systemBackground)
    }

    static var groupedBackgroundColor: UIColor {
        dynamicColor(oled: .black, standard: .systemGroupedBackground)
    }

    static var toolbarBackgroundColor: UIColor {
        dynamicColor(oled: .black, standard: .systemGray6)
    }

    static var surfaceColor: UIColor {
        dynamicColor(oled: UIColor(white: 0.04, alpha: 1), standard: .systemBackground)
    }

    static var secondarySurfaceColor: UIColor {
        dynamicColor(oled: UIColor(white: 0.08, alpha: 1), standard: .secondarySystemBackground)
    }

    private static func dynamicColor(oled: UIColor, standard: UIColor) -> UIColor {
        UIColor { traitCollection in
            guard Prefs.AppearanceSettings.themeMode == .oledBlack,
                  traitCollection.userInterfaceStyle == .dark else {
                return standard
            }
            return oled
        }
    }
}

private extension UIColor {
    func rgbaComponents(in traitCollection: UITraitCollection) -> (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    )? {
        let color = resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return (red, green, blue, alpha)
    }
}
