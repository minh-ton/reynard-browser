import UIKit

struct DefaultBrowserSettingsSection {
    var rowCount: Int {
        return 1
    }

    func cell(at index: Int) -> UITableViewCell {
        guard index == 0 else {
            return UITableViewCell()
        }

        return SettingsViewUtils.disclosureCell(
            title: NSLocalizedString("Set as Default Browser", comment: "")
        )
    }

    func selectRow(at index: Int) {
        guard index == 0 else {
            return
        }

        let destination = DefaultBrowserSettingsPolicy.destination(
            for: ProcessInfo.processInfo.operatingSystemVersion
        )
        let settingsURLString: String

        switch destination {
        case .applicationSettings:
            settingsURLString = UIApplication.openSettingsURLString
        case .defaultApplicationsSettings:
            if #available(iOS 18.3, *) {
                settingsURLString = UIApplication.openDefaultApplicationsSettingsURLString
            } else {
                settingsURLString = UIApplication.openSettingsURLString
            }
        }

        guard let settingsURL = URL(string: settingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
    }
}
