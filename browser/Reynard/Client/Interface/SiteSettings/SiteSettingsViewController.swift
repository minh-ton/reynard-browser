//
//  SiteSettingsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class SiteSettingsViewController: UITableViewController, UINavigationControllerDelegate {
    private let permissionCellReuseIdentifier = "Cell"
    private let trackingProtectionSwitch = UISwitch()
    private let requestDesktopWebsiteSwitch = UISwitch()
    private let useReaderAutomaticallySwitch = UISwitch()
    
    private enum Section {
        case availability
        case trackingProtection
        case content
        case permissions
        case websiteActions
    }
    
    private enum Row: CaseIterable {
        case autoplay
        case camera
        case microphone
        case location
        case persistentStorage
        case crossOriginStorageAccess
        case localDeviceAccess
        case localNetworkAccess

        var title: String {
            switch self {
            case .camera:
                return NSLocalizedString("Camera", comment: "")
            case .microphone:
                return NSLocalizedString("Microphone", comment: "")
            case .location:
                return NSLocalizedString("Location", comment: "")
            case .persistentStorage:
                return NSLocalizedString("Persistent Storage", comment: "")
            case .crossOriginStorageAccess:
                return NSLocalizedString("Cross-Site Cookies", comment: "")
            case .localDeviceAccess:
                return NSLocalizedString("Device Apps and Services", comment: "")
            case .localNetworkAccess:
                return NSLocalizedString("Local Network Devices", comment: "")
            case .autoplay:
                return NSLocalizedString("Autoplay", comment: "")
            }
        }
        
        var permission: SitePermission {
            switch self {
            case .camera:
                return .camera
            case .microphone:
                return .microphone
            case .location:
                return .location
            case .persistentStorage:
                return .persistentStorage
            case .crossOriginStorageAccess:
                return .crossOriginStorageAccess
            case .localDeviceAccess:
                return .localDeviceAccess
            case .localNetworkAccess:
                return .localNetworkAccess
            case .autoplay:
                return .autoplay
            }
        }
    }
    
    private enum LoadingState {
        case loading
        case loaded
    }
    
    private let permissionRows: [Row] = [
        .autoplay,
        .camera,
        .microphone,
        .location,
    ]
    private let host: String
    private let origin: String
    private let session: GeckoSession
    private let trackingProtection: TrackingProtectionManager
    private var loadState: LoadingState = .loading
    private var loadedGeckoPermissions: [ContentPermission] = []
    private var hasTrackingProtectionException = false
    
    private var visibleSections: [Section] {
        var sections: [Section] = []
        
        if !SiteSettingsUtils.disabledPermissionNames().isEmpty {
            sections.append(.availability)
        }
        
        sections.append(.trackingProtection)
        sections.append(.content)
        sections.append(.permissions)
        sections.append(.websiteActions)
        return sections
    }
    
    init?(
        url: URL,
        session: GeckoSession,
        trackingProtection: TrackingProtectionManager
    ) {
        guard let host = URLUtils.normalizedHost(url.host),
              let origin = URLUtils.httpOriginString(for: url) else {
            return nil
        }
        
        self.host = host
        self.origin = origin
        self.session = session
        self.trackingProtection = trackingProtection
        super.init(style: .insetGrouped)
        title = String(format: NSLocalizedString("Settings for %@", comment: "Website host"), host)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        trackingProtectionSwitch.addTarget(self, action: #selector(trackingProtectionSwitchDidChange), for: .valueChanged)
        requestDesktopWebsiteSwitch.addTarget(self, action: #selector(requestDesktopWebsiteSwitchDidChange), for: .valueChanged)
        useReaderAutomaticallySwitch.addTarget(self, action: #selector(useReaderAutomaticallySwitchDidChange), for: .valueChanged)
        Task { [weak self] in
            await self?.loadPermissionsFromGecko()
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.trackingProtection.refreshBlockedTrackers(for: self.session)
            self.tableView.reloadData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.delegate = self
        trackingProtection.addObserver(self)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        trackingProtection.removeObserver(self)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else {
            return 0
        }
        
        switch visibleSections[section] {
        case .availability:
            return 2
        case .trackingProtection:
            return Prefs.TrackingProtectionPreferences.level == .off
            || hasTrackingProtectionException ? 1 : 2
        case .content:
            return 3
        case .permissions:
            return loadState == .loaded ? permissionRows.count : 0
        case .websiteActions:
            return loadState == .loaded ? 2 : 0
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else {
            return nil
        }
        
        switch visibleSections[section] {
        case .availability:
            return nil
        case .trackingProtection:
            return NSLocalizedString("Tracking Protection", comment: "")
        case .content:
            return NSLocalizedString("Content", comment: "Website settings section title")
        case .permissions:
            return NSLocalizedString("Permissions", comment: "")
        case .websiteActions:
            return nil
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch visibleSections[indexPath.section] {
        case .availability:
            return availabilityCell(at: indexPath)
        case .trackingProtection:
            return trackingProtectionCell(at: indexPath)
        case .content:
            return contentCell(at: indexPath)
        case .permissions:
            return permissionCell(at: indexPath)
        case .websiteActions:
            return websiteActionCell(at: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard visibleSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch visibleSections[indexPath.section] {
        case .availability:
            handleAvailabilitySelection(at: indexPath)
        case .trackingProtection:
            showBlockedTrackers(at: indexPath)
        case .content:
            handleContentSelection(at: indexPath)
        case .permissions:
            handlePermissionSelection(at: indexPath)
        case .websiteActions:
            handleWebsiteActionSelection(at: indexPath)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        viewController.navigationItem.rightBarButtonItem = SiteSettingsUtils.makeDismissButton(
            target: self,
            action: #selector(dismissModal)
        )
    }
    
    // MARK: - Table Data
    
    private func availabilityCell(at indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = SiteSettingsUtils.disabledPermissionMessage()
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.numberOfLines = 0
            cell.selectionStyle = .none
            return cell
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString("Open Settings", comment: "")
        cell.textLabel?.textColor = view.tintColor
        cell.accessoryType = .none
        return cell
    }
    
    private func permissionCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: permissionCellReuseIdentifier)
        ?? UITableViewCell(style: .value1, reuseIdentifier: permissionCellReuseIdentifier)
        
        guard let row = row(at: indexPath) else {
            return cell
        }
        
        let titles = SiteSettingsUtils.actionTitles(for: row.permission)
        let selectedIndex = selectedOptionIndex(for: row)
        cell.textLabel?.text = row.title
        if SiteSettingsUtils.isSystemDisabled(row.permission) {
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = titles[selectedIndex]
            cell.detailTextLabel?.textColor = .tertiaryLabel
            cell.selectionStyle = .none
            cell.isUserInteractionEnabled = false
            cell.accessoryView = nil
            cell.accessoryType = .none
            return cell
        }
        
        cell.textLabel?.textColor = .label
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = true
        
        configureMenuCell(cell, titles: titles, selectedIndex: selectedIndex) { [weak self] index in
            self?.applyOption(at: index, for: row)
        }
        return cell
    }
    
    private func websiteActionCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.row == 0 {
            cell.textLabel?.text = NSLocalizedString("Clear Cookies and Website Data", comment: "")
            cell.textLabel?.textColor = .systemRed
        } else {
            cell.textLabel?.text = NSLocalizedString("Reset Settings for This Website", comment: "")
            cell.textLabel?.textColor = .systemRed
        }
        cell.textLabel?.textAlignment = .center
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }
    
    private func trackingProtectionCell(at indexPath: IndexPath) -> UITableViewCell {
        let protectionEnabled = Prefs.TrackingProtectionPreferences.level != .off
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Enhanced Tracking Protection", comment: "")
            cell.detailTextLabel?.text = protectionEnabled && !hasTrackingProtectionException
            ? NSLocalizedString("If something looks broken on this website, try turning it off.", comment: "")
            : NSLocalizedString("Turning on tracking protection is recommended.", comment: "")
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.numberOfLines = 0
            trackingProtectionSwitch.isOn = protectionEnabled && !hasTrackingProtectionException
            trackingProtectionSwitch.isEnabled = protectionEnabled
            cell.accessoryView = trackingProtectionSwitch
            cell.selectionStyle = .none
            return cell
        }
        
        let count = trackingProtection.blockedTrackers(for: session).count
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = count == 0
        ? NSLocalizedString("No Trackers Found", comment: "")
        : String(format: NSLocalizedString("%d Trackers Blocked", comment: "Blocked tracker count"), count)
        cell.accessoryType = count == 0 ? .none : .disclosureIndicator
        cell.selectionStyle = count == 0 ? .none : .default
        return cell
    }
    
    private func contentCell(at indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Request Desktop Website", comment: "")
            requestDesktopWebsiteSwitch.isOn = SiteSettingsStore.shared.settings(for: host)?.websiteMode.map {
                $0 == .desktop
            } ?? Prefs.BrowsingSettings.requestDesktopWebsite
            cell.accessoryView = requestDesktopWebsiteSwitch
            cell.selectionStyle = .none
            return cell
        }
        
        if indexPath.row == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Use Reader Automatically", comment: "")
            useReaderAutomaticallySwitch.isOn = SiteSettingsStore.shared.settings(for: host)?.readerMode
            ?? Prefs.BrowsingSettings.useReaderAutomatically
            cell.accessoryView = useReaderAutomaticallySwitch
            cell.selectionStyle = .none
            return cell
        }
        
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString("Page Zoom", comment: "")
        let titles = PageZoomLevels.all.map { PageZoomLevels.displayText(for: $0) }
        let selectedIndex = PageZoomLevels.all.firstIndex(of: selectedPageZoomLevel) ?? 0
        configureMenuCell(cell, titles: titles, selectedIndex: selectedIndex) { [weak self] index in
            self?.applyPageZoomLevel(PageZoomLevels.all[index])
        }
        return cell
    }
    
    private func row(at indexPath: IndexPath) -> Row? {
        guard visibleSections.indices.contains(indexPath.section) else {
            return nil
        }
        
        switch visibleSections[indexPath.section] {
        case .permissions:
            return permissionRows[safe: indexPath.row]
        case .availability, .trackingProtection, .content, .websiteActions:
            return nil
        }
    }
    
    // MARK: - Actions
    
    private func handleAvailabilitySelection(at indexPath: IndexPath) {
        guard indexPath.row == 1 else {
            return
        }
        
        SiteSettingsUtils.openAppSettings()
    }
    
    private func handlePermissionSelection(at indexPath: IndexPath) {
        guard let row = row(at: indexPath),
              !SiteSettingsUtils.isSystemDisabled(row.permission) else {
            return
        }
        
        if #available(iOS 14.0, *) {
            if #available(iOS 17.4, *),
               let cell = tableView.cellForRow(at: indexPath),
               let button = cell.accessoryView as? UIButton {
                button.performPrimaryAction()
            }
            return
        }
        
        let picker = SitePermissionOptionsViewController(
            title: row.title,
            options: SiteSettingsUtils.actionTitles(for: row.permission),
            selectedIndex: selectedOptionIndex(for: row)
        ) { [weak self] optionIndex in
            self?.applyOption(at: optionIndex, for: row)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
    
    private func handleContentSelection(at indexPath: IndexPath) {
        guard indexPath.row == 2 else {
            return
        }
        
        if #available(iOS 14.0, *) {
            if #available(iOS 17.4, *),
               let cell = tableView.cellForRow(at: indexPath),
               let button = cell.accessoryView as? UIButton {
                button.performPrimaryAction()
            }
            return
        }
        
        let picker = SitePermissionOptionsViewController(
            title: NSLocalizedString("Page Zoom", comment: ""),
            options: PageZoomLevels.all.map { PageZoomLevels.displayText(for: $0) },
            selectedIndex: PageZoomLevels.all.firstIndex(of: selectedPageZoomLevel) ?? 0
        ) { [weak self] optionIndex in
            guard PageZoomLevels.all.indices.contains(optionIndex) else {
                return
            }
            self?.applyPageZoomLevel(PageZoomLevels.all[optionIndex])
        }
        navigationController?.pushViewController(picker, animated: true)
    }
    
    private func handleWebsiteActionSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            confirmClearWebsiteData()
        } else {
            confirmResetWebsiteSettings()
        }
    }
    
    private func showBlockedTrackers(at indexPath: IndexPath) {
        let blockedTrackers = trackingProtection.blockedTrackers(for: session)
        guard indexPath.row == 1, !blockedTrackers.isEmpty else {
            return
        }
        navigationController?.pushViewController(
            BlockedTrackersViewController(trackers: blockedTrackers),
            animated: true
        )
    }
    
    @objc private func trackingProtectionSwitchDidChange(_ sender: UISwitch) {
        let permissionKey = session.isPrivateMode ? "trackingprotection-pb" : "trackingprotection"
        PermissionDelegate.setPermission(
            uri: origin,
            permissionKey: permissionKey,
            rawValue: sender.isOn ? ContentPermission.Value.deny.rawValue : ContentPermission.Value.allow.rawValue,
            privateMode: session.isPrivateMode
        )
        hasTrackingProtectionException = !sender.isOn
        tableView.reloadData()
        
        guard sender.isOn else {
            trackingProtection.clearBlockedTrackers(for: session)
            tableView.reloadData()
            session.reload()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.trackingProtection.refreshBlockedTrackers(for: self.session)
            self.tableView.reloadData()
            self.session.reload()
        }
    }
    
    @objc private func requestDesktopWebsiteSwitchDidChange(_ sender: UISwitch) {
        if sender.isOn == Prefs.BrowsingSettings.requestDesktopWebsite {
            _ = SiteSettingsStore.shared.clearWebsiteMode(for: host)
        } else {
            _ = SiteSettingsStore.shared.setWebsiteMode(sender.isOn ? .desktop : .mobile, for: host)
        }
        session.reload()
    }
    
    @objc private func useReaderAutomaticallySwitchDidChange(_ sender: UISwitch) {
        _ = SiteSettingsStore.shared.setReaderMode(sender.isOn, for: host)
        session.reload()
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    // MARK: - Page Zoom
    
    private var selectedPageZoomLevel: Int {
        return SiteSettingsStore.shared.settings(for: host)?.pageZoom
        ?? Prefs.BrowsingSettings.defaultPageZoomLevel
    }
    
    private func applyPageZoomLevel(_ level: Int) {
        _ = SiteSettingsStore.shared.setPageZoom(level, for: host)
        updateSessionPageZoom(level)
        tableView.reloadData()
    }
    
    private func updateSessionPageZoom(_ level: Int) {
        session.updateSettings(
            GeckoSessionSettings(
                websiteMode: session.settings.websiteMode,
                pageZoom: PageZoomSetting(level: level),
                language: session.settings.language
            )
        )
    }
    
    // MARK: - Permissions
    
    @MainActor
    private func loadPermissionsFromGecko() async {
        let permissions = (try? await PermissionDelegate.permissions(
            for: origin,
            privateMode: session.isPrivateMode
        )) ?? []
        loadedGeckoPermissions = permissions
        hasTrackingProtectionException = permissions.contains {
            $0.permission == .tracking && $0.value == .allow
        }
        syncStore(with: permissions)
        loadState = .loaded
        tableView.reloadData()
    }
    
    private func syncStore(with permissions: [ContentPermission]) {
        var seenPermissions = Set<SitePermission>()
        
        for permission in permissions {
            guard let sitePermission = SitePermission(contentPermission: permission),
                  let action = sitePermission == .autoplay ? SitePermissionAction(autoplayValue: permission.rawValue) : SitePermissionAction(value: permission.value) else {
                continue
            }
            
            if SiteSettingsUtils.isSystemDisabled(sitePermission) {
                continue
            }
            
            seenPermissions.insert(sitePermission)
            if SitePermissionStore.shared.resolvedAction(for: sitePermission, host: host, session: session) != action {
                SitePermissionStore.shared.updateAction(action, for: sitePermission, host: host, session: session)
            }
        }
        
        for row in Row.allCases {
            let permission = row.permission
            if !SiteSettingsUtils.isSystemDisabled(permission),
               !seenPermissions.contains(permission),
               SitePermissionStore.shared.resolvedAction(for: permission, host: host, session: session) != .askToAllow {
                SitePermissionStore.shared.removeAction(for: permission, host: host, session: session)
            }
        }
    }
    
    private func applyOption(at optionIndex: Int, for row: Row) {
        let action: SitePermissionAction
        switch optionIndex {
        case 0:
            action = .allowed
        case 1:
            action = .askToAllow
        default:
            action = .blocked
        }
        
        setAction(action, for: row.permission)
        tableView.reloadData()
    }
    
    private func setAction(_ action: SitePermissionAction, for permission: SitePermission) {
        SitePermissionStore.shared.updateAction(action, for: permission, host: host, session: session)
        let key = SiteSettingsUtils.geckoKey(for: permission)
        if action == .askToAllow, permission != .autoplay {
            PermissionDelegate.removePermission(
                uri: origin,
                permissionKey: key,
                privateMode: session.isPrivateMode
            )
            return
        }
        
        if permission == .autoplay {
            PermissionDelegate.setPermission(
                uri: origin,
                permissionKey: key,
                rawValue: action.autoplayValue,
                privateMode: session.isPrivateMode
            )
            session.reload()
            return
        }
        
        PermissionDelegate.setPermission(
            uri: origin,
            permissionKey: key,
            rawValue: action.contentPermissionValue.rawValue,
            privateMode: session.isPrivateMode
        )
    }
    
    private func selectedOptionIndex(for row: Row) -> Int {
        let permission = row.permission
        switch SitePermissionStore.shared.resolvedAction(for: permission, host: host, session: session) {
        case .allowed:
            return 0
        case .askToAllow:
            return 1
        case .blocked:
            return 2
        }
    }
    
    // MARK: - Actions
    
    private func confirmResetWebsiteSettings() {
        AlertPresenter.show(
            title: nil,
            message: NSLocalizedString("This will reset settings for this website. This action cannot be undone.", comment: ""),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Reset", comment: "Destructive button"), style: .destructive) { [weak self] in
                    self?.performResetWebsiteSettings()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
    
    private func confirmClearWebsiteData() {
        AlertPresenter.show(
            title: NSLocalizedString("Clear Cookies and Website Data", comment: ""),
            message: String(
                format: NSLocalizedString("Removing cookies and website data for %@ may require you to sign in again.", comment: "Website host"),
                host
            ),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Clear", comment: "Destructive button"), style: .destructive) { [weak self] in
                    self?.clearWebsiteData()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
    
    private func clearWebsiteData() {
        Task { [weak self] in
            guard let self else {
                return
            }
            
            do {
                try await GeckoStorageController.clearData(
                    forHost: host,
                    flags: GeckoStorageClearFlags.cookies
                    | GeckoStorageClearFlags.authSessions
                    | GeckoStorageClearFlags.domStorages
                )
                await MainActor.run {
                    self.session.reload()
                }
            } catch {
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn’t Clear Cookies and Website Data", comment: ""),
                    message: "\(error)"
                )
            }
        }
    }
    
    private func performResetWebsiteSettings() {
        for permission in loadedGeckoPermissions {
            PermissionDelegate.removePermission(permission)
        }
        for permission in SitePermission.allCases {
            PermissionDelegate.removePermission(
                uri: origin,
                permissionKey: SiteSettingsUtils.geckoKey(for: permission),
                privateMode: session.isPrivateMode
            )
        }
        PermissionDelegate.removePermission(
            uri: origin,
            permissionKey: session.isPrivateMode ? "trackingprotection-pb" : "trackingprotection",
            privateMode: session.isPrivateMode
        )
        
        for permission in SitePermission.allCases {
            SitePermissionStore.shared.removeAction(for: permission, host: host, session: session)
        }
        loadedGeckoPermissions = []
        hasTrackingProtectionException = false
        trackingProtection.clearBlockedTrackers(for: session)
        _ = SiteSettingsStore.shared.clearPageZoom(for: host)
        _ = SiteSettingsStore.shared.clearWebsiteMode(for: host)
        _ = SiteSettingsStore.shared.clearReaderMode(for: host)
        requestDesktopWebsiteSwitch.isOn = Prefs.BrowsingSettings.requestDesktopWebsite
        useReaderAutomaticallySwitch.isOn = Prefs.BrowsingSettings.useReaderAutomatically
        updateSessionPageZoom(Prefs.BrowsingSettings.defaultPageZoomLevel)
        tableView.reloadData()
        session.reload()
    }
    
    // MARK: - Helpers
    
    private func configureView() {
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            SiteSettingsUtils.makeDismissButton(target: self, action: #selector(dismissModal))
        ]
    }
    
    // MARK: - Menu Cells
    
    private func configureMenuCell(
        _ cell: UITableViewCell,
        titles: [String],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) {
        if #available(iOS 14.0, *) {
            cell.detailTextLabel?.text = nil
            cell.accessoryView = menuButton(titles: titles, selectedIndex: selectedIndex, onSelect: onSelect)
            cell.accessoryType = .none
        } else {
            cell.detailTextLabel?.text = titles[selectedIndex]
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
    }
    
    @available(iOS 14.0, *)
    private func menuButton(
        titles: [String],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(titles[selectedIndex], for: .normal)
        button.setImage(UIImage(named: "reynard.chevron.up.chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        if #available(iOS 15.0, *) {
            button.changesSelectionAsPrimaryAction = true
        }
        button.menu = menu(titles: titles, selectedIndex: selectedIndex, onSelect: onSelect)
        button.sizeToFit()
        return button
    }
    
    @available(iOS 14.0, *)
    private func menu(
        titles: [String],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) -> UIMenu {
        let actions = titles.enumerated().map { index, title in
            UIAction(title: title, state: index == selectedIndex ? .on : .off) { _ in
                onSelect(index)
            }
        }
        
        if #available(iOS 15.0, *) {
            return UIMenu(title: "", options: .singleSelection, children: actions)
        }
        return UIMenu(title: "", children: actions)
    }
}

extension SiteSettingsViewController: TrackingProtectionManagerObserver {
    func trackingProtectionManager(
        _ manager: TrackingProtectionManager,
        didUpdate session: GeckoSession
    ) {
        guard session === self.session else {
            return
        }
        tableView.reloadData()
    }
}
