//
//  SettingsView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

class SettingsTableViewController: UITableViewController {
    let preferences = BrowserPreferences.shared
    
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
        case jit
        case search
        case tab
        case compatibility
        case about
    }
    
    var visibleSections: [Section] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Section.allCases.filter { $0 != .tab }
        }
        
        // if using Trollstore or jailbroken, hide JIT section
        if getEntitlementValue("com.apple.private.security.no-sandbox") {
            return Section.allCases.filter { $0 != .jit }
        }
        
        return Section.allCases
    }
    
    let jitSwitch = UISwitch()
    let landscapeTabBarSwitch = UISwitch()
    let backgroundQueue = DispatchQueue(label: "me.minh-ton.reynard.settings.backgroundqueue", qos: .userInitiated)
    var isJITLessModeActive = false
    var activeDDIDownloadToken: UUID?
    
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
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchChanged), for: .valueChanged)
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
        jitSwitch.isEnabled = preferences.hasPairingFile
        jitSwitch.isOn = preferences.isJITEnabled
        landscapeTabBarSwitch.isOn = preferences.showsLandscapeTabBar
        isJITLessModeActive = JITController.shared.isJITLessModeActive
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else { return 0 }
        switch visibleSections[section] {
        case .jit: return 2
        case .search, .compatibility: return 1
        case .tab: return 2
        case .about: return 3
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else { return UITableViewCell() }
        switch visibleSections[indexPath.section] {
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
        case .search:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Search Engine"
            cell.detailTextLabel?.text = preferences.searchEngineSummary
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        case .tab:
            if indexPath.row == 0 {
                let cell = AddressBarPositionPickerCell(style: .default, reuseIdentifier: nil)
                cell.configure(selectedPosition: preferences.addressBarPosition)
                cell.onSelectionChanged = { [weak self] position in
                    self?.preferences.addressBarPosition = position
                }
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Landscape Tab Bar"
                cell.selectionStyle = .none
                cell.accessoryView = landscapeTabBarSwitch
                return cell
            }
        case .compatibility:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "User Agent Override"
            cell.accessoryType = .disclosureIndicator
            return cell
        case .about:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            switch indexPath.row {
            case 0: cell.textLabel?.text = "View Source Code"
            case 1: cell.textLabel?.text = "GitHub - @minh-ton"
            case 2: cell.textLabel?.text = "Reddit - u/Minh-Ton"
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
        case .jit where indexPath.row == 1:
            presentPairingFilePicker()
        case .search:
            navigationController?.pushViewController(SearchEngineSettingsViewController(), animated: true)
        case .compatibility:
            navigationController?.pushViewController(UserAgentOverrideViewController(), animated: true)
        case .tab:
            break
        case .about:
            let url: URL?
            switch indexPath.row {
            case 0: url = sourceCodeURL
            case 1: url = githubProfileURL
            case 2: url = redditProfileURL
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
        case .jit: return "JIT"
        case .search: return "Search"
        case .tab: return "Tabs"
        case .compatibility: return "Compatibility"
        case .about: return "About"
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else { return nil }
        switch visibleSections[section] {
        case .jit, .search, .tab, .compatibility: return nil
        case .about:
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let build = info?["CFBundleVersion"] as? String ?? "Unknown"
            let geckoTag = info?["GeckoVersion"] as? String ?? "Unknown"
            return "App Version: \(version) (\(build))\nGecko Release Tag: \(geckoTag)"
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard visibleSections.indices.contains(section), visibleSections[section] == .jit else { return nil }
        return makeJITFooterView()
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
    func presentAlert(title: String, message: String) {
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
