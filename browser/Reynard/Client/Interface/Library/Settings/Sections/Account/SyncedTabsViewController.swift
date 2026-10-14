//
//  SyncedTabsViewController.swift
//  Reynard
//
//  Open tabs from your other Firefox devices.
//

import UIKit

final class SyncedTabsViewController: UITableViewController {
    private var clients: [RemoteClientTabs] = []

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Tabs From Other Devices", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshRequested), for: .valueChanged)
        self.refreshControl = refreshControl

        for name in [Notification.Name.syncedTabsDidChange, .syncStatusDidChange] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reloadClients),
                name: name,
                object: nil
            )
        }
        reloadClients()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        SyncManager.shared.requestSync(reason: .foreground)
    }

    @objc private func refreshRequested() {
        SyncManager.shared.requestSync(reason: .user)
        if !SyncManager.shared.isSyncing {
            refreshControl?.endRefreshing()
        }
    }

    @objc private func reloadClients() {
        clients = SyncManager.shared.remoteClients
        if !SyncManager.shared.isSyncing {
            refreshControl?.endRefreshing()
        }
        updateBackground()
        tableView.reloadData()
    }

    private func updateBackground() {
        guard clients.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.text = SyncManager.shared.isSyncing
            ? NSLocalizedString("Syncing…", comment: "")
            : NSLocalizedString("No tabs from other devices yet.\nOpen Firefox on another device signed in to the same account, then pull down to refresh.", comment: "")

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor, constant: -16),
        ])
        tableView.backgroundView = container
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        clients.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        clients[section].tabs.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        clients[section].name
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(
            format: NSLocalizedString("Updated %@", comment: ""),
            Self.dateFormatter.string(from: clients[section].lastModified)
        )
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let tab = clients[indexPath.section].tabs[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "SyncedTab")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SyncedTab")
        cell.textLabel?.text = tab.title
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.text = URL(string: tab.url)?.host ?? tab.url
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "globe")
        cell.imageView?.tintColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tab = clients[indexPath.section].tabs[indexPath.row]
        guard let url = URL(string: tab.url),
              let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: self) else {
            return
        }

        browserViewController.loadViewIfNeeded()
        browserViewController.exitFullscreenIfNeeded()
        browserViewController.openURLFromHomepage(url, disposition: .newTab)

        if let navigationController = navigationController, navigationController.presentingViewController != nil {
            navigationController.dismiss(animated: true)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = clients[indexPath.section].tabs[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(
                    title: NSLocalizedString("Copy Link", comment: ""),
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in
                    UIPasteboard.general.string = tab.url
                },
            ])
        }
    }
}
