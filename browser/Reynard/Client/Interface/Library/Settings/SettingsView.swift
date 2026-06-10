//
//  SettingsView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import GeckoView
import UIKit

class SettingsTableViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .interactive
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
    }
}

final class SettingsRootViewController: SettingsTableViewController {
    enum Section: Int, CaseIterable {
        case updates
        case jit
        case general
        case privacy
        case about
    }
    
    enum GeneralRow: CaseIterable {
        case addons
        case browsing
        case search
        case appearance
        case compatibility
    }
    
    enum PrivacyRow: CaseIterable {
        case sitePermissions
    }
    
    var visibleSections: [Section] {
        var hiddenSections: Set<Section> = []
        let unsandboxed = getEntitlementValue("com.apple.private.security.no-sandbox")
        
        if !AppUpdates.shared.hasUpdate || (unsandboxed && !installedThroughTrollStore) {
            hiddenSections.insert(.updates)
        }
        
        // if using Trollstore or jailbroken, hide JIT section
        if unsandboxed {
            hiddenSections.insert(.jit)
        }
        
        return Section.allCases.filter { !hiddenSections.contains($0) }
    }
    
    var hasEntitledJIT: Bool {
        getEntitlementValue("com.apple.private.security.no-sandbox")
    }
    
    let jitSwitch = UISwitch()
    let backgroundQueue = DispatchQueue(label: "com.minh-ton.settings-background-queue", qos: .userInitiated)
    var isJITLessModeActive = false
    var activeDDIDownloadToken: UUID?
    var activeUpdateTask: URLSessionDownloadTask?
    var updateProgressObservation: NSKeyValueObservation?
    
    init() {
        super.init(style: .insetGrouped)
        title = "Settings"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        jitSwitch.addTarget(self, action: #selector(jitSwitchChanged(_:)), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJITLessModeActivated(_:)),
            name: Notification.Name(rawValue: "me.minh-ton.reynard.jitless-mode-activated"),
            object: nil
        )
        refreshControls()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshControls()
        tableView.reloadData()
    }
    
    func refreshControls() {
        jitSwitch.isEnabled = Prefs.JITSettings.hasPairingFile
        jitSwitch.isOn = Prefs.JITSettings.isJITEnabled
        isJITLessModeActive = JITController.shared.isJITLessModeActive
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else { return 0 }
        switch visibleSections[section] {
        case .updates: return 2
        case .jit: return 2
        case .general: return GeneralRow.allCases.count
        case .privacy: return PrivacyRow.allCases.count
        case .about: return 5
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else { return UITableViewCell() }
        switch visibleSections[indexPath.section] {
        case .updates where indexPath.row == 0:
            return makeReleaseNotesCell()
        case .updates:
            return makeUpdateNowCell()
        case .jit where indexPath.row == 0:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Enable JIT"
            cell.selectionStyle = .none
            cell.accessoryView = jitSwitch
            return cell
        case .jit:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Import Pairing File..."
            cell.textLabel?.textColor = view.tintColor
            // if on 16.6 to 17.3.1, disable the cell.
            if #available(iOS 16.6, *) {
                if #unavailable(iOS 17.4) {
                    cell.textLabel?.textColor = .secondaryLabel
                    cell.selectionStyle = .none
                    cell.isUserInteractionEnabled = false
                }
            }
            return cell
        case .general:
            return makeGeneralCell(for: indexPath)
        case .privacy:
            return makePrivacyCell(for: indexPath)
        case .about:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            switch indexPath.row {
            case 0:
                let info = Bundle.main.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
                let build = info?["CFBundleVersion"] as? String ?? "Unknown"
                cell.textLabel?.text = "Reynard Browser"
                cell.detailTextLabel?.text = "\(version) (\(build))"
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none
                cell.accessoryType = .none
                return cell
            case 1:
                cell.textLabel?.text = "Engine Version"
                cell.detailTextLabel?.text = GeckoRuntime.version
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none
                cell.accessoryType = .none
                return cell
            case 2: cell.textLabel?.text = "View Source Code"
            case 3: cell.textLabel?.text = "Support The Project"
            case 4: cell.textLabel?.text = "GitHub - @minh-ton"
            default: cell.textLabel?.text = nil
            }
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard visibleSections.indices.contains(indexPath.section) else { return }
        switch visibleSections[indexPath.section] {
        case .updates:
            if indexPath.row == 1 { presentUpdateAlert() }
        case .jit where indexPath.row == 1:
            presentPairingFilePicker()
        case .general:
            handleGeneralSelection(at: indexPath)
        case .privacy:
            handlePrivacySelection(at: indexPath)
        case .about:
            let url: URL?
            switch indexPath.row {
            case 2: url = sourceCodeURL
            case 3: url = supportProjectURL
            case 4: url = githubProfileURL
            default: url = nil
            }
            guard let url else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        default:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else { return nil }
        switch visibleSections[section] {
        case .updates: return "Update Available"
        case .jit: return "JIT"
        case .general: return "General"
        case .privacy: return "Privacy"
        case .about: return "About"
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard visibleSections.indices.contains(section) else { return nil }
        switch visibleSections[section] {
        case .updates where installedThroughTrollStore:
            return makeTrollStoreUpdateFooterView()
        case .jit:
            return makeJITFooterView()
        default:
            return nil
        }
    }
}

private extension SettingsRootViewController {
    func makeGeneralCell(for indexPath: IndexPath) -> UITableViewCell {
        let rows = GeneralRow.allCases
        guard rows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = rows[indexPath.row]
        switch row {
        case .addons:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Add-ons"
            cell.accessoryType = .disclosureIndicator
            return cell
        case .browsing:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Browsing"
            cell.accessoryType = .disclosureIndicator
            return cell
        case .search:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Search"
            cell.accessoryType = .disclosureIndicator
            return cell
        case .appearance:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Appearance"
            cell.accessoryType = .disclosureIndicator
            return cell
        case .compatibility:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Compatibility"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    func handleGeneralSelection(at indexPath: IndexPath) {
        let rows = GeneralRow.allCases
        guard rows.indices.contains(indexPath.row) else {
            return
        }
        
        let row = rows[indexPath.row]
        switch row {
        case .addons:
            navigationController?.pushViewController(AddonsPreferencesViewController(), animated: true)
        case .browsing:
            navigationController?.pushViewController(BrowsingPreferencesViewController(), animated: true)
        case .search:
            navigationController?.pushViewController(SearchPreferencesViewController(), animated: true)
        case .appearance:
            navigationController?.pushViewController(AppearancePreferencesViewController(), animated: true)
        case .compatibility:
            navigationController?.pushViewController(CompatibilityPreferencesViewController(), animated: true)
        }
    }
    
    func makePrivacyCell(for indexPath: IndexPath) -> UITableViewCell {
        let rows = PrivacyRow.allCases
        guard rows.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = rows[indexPath.row]
        switch row {
        case .sitePermissions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Site Permissions"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    func handlePrivacySelection(at indexPath: IndexPath) {
        let rows = PrivacyRow.allCases
        guard rows.indices.contains(indexPath.row) else {
            return
        }
        
        switch rows[indexPath.row] {
        case .sitePermissions:
            navigationController?.pushViewController(SitePermissionsViewController(), animated: true)
        }
    }
}

final class SettingsView: UIView {
    private weak var hostedViewController: SettingsRootViewController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        embedViewControllerIfNeeded()
    }
    
    private func embedViewControllerIfNeeded() {
        guard hostedViewController == nil,
              let parentViewController = containingViewController else { return }
        let settingsVC = SettingsRootViewController()
        settingsVC.view.translatesAutoresizingMaskIntoConstraints = false
        settingsVC.view.backgroundColor = .clear
        parentViewController.addChild(settingsVC)
        addSubview(settingsVC.view)
        NSLayoutConstraint.activate([
            settingsVC.view.topAnchor.constraint(equalTo: topAnchor),
            settingsVC.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsVC.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsVC.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        settingsVC.didMove(toParent: parentViewController)
        hostedViewController = settingsVC
    }
}

extension UIViewController {
    func presentAlert(title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension UIView {
    func firstDescendantLabel(withText text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text { return label }
        for subview in subviews {
            if let match = subview.firstDescendantLabel(withText: text) { return match }
        }
        return nil
    }
    
    func firstDescendantButton(withTitle title: String) -> UIButton? {
        if let button = self as? UIButton, button.currentTitle == title { return button }
        for subview in subviews {
            if let match = subview.firstDescendantButton(withTitle: title) { return match }
        }
        return nil
    }
    
    func firstDescendantView(containingLabelText text: String) -> UIView? {
        if subviews.contains(where: { ($0 as? UILabel)?.text == text }) { return self }
        for subview in subviews {
            if let match = subview.firstDescendantView(containingLabelText: text) { return match }
        }
        return nil
    }
}

private extension UIView {
    var containingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
}
