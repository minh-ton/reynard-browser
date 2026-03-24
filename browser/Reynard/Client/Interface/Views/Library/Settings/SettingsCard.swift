//
//  SettingsCard.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit
import UniformTypeIdentifiers

private final class SettingsTextFieldCell: UITableViewCell {
    let textField = UITextField()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        
        contentView.addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomInsets()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomInsets()
    }
    
    private func updateBottomInsets() {
        let bottomInset = view.safeAreaInsets.bottom
        tableView.contentInset.bottom = bottomInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomInset
    }
}

final class SettingsRootViewController: SettingsTableViewController, UIDocumentPickerDelegate {
    private enum Section: Int, CaseIterable {
        case jit
        case search
        case compatibility
        case about
    }
    
    private let jitSwitch = UISwitch()
    private let androidUserAgentSwitch = UISwitch()
    private let backgroundQueue = DispatchQueue(label: "me.minh-ton.reynard.settings.backgroundqueue", qos: .userInitiated)
    private let sourceCodeURL = URL(string: "https://github.com/minh-ton/reynard-browser")
    private let githubProfileURL = URL(string: "https://github.com/minh-ton")
    private let redditProfileURL = URL(string: "https://www.reddit.com/user/Minh-Ton/")
    private var isJITLessModeActive = false
    private var activeDDIDownloadToken: UUID?
    
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
        androidUserAgentSwitch.addTarget(self, action: #selector(androidUserAgentSwitchChanged), for: .valueChanged)
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }
        
        switch section {
        case .jit:
            return 2
        case .search, .compatibility:
            return 1
        case .about:
            return 3
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
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
            return cell
            
        case .search:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Search Engine"
            cell.detailTextLabel?.text = preferences.searchEngineSummary
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case .compatibility:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Use Android User Agent"
            cell.selectionStyle = .none
            cell.accessoryView = androidUserAgentSwitch
            return cell
            
        case .about:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "View Source Code"
            case 1:
                cell.textLabel?.text = "GitHub - @minh-ton"
            case 2:
                cell.textLabel?.text = "Reddit - u/Minh-Ton"
            default:
                cell.textLabel?.text = nil
            }
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard let section = Section(rawValue: indexPath.section) else {
            return
        }
        
        switch section {
        case .jit where indexPath.row == 1:
            presentPairingFilePicker()
            
        case .search:
            navigationController?.pushViewController(SearchEngineSettingsViewController(), animated: true)
            
        case .about:
            let url: URL?
            switch indexPath.row {
            case 0:
                url = sourceCodeURL
            case 1:
                url = githubProfileURL
            case 2:
                url = redditProfileURL
            default:
                url = nil
            }
            
            guard let url else {
                return
            }
            
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        default:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }
        
        switch section {
        case .jit:
            return "JIT"
        case .search:
            return "Search"
        case .compatibility:
            return "Compatibility"
        case .about:
            return "About"
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }
        
        switch section {
        case .jit:
            return nil
        case .search:
            return nil
        case .compatibility:
            return "Compatibility with several websites, such as YouTube, improves when the user agent is set to Firefox on Android. You might see websites identify your device as an Android though."
        case .about:
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let build = info?["CFBundleVersion"] as? String ?? "Unknown"
            let geckoTag = info?["GeckoVersion"] as? String ?? "Unknown"
            return "App Version: \(version) (\(build))\nGecko Release Tag: \(geckoTag)"
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let section = Section(rawValue: section), section == .jit else {
            return nil
        }
        
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true
        
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        
        let footerPointSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        let statusBoldFont = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.systemFont(ofSize: footerPointSize, weight: .semibold))
        
        if isJITLessModeActive {
            let statusLabel = UILabel()
            statusLabel.numberOfLines = 0
            statusLabel.font = statusBoldFont
            statusLabel.adjustsFontForContentSizeCategory = true
            statusLabel.textColor = .systemOrange
            statusLabel.text = "▲ JIT-Less Mode is Currently Active"
            stack.addArrangedSubview(statusLabel)
        }
        
        let detailText = "Enabling JIT improves performance significantly and is required for features like WebAssembly."
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.text = detailText
        stack.addArrangedSubview(detailLabel)
        
        footerView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        
        importPairingFile(from: url)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    
    private func refreshControls() {
        jitSwitch.isEnabled = preferences.hasPairingFile
        jitSwitch.isOn = preferences.isJITEnabled
        androidUserAgentSwitch.isOn = preferences.useAndroidUserAgent
        isJITLessModeActive = JITController.shared.isJITLessModeActive
    }
    
    @objc private func handleJITLessModeActivated(_ notification: Notification) {
        refreshControls()
        tableView.reloadData()
    }
    
    private func presentPairingFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedPairingFileTypes(), asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    private func importPairingFile(from url: URL) {
        backgroundQueue.async { [weak self] in
            guard let self else {
                return
            }
            
            do {
                try self.preferences.installPairingFile(from: url)
                DispatchQueue.main.async {
                    self.refreshControls()
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentAlert(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func jitSwitchChanged(_ sender: UISwitch) {
        let isOn = sender.isOn
        
        preferences.isJITEnabled = isOn
        
        guard isOn else {
            presentJITRestartAlert()
            return
        }
        
        guard !DDIManager.shared.hasRequiredDDIFiles() else {
            presentJITRestartAlert()
            return
        }
        
        presentDDIDownloadAlert(for: sender)
    }
    
    private func presentDDIDownloadAlert(for sender: UISwitch) {
        sender.isEnabled = false
        
        let alert = UIAlertController(
            title: "Preparing JIT",
            message: "Since this is your first time enabling JIT, Reynard needs to download and mount the Developer Disk Image. This is required for JIT to work properly.",
            preferredStyle: .alert
        )
        
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0
        
        let token = UUID()
        activeDDIDownloadToken = token
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.cancelDDIDownload(for: sender, token: token)
        })
        
        present(alert, animated: true) { [weak self] in
            self?.attachProgressView(progressView, to: alert)
            self?.startDDIDownload(for: sender, alert: alert, progressView: progressView, token: token)
        }
    }
    
    private func attachProgressView(_ progressView: UIProgressView, to alert: UIAlertController) {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else {
            return
        }
        
        alert.view.addSubview(progressView)
        let cancelAnchorView: UIView? = {
            if let button = alert.view.firstDescendantButton(withTitle: "Cancel") {
                return button
            }
            
            return alert.view.firstDescendantView(containingLabelText: "Cancel")
        }()
        
        var constraints = [
            progressView.widthAnchor.constraint(equalTo: messageLabel.widthAnchor),
            progressView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            progressView.topAnchor.constraint(greaterThanOrEqualTo: messageLabel.bottomAnchor, constant: 12),
        ]
        
        if let cancelAnchorView {
            let verticalGuide = UILayoutGuide()
            alert.view.addLayoutGuide(verticalGuide)
            constraints.append(contentsOf: [
                verticalGuide.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
                verticalGuide.bottomAnchor.constraint(equalTo: cancelAnchorView.topAnchor, constant: -16),
                progressView.centerYAnchor.constraint(equalTo: verticalGuide.centerYAnchor),
            ])
        } else {
            constraints.append(progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20))
        }
        
        NSLayoutConstraint.activate(constraints)
    }
    
    private func startDDIDownload(for sender: UISwitch, alert: UIAlertController, progressView: UIProgressView, token: UUID) {
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self, self.activeDDIDownloadToken == token else {
                    return
                }
                progressView.setProgress(Float(value), animated: true)
            },
            completion: { [weak self] result in
                guard let self, self.activeDDIDownloadToken == token else {
                    return
                }
                
                self.activeDDIDownloadToken = nil
                sender.isEnabled = self.preferences.hasPairingFile
                
                switch result {
                case .success:
                    self.dismissAlertIfPresented(alert) {
                        self.presentJITRestartAlert()
                    }
                case .failure(let error):
                    self.preferences.isJITEnabled = false
                    sender.setOn(false, animated: true)
                    self.dismissAlertIfPresented(alert) {
                        self.presentAlert(title: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        )
    }
    
    private func cancelDDIDownload(for sender: UISwitch, token: UUID) {
        guard activeDDIDownloadToken == token else {
            return
        }
        
        activeDDIDownloadToken = nil
        DDIManager.shared.cancelActiveDownload()
        preferences.isJITEnabled = false
        sender.setOn(false, animated: true)
        sender.isEnabled = preferences.hasPairingFile
    }
    
    private func dismissAlertIfPresented(_ alert: UIAlertController, completion: @escaping () -> Void) {
        guard presentedViewController === alert else {
            completion()
            return
        }
        
        alert.dismiss(animated: true, completion: completion)
    }
    
    @objc private func androidUserAgentSwitchChanged() {
        preferences.useAndroidUserAgent = androidUserAgentSwitch.isOn
    }
    
    private func presentJITRestartAlert() {
        let alert = UIAlertController(
            title: "Restart Required",
            message: "The app will now close for the JIT setting to take effect.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                exit(EXIT_SUCCESS)
            })
        })
        
        present(alert, animated: true)
    }
}

private final class SearchEngineSettingsViewController: SettingsTableViewController, UITextFieldDelegate {
    init() {
        super.init(style: .insetGrouped)
        title = "Search Engine"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(SettingsTextFieldCell.self, forCellReuseIdentifier: "SettingsTextFieldCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        preferences.searchEngine == .custom ? 2 : 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? BrowserPreferences.SearchEngine.allCases.count : 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTextFieldCell", for: indexPath) as? SettingsTextFieldCell else {
                return UITableViewCell()
            }
            
            cell.textField.delegate = self
            cell.textField.placeholder = "https://example.com/search?q=%s"
            cell.textField.text = preferences.customSearchTemplate
            return cell
        }
        
        let engine = BrowserPreferences.SearchEngine.allCases[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = engine.displayName
        cell.accessoryType = preferences.searchEngine == engine ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard indexPath.section == 0,
              BrowserPreferences.SearchEngine.allCases.indices.contains(indexPath.row) else {
            return
        }
        
        let selectedEngine = BrowserPreferences.SearchEngine.allCases[indexPath.row]
        let wasCustom = preferences.searchEngine == .custom
        preferences.searchEngine = selectedEngine
        
        if wasCustom != (selectedEngine == .custom) {
            tableView.reloadData()
        } else {
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
        
        if selectedEngine == .custom {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as? SettingsTextFieldCell else {
                    return
                }
                
                cell.textField.becomeFirstResponder()
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Search Engine" : nil
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else {
            return nil
        }
        
        let baseText = "Enter URL with %s in place of query"
        guard !preferences.customSearchTemplate.isEmpty,
              !preferences.isCustomSearchTemplateValid else {
            return baseText
        }
        
        return "\(baseText). The current value must be a valid http(s) URL."
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        preferences.customSearchTemplate = textField.text ?? ""
        tableView.reloadData()
        
        let value = preferences.customSearchTemplate
        guard !value.isEmpty,
              !preferences.isCustomSearchTemplateValid else {
            return
        }
        
        presentAlert(
            title: "Invalid Search URL",
            message: "Enter a valid http(s) URL containing %s where the search query should go."
        )
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class SettingsCard: UIView {
    private weak var hostedNavigationController: UINavigationController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        embedNavigationControllerIfNeeded()
    }
    
    private func embedNavigationControllerIfNeeded() {
        guard hostedNavigationController == nil,
              let parentViewController = containingViewController else {
            return
        }
        
        let navigationController = UINavigationController(rootViewController: SettingsRootViewController())
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false
        navigationController.view.backgroundColor = .clear
        
        parentViewController.addChild(navigationController)
        addSubview(navigationController.view)
        
        NSLayoutConstraint.activate([
            navigationController.view.topAnchor.constraint(equalTo: topAnchor),
            navigationController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        navigationController.didMove(toParent: parentViewController)
        hostedNavigationController = navigationController
    }
}

private func allowedPairingFileTypes() -> [UTType] {
    var types = [UTType.propertyList]
    
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { fileExtension in
        if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
            types.append(type)
        }
    }
    
    return types
}

extension UIViewController {
    func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private extension UIView {
    var containingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
    
    func firstDescendantLabel(withText text: String) -> UILabel? {
        if let label = self as? UILabel,
           label.text == text {
            return label
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantLabel(withText: text) {
                return match
            }
        }
        
        return nil
    }
    
    func firstDescendantButton(withTitle title: String) -> UIButton? {
        if let button = self as? UIButton,
           button.currentTitle == title {
            return button
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantButton(withTitle: title) {
                return match
            }
        }
        
        return nil
    }
    
    func firstDescendantView(containingLabelText text: String) -> UIView? {
        if subviews.contains(where: { ($0 as? UILabel)?.text == text }) {
            return self
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantView(containingLabelText: text) {
                return match
            }
        }
        
        return nil
    }
}
