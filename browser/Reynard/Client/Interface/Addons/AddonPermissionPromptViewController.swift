//
//  AddonPermissionPromptViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/5/26.
//

import GeckoView
import UIKit

final class AddonPermissionPromptViewController: UITableViewController {
    private enum UX {
        static let footerHeight: CGFloat = 88
        static let actionButtonTopInset: CGFloat = 24
        static let actionButtonHeight: CGFloat = 50
        static let actionButtonCornerRadius: CGFloat = 25
    }
    
    private enum Section {
        case message
        case permissions
        case dataCollection
        case options
    }
    
    private enum PermissionRow {
        case domainHeader(String)
        case showAllSites
        case permission(String)
    }
    
    private let cellReuseIdentifier = "Cell"
    private let prompt: AddonPermissionPrompt
    private let onDecision: (AddonPermissionPromptResponse) -> Void
    private let siteDomains: [String]
    private let permissionRows: [PermissionRow]
    private let dataCollectionDescription: String?
    private var buttonLeadingConstraint: NSLayoutConstraint?
    private var buttonTrailingConstraint: NSLayoutConstraint?
    private var hasResolvedDecision = false
    private let privateBrowsingSwitch = UISwitch()
    private var visibleSections: [Section] {
        var sections: [Section] = [.message]
        if !permissionRows.isEmpty {
            sections.append(.permissions)
        }
        if dataCollectionDescription != nil {
            sections.append(.dataCollection)
        }
        if prompt.kind == .install {
            sections.append(.options)
        }
        return sections
    }
    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = view.tintColor
        button.tintColor = .white
        button.layer.cornerRadius = UX.actionButtonCornerRadius
        button.layer.cornerCurve = .continuous
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.setTitle(prompt.kind == .install ? "Add" : "Allow", for: .normal)
        button.addTarget(self, action: #selector(confirmPrompt), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    
    init(prompt: AddonPermissionPrompt, onDecision: @escaping (AddonPermissionPromptResponse) -> Void) {
        self.prompt = prompt
        self.onDecision = onDecision
        let content = Self.promptContent(for: prompt)
        siteDomains = content.siteDomains
        permissionRows = Self.makePermissionRows(
            localizedPermissions: content.permissionRows,
            domains: content.siteDomains
        )
        dataCollectionDescription = content.dataCollectionDescription
        super.init(style: .insetGrouped)
        configureTitle()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureNavigationItem()
        configureFooter()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        guard rowRect.width > 0 else {
            return
        }
        
        buttonLeadingConstraint?.constant = rowRect.minX
        buttonTrailingConstraint?.constant = -(tableView.bounds.width - rowRect.maxX)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if !hasResolvedDecision,
           isBeingDismissed || navigationController?.isBeingDismissed == true {
            hasResolvedDecision = true
            onDecision(.deny)
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else {
            return 0
        }
        
        switch visibleSections[section] {
        case .message:
            return 1
        case .permissions:
            return permissionRows.count
        case .dataCollection:
            return 1
        case .options:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else {
            return nil
        }
        
        switch visibleSections[section] {
        case .permissions:
            guard !permissionRows.isEmpty else {
                return nil
            }
            return "Required Permissions"
        case .dataCollection:
            return "Required Data Collection"
        case .options:
            return "Additional Options"
        case .message:
            return nil
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier)
        ?? UITableViewCell(style: .default, reuseIdentifier: cellReuseIdentifier)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = .label
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil
        
        guard visibleSections.indices.contains(indexPath.section) else {
            cell.textLabel?.text = nil
            return cell
        }
        
        switch visibleSections[indexPath.section] {
        case .message:
            cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
            cell.textLabel?.text = promptMessage()
        case .permissions:
            switch permissionRows[indexPath.row] {
            case .domainHeader(let value):
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.textLabel?.text = value
            case .showAllSites:
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.textLabel?.text = "Show All Sites"
                cell.textLabel?.textColor = view.tintColor
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            case .permission(let value):
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.textLabel?.text = value
            }
        case .dataCollection:
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.text = dataCollectionDescription
        case .options:
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.text = "Allow in Private Browsing"
            cell.accessoryView = privateBrowsingSwitch
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard visibleSections.indices.contains(indexPath.section),
              visibleSections[indexPath.section] == .permissions else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        if case .showAllSites = permissionRows[indexPath.row] {
            navigationController?.pushViewController(
                AddonPromptSiteListViewController(sites: siteDomains),
                animated: true
            )
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Setup
    
    private func configureTitle() {
        title = Self.promptTitle(for: prompt)
    }
    
    private func configureView() {
        view.backgroundColor = .systemGroupedBackground
    }
    
    private func configureNavigationItem() {
        navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 26.0, *) {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissModal))
            ]
            navigationItem.rightBarButtonItems?.first?.tintColor = .label
        } else {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissModal))
            ]
        }
    }
    
    private func configureFooter() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: UX.footerHeight))
        container.addSubview(actionButton)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        buttonLeadingConstraint = actionButton.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        buttonTrailingConstraint = actionButton.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        
        NSLayoutConstraint.activate([
            actionButton.topAnchor.constraint(equalTo: container.topAnchor, constant: UX.actionButtonTopInset),
            buttonLeadingConstraint!,
            buttonTrailingConstraint!,
            actionButton.heightAnchor.constraint(equalToConstant: UX.actionButtonHeight),
        ])
        
        tableView.tableFooterView = container
    }
    
    // MARK: - Actions
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    @objc private func confirmPrompt() {
        guard !hasResolvedDecision else {
            return
        }
        
        hasResolvedDecision = true
        onDecision(
            AddonPermissionPromptResponse(
                allow: true,
                privateBrowsingAllowed: prompt.kind == .install ? privateBrowsingSwitch.isOn : false
            )
        )
        dismiss(animated: true)
    }
    
    // MARK: - Content
    
    private func promptMessage() -> String {
        let addonName = prompt.addon.metaData.name ?? prompt.addon.id
        
        switch prompt.kind {
        case .install:
            return "Add \(addonName)?"
        case .optional:
            if prompt.permissions.isEmpty && prompt.origins.isEmpty && !prompt.dataCollectionPermissions.isEmpty {
                return "\(addonName) requests additional data collection."
            }
            return "\(addonName) requests additional permissions."
        case .update:
            return "\(addonName) has been updated. You must approve additional permissions before the updated version will install. Dismissing this prompt will maintain your current add-on version."
        }
    }
    
    private static func makePermissionRows(localizedPermissions: [String], domains: [String]) -> [PermissionRow] {
        var rows: [PermissionRow] = []
        
        if !domains.isEmpty {
            rows.append(.domainHeader("Access your data for sites in \(domains.count) domains"))
            rows.append(.showAllSites)
        }
        
        localizedPermissions.forEach { rows.append(.permission($0)) }
        
        return rows
    }
    
    // MARK: - Formatting
    
    private static func promptContent(
        for prompt: AddonPermissionPrompt
    ) -> (permissionRows: [String], siteDomains: [String], dataCollectionDescription: String?) {
        switch prompt.kind {
        case .install, .optional:
            let hostPermissions = AddonPermissionSupport.classifyOriginPermissions(prompt.origins)
            let allUrlsPermissionFound = prompt.permissions.contains("<all_urls>") || hostPermissions.allUrls != nil
            var displayPermissions = prompt.permissions.filter { $0 != "<all_urls>" }
            if allUrlsPermissionFound {
                displayPermissions.insert("<all_urls>", at: 0)
            }
            
            let filteredDataCollectionPermissions = prompt.kind == .optional
            ? prompt.dataCollectionPermissions
            : prompt.dataCollectionPermissions.filter { $0 != "technicalAndInteraction" }
            
            return (
                permissionRows: AddonPermissionSupport.localizePermissions(displayPermissions, forUpdate: false),
                siteDomains: allUrlsPermissionFound ? [] : (hostPermissions.wildcards + hostPermissions.sites),
                dataCollectionDescription: prompt.kind == .optional
                ? AddonPermissionSupport.optionalDataCollectionDescription(for: filteredDataCollectionPermissions)
                : AddonPermissionSupport.requiredDataCollectionDescription(for: filteredDataCollectionPermissions)
            )
        case .update:
            return (
                permissionRows: AddonPermissionSupport.updatePermissionDescription(for: prompt.permissions + prompt.origins).map { [$0] } ?? [],
                siteDomains: [],
                dataCollectionDescription: AddonPermissionSupport.updateDataCollectionDescription(for: prompt.dataCollectionPermissions)
            )
        }
    }
    
    private static func promptTitle(for prompt: AddonPermissionPrompt) -> String {
        switch prompt.kind {
        case .install:
            return "Add Add-on"
        case .optional, .update:
            return "Update Add-on Permissions"
        }
    }
    
}

private final class AddonPromptSiteListViewController: UITableViewController {
    private let cellReuseIdentifier = "SiteCell"
    private let sites: [String]
    
    init(sites: [String]) {
        self.sites = sites
        super.init(style: .insetGrouped)
        title = "Sites"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sites.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier)
        ?? UITableViewCell(style: .default, reuseIdentifier: cellReuseIdentifier)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = sites[indexPath.row]
        return cell
    }
}
