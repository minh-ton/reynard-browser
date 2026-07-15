import Foundation

enum DefaultBrowserSettingsDestination: Equatable {
    case applicationSettings
    case defaultApplicationsSettings
}

enum DefaultBrowserSettingsPolicy {
    static func destination(
        for operatingSystemVersion: OperatingSystemVersion
    ) -> DefaultBrowserSettingsDestination {
        if operatingSystemVersion.majorVersion > 18 ||
            (operatingSystemVersion.majorVersion == 18 && operatingSystemVersion.minorVersion >= 3) {
            return .defaultApplicationsSettings
        }

        return .applicationSettings
    }
}
