//
//  DNSOverHTTPSPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/9/26.
//

import UIKit

final class DNSOverHTTPSPreferencesViewController: SettingsTableViewController, UITextFieldDelegate {
    private enum UX {
        static let footerHorizontalPadding: CGFloat = 20
        static let footerVerticalPadding: CGFloat = 8
        static let subtitleLineCount = 0
    }
    
    private enum Section: CaseIterable {
        case dnsOverHTTPS
        case secureDNSProvider
        case exceptions
    }
    
    private enum ProtectionRow: CaseIterable {
        case defaultProtection
        case increasedProtection
        case maxProtection
        case noProtection
        
        var protectionLevel: DNSOverHTTPSProtectionLevel {
            switch self {
            case .defaultProtection:
                return .defaultProtection
            case .increasedProtection:
                return .increasedProtection
            case .maxProtection:
                return .maxProtection
            case .noProtection:
                return .noProtection
            }
        }
        
        var title: String {
            switch self {
            case .defaultProtection:
                return NSLocalizedString("Default Protection", comment: "DoH protection level")
            case .increasedProtection:
                return NSLocalizedString("Increased Protection", comment: "DoH protection level")
            case .maxProtection:
                return NSLocalizedString("Max Protection", comment: "DoH protection level")
            case .noProtection:
                return NSLocalizedString("No Protection", comment: "DoH protection level")
            }
        }
        
        var subtitle: String {
            switch self {
            case .defaultProtection:
                return NSLocalizedString("Uses secure DNS when appropriate to protect your privacy.", comment: "")
            case .increasedProtection:
                return NSLocalizedString("Uses your selected secure DNS provider whenever possible. If it’s unavailable, your system DNS is used.", comment: "")
            case .maxProtection:
                return NSLocalizedString("Always uses your selected secure DNS provider. If it’s unavailable, websites may not load.", comment: "")
            case .noProtection:
                return NSLocalizedString("Uses your system DNS.", comment: "")
            }
        }
    }
    
    private enum ExceptionRow {
        case website(String)
        case addWebsite
    }
    
    private enum CustomProviderValidation {
        case empty
        case valid(String)
        case nonHTTPS
        case invalidURL
        
        var errorMessage: String? {
            switch self {
            case .empty, .valid:
                return nil
            case .nonHTTPS:
                return NSLocalizedString("URL must start with “https://”", comment: "")
            case .invalidURL:
                return NSLocalizedString("Invalid URL", comment: "")
            }
        }
    }
    
    private var displayedProtectionLevel = Prefs.DNSOverHTTPSPreferences.protectionLevel
    private var exceptions = Prefs.DNSOverHTTPSPreferences.exceptions
    private var customProviderValidationMessage: String?
    private weak var customProviderValidationLabel: UILabel?
    private weak var customProviderValidationTopConstraint: NSLayoutConstraint?
    private weak var customProviderValidationBottomConstraint: NSLayoutConstraint?
    private weak var exceptionAddAction: UIAlertAction?
    
    private var displaysProviderSection: Bool {
        return displayedProtectionLevel == .increasedProtection || displayedProtectionLevel == .maxProtection
    }
    
    private var displayedSections: [Section] {
        return displaysProviderSection ? Section.allCases : [.dnsOverHTTPS, .exceptions]
    }
    
    private var exceptionRows: [ExceptionRow] {
        return exceptions.map(ExceptionRow.website) + [.addWebsite]
    }
    
    // MARK: - Lifecycle
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("DNS over HTTPS", tableName: "SettingsLocalizable", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(CustomNewTabURLCell.self, forCellReuseIdentifier: "CustomSecureDNSProviderCell")
        if Prefs.DNSOverHTTPSPreferences.provider == .custom {
            switch validateCustomProvider(Prefs.DNSOverHTTPSPreferences.customProviderURL) {
            case .valid:
                break
            case .empty, .nonHTTPS, .invalidURL:
                Prefs.DNSOverHTTPSPreferences.provider = .cloudflare
                DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
            }
        }
    }
    
    // MARK: - Table Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        
        switch displayedSections[section] {
        case .dnsOverHTTPS:
            return ProtectionRow.allCases.count
        case .secureDNSProvider:
            return SecureDNSProvider.allCases.count
        case .exceptions:
            return exceptionRows.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        switch displayedSections[section] {
        case .dnsOverHTTPS:
            return SettingsSectionText(
                headerTitle: NSLocalizedString("DNS over HTTPS", tableName: "SettingsLocalizable", comment: ""),
                footerTitle: NSLocalizedString("Domain Name System (DNS) over HTTPS sends your request for a domain name through an encrypted connection, providing a secure DNS and making it harder for others to see which website you're about to access.", tableName: "SettingsLocalizable", comment: "")
            )
        case .secureDNSProvider:
            return SettingsSectionText(headerTitle: NSLocalizedString("Secure DNS Provider", comment: ""))
        case .exceptions:
            return SettingsSectionText(
                headerTitle: NSLocalizedString("Exceptions", comment: ""),
                footerTitle: NSLocalizedString("Secure DNS won’t be used on these websites or their subdomains.", comment: "")
            )
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .dnsOverHTTPS:
            guard ProtectionRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            return protectionCell(for: ProtectionRow.allCases[indexPath.row])
        case .secureDNSProvider:
            guard SecureDNSProvider.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            return providerCell(for: SecureDNSProvider.allCases[indexPath.row])
        case .exceptions:
            guard exceptionRows.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            return exceptionCell(for: exceptionRows[indexPath.row])
        }
    }
    
    // MARK: - Table Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch displayedSections[indexPath.section] {
        case .dnsOverHTTPS:
            guard ProtectionRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            selectProtectionLevel(ProtectionRow.allCases[indexPath.row].protectionLevel)
        case .secureDNSProvider:
            guard SecureDNSProvider.allCases.indices.contains(indexPath.row) else {
                return
            }
            selectProvider(SecureDNSProvider.allCases[indexPath.row])
        case .exceptions:
            guard exceptionRows.indices.contains(indexPath.row),
                  case .addWebsite = exceptionRows[indexPath.row] else {
                return
            }
            promptForException()
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .exceptions,
              exceptionRows.indices.contains(indexPath.row),
              case .website = exceptionRows[indexPath.row] else {
            return nil
        }
        
        let clearAction = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Clear", comment: "Swipe action")
        ) { [weak self] _, _, completion in
            guard let self, self.exceptions.indices.contains(indexPath.row) else {
                completion(false)
                return
            }
            self.exceptions.remove(at: indexPath.row)
            Prefs.DNSOverHTTPSPreferences.exceptions = self.exceptions
            DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [clearAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard displayedSections.indices.contains(section),
              displayedSections[section] == .secureDNSProvider else {
            return nil
        }
        
        let footer = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.text = customProviderValidationMessage
        label.isHidden = customProviderValidationMessage == nil
        footer.addSubview(label)
        customProviderValidationLabel = label
        let topConstraint = label.topAnchor.constraint(
            equalTo: footer.topAnchor,
            constant: customProviderValidationMessage == nil ? 0 : UX.footerVerticalPadding
        )
        let bottomConstraint = label.bottomAnchor.constraint(
            equalTo: footer.bottomAnchor,
            constant: customProviderValidationMessage == nil ? 0 : -UX.footerVerticalPadding
        )
        customProviderValidationTopConstraint = topConstraint
        customProviderValidationBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: UX.footerHorizontalPadding),
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -UX.footerHorizontalPadding),
            topConstraint,
            bottomConstraint,
        ])
        return footer
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard displayedSections.indices.contains(section),
              displayedSections[section] == .secureDNSProvider else {
            return UITableView.automaticDimension
        }
        return customProviderValidationMessage == nil ? CGFloat.leastNormalMagnitude : UITableView.automaticDimension
    }
    
    // MARK: - Text Field Delegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let validation = validateCustomProvider(textField.text ?? "")
        switch validation {
        case .empty:
            resetCustomProvider()
            textField.text = ""
            textField.resignFirstResponder()
            return true
        case .valid(let url):
            Prefs.DNSOverHTTPSPreferences.customProviderURL = url
            Prefs.DNSOverHTTPSPreferences.provider = .custom
            DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
            textField.text = url
            setCustomProviderValidationMessage(nil)
            updateProviderCheckmarks()
            textField.resignFirstResponder()
            return true
        case .nonHTTPS, .invalidURL:
            setCustomProviderValidationMessage(validation.errorMessage)
            return false
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if case .empty = validateCustomProvider(textField.text ?? "") {
            resetCustomProvider()
        }
        setCustomProviderValidationMessage(nil)
        textField.text = Prefs.DNSOverHTTPSPreferences.customProviderURL
    }
    
    // MARK: - Cells
    
    private func protectionCell(for row: ProtectionRow) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = UX.subtitleLineCount
        cell.accessoryType = row.protectionLevel == displayedProtectionLevel ? .checkmark : .none
        return cell
    }
    
    private func providerCell(for provider: SecureDNSProvider) -> UITableViewCell {
        if provider == .custom {
            return customProviderCell()
        }
        
        let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
        switch provider {
        case .cloudflare:
            cell.textLabel?.text = "Cloudflare"
        case .nextDNS:
            cell.textLabel?.text = "NextDNS"
        case .quad9:
            cell.textLabel?.text = "Quad9"
        case .adGuardDNS:
            cell.textLabel?.text = "AdGuardDNS"
        case .foundationForAppliedPrivacy:
            cell.textLabel?.text = "Foundation For Applied Privacy"
        case .njalla:
            cell.textLabel?.text = "Njalla"
        case .custom:
            break
        }
        cell.accessoryType = provider == Prefs.DNSOverHTTPSPreferences.provider ? .checkmark : .none
        return cell
    }
    
    private func customProviderCell() -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "CustomSecureDNSProviderCell") as? CustomNewTabURLCell else {
            return UITableViewCell()
        }
        cell.textField.delegate = self
        cell.textField.placeholder = NSLocalizedString("Custom", comment: "")
        cell.textField.text = Prefs.DNSOverHTTPSPreferences.customProviderURL
        cell.textField.removeTarget(self, action: #selector(customProviderTextDidChange(_:)), for: .editingChanged)
        cell.textField.addTarget(self, action: #selector(customProviderTextDidChange(_:)), for: .editingChanged)
        cell.accessoryType = Prefs.DNSOverHTTPSPreferences.provider == .custom ? .checkmark : .none
        return cell
    }
    
    private func exceptionCell(for row: ExceptionRow) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
        switch row {
        case .website(let website):
            cell.textLabel?.text = website
            cell.selectionStyle = .none
        case .addWebsite:
            cell.textLabel?.text = NSLocalizedString("Add Website…", comment: "")
            cell.textLabel?.textColor = tableView.tintColor
        }
        return cell
    }
    
    // MARK: - Selection
    
    private func selectProtectionLevel(_ protectionLevel: DNSOverHTTPSProtectionLevel) {
        guard displayedProtectionLevel != protectionLevel else {
            return
        }
        
        view.endEditing(true)
        let showedProviderSection = displaysProviderSection
        Prefs.DNSOverHTTPSPreferences.protectionLevel = protectionLevel
        DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
        
        for indexPath in tableView.indexPathsForVisibleRows ?? [] where indexPath.section == 0 {
            guard ProtectionRow.allCases.indices.contains(indexPath.row) else {
                continue
            }
            let row = ProtectionRow.allCases[indexPath.row]
            tableView.cellForRow(at: indexPath)?.accessoryType = row.protectionLevel == protectionLevel ? .checkmark : .none
        }
        
        let showsProviderSection = protectionLevel == .increasedProtection || protectionLevel == .maxProtection
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.tableView.performBatchUpdates {
                self.displayedProtectionLevel = protectionLevel
                if showedProviderSection, !showsProviderSection {
                    self.tableView.deleteSections(IndexSet(integer: 1), with: .fade)
                } else if !showedProviderSection, showsProviderSection {
                    self.tableView.insertSections(IndexSet(integer: 1), with: .fade)
                }
            }
        }
    }
    
    private func selectProvider(_ provider: SecureDNSProvider) {
        if provider == .custom {
            focusCustomProviderField()
            return
        }
        
        view.endEditing(true)
        guard Prefs.DNSOverHTTPSPreferences.provider != provider else {
            return
        }
        Prefs.DNSOverHTTPSPreferences.provider = provider
        DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
        updateProviderCheckmarks()
    }
    
    private func updateProviderCheckmarks() {
        guard let section = displayedSections.firstIndex(of: .secureDNSProvider) else {
            return
        }
        for indexPath in tableView.indexPathsForVisibleRows ?? [] where indexPath.section == section {
            guard SecureDNSProvider.allCases.indices.contains(indexPath.row) else {
                continue
            }
            let provider = SecureDNSProvider.allCases[indexPath.row]
            tableView.cellForRow(at: indexPath)?.accessoryType = provider == Prefs.DNSOverHTTPSPreferences.provider ? .checkmark : .none
        }
    }
    
    // MARK: - Custom Provider
    
    private func focusCustomProviderField() {
        guard let section = displayedSections.firstIndex(of: .secureDNSProvider),
              let row = SecureDNSProvider.allCases.firstIndex(of: .custom),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: section)) as? CustomNewTabURLCell else {
            return
        }
        cell.textField.becomeFirstResponder()
    }
    
    @objc private func customProviderTextDidChange(_ sender: UITextField) {
        if case .empty = validateCustomProvider(sender.text ?? "") {
            resetCustomProvider()
            return
        }
        guard customProviderValidationMessage != nil else {
            return
        }
        setCustomProviderValidationMessage(validateCustomProvider(sender.text ?? "").errorMessage)
    }
    
    private func validateCustomProvider(_ value: String) -> CustomProviderValidation {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        guard value.hasPrefix("https://") else {
            return .nonHTTPS
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              url.scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return .invalidURL
        }
        return .valid(url.absoluteString)
    }
    
    private func resetCustomProvider() {
        Prefs.DNSOverHTTPSPreferences.customProviderURL = ""
        Prefs.DNSOverHTTPSPreferences.provider = .cloudflare
        DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
        setCustomProviderValidationMessage(nil)
        updateProviderCheckmarks()
    }
    
    private func setCustomProviderValidationMessage(_ message: String?) {
        guard customProviderValidationMessage != message else {
            return
        }
        customProviderValidationMessage = message
        customProviderValidationLabel?.text = message
        customProviderValidationLabel?.isHidden = message == nil
        customProviderValidationTopConstraint?.constant = message == nil ? 0 : UX.footerVerticalPadding
        customProviderValidationBottomConstraint?.constant = message == nil ? 0 : -UX.footerVerticalPadding
        guard displayedSections.contains(.secureDNSProvider) else {
            return
        }
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
    }
    
    // MARK: - Exceptions
    
    private func promptForException() {
        let alert = UIAlertController(
            title: NSLocalizedString("Add Website", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] field in
            field.placeholder = NSLocalizedString("e.g. youtube.com", comment: "")
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.keyboardType = .URL
            field.clearButtonMode = .whileEditing
            field.addTarget(self, action: #selector(self?.exceptionTextDidChange(_:)), for: .editingChanged)
        }
        let addAction = UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let text = alert?.textFields?.first?.text,
                  let host = self.validatedExceptionHost(text),
                  !self.exceptions.contains(host) else {
                return
            }
            self.exceptions.append(host)
            self.exceptions.sort()
            Prefs.DNSOverHTTPSPreferences.exceptions = self.exceptions
            DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
            self.tableView.reloadData()
        }
        addAction.isEnabled = false
        exceptionAddAction = addAction
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(addAction)
        present(alert, animated: true)
    }
    
    @objc private func exceptionTextDidChange(_ sender: UITextField) {
        guard let host = validatedExceptionHost(sender.text ?? "") else {
            exceptionAddAction?.isEnabled = false
            return
        }
        exceptionAddAction?.isEnabled = !exceptions.contains(host)
    }
    
    private func validatedExceptionHost(_ value: String) -> String? {
        guard let url = URLUtils.normalizedCustomURL(from: value),
              let host = URLUtils.normalizedHost(url.host) else {
            return nil
        }
        return host
    }
}
