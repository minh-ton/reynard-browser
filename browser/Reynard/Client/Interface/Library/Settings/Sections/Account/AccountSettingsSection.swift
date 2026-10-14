//
//  AccountSettingsSection.swift
//  Reynard
//
//  Mozilla account / Firefox Sync entry point in Settings.
//

import UIKit

struct AccountSettingsSection {
    enum Row {
        case signIn
        case account
        case syncedTabs
    }

    private var rows: [Row] {
        FxAAccountManager.shared.isSignedIn ? [.account, .syncedTabs] : [.signIn]
    }

    var rowCount: Int {
        rows.count
    }

    var footerTitle: String? {
        guard !FxAAccountManager.shared.isSignedIn else {
            return nil
        }
        return NSLocalizedString("Sign in with your Mozilla account to see tabs from your other devices and sync your history and bookmarks.", comment: "")
    }

    func cell(at index: Int, tintColor: UIColor?) -> UITableViewCell {
        guard rows.indices.contains(index) else {
            return UITableViewCell()
        }

        let accounts = FxAAccountManager.shared
        switch rows[index] {
        case .signIn:
            let title = accounts.isSigningIn
                ? NSLocalizedString("Continue Signing In…", comment: "")
                : NSLocalizedString("Sign In to Sync", comment: "")
            return SettingsViewUtils.actionCell(title: title, tintColor: tintColor)
        case .account:
            let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = accounts.account?.email ?? NSLocalizedString("Mozilla Account", comment: "")
            cell.detailTextLabel?.text = FirefoxAccountViewController.statusText()
            cell.detailTextLabel?.textColor = accounts.needsReauthentication ? .systemRed : .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        case .syncedTabs:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Tabs From Other Devices", comment: ""))
        }
    }

    func selectRow(at index: Int, from viewController: UIViewController) {
        guard rows.indices.contains(index) else {
            return
        }

        switch rows[index] {
        case .signIn:
            FxASignInLauncher.start(from: viewController)
        case .account:
            viewController.navigationController?.pushViewController(FirefoxAccountViewController(), animated: true)
        case .syncedTabs:
            viewController.navigationController?.pushViewController(SyncedTabsViewController(), animated: true)
        }
    }
}

/// Opens accounts.firefox.com in a new tab and closes Settings.
enum FxASignInLauncher {
    static func start(from viewController: UIViewController) {
        Task { @MainActor in
            do {
                let url = try await FxAAccountManager.shared.beginSignIn()
                guard let browserViewController = LibrarySharedUtils.resolvedBrowserViewController(from: viewController) else {
                    return
                }
                browserViewController.loadViewIfNeeded()
                browserViewController.exitFullscreenIfNeeded()
                browserViewController.openURLFromHomepage(url, disposition: .newTab)

                if let navigationController = viewController.navigationController,
                   navigationController.presentingViewController != nil {
                    navigationController.dismiss(animated: true)
                }
            } catch {
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn't Start Sign In", comment: ""),
                    message: error.localizedDescription
                )
            }
        }
    }
}
