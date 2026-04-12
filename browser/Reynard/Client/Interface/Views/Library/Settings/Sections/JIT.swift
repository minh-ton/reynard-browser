//
//  JIT.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit
import UniformTypeIdentifiers

extension SettingsRootViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importPairingFile(from: url)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}

extension SettingsRootViewController {
    func makeJITFooterView() -> UIView {
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
            statusLabel.text = "\u{25B2} JIT-Less Mode is Currently Active"
            stack.addArrangedSubview(statusLabel)
        }
        
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.text = "Enabling JIT improves performance significantly and is required for features like WebAssembly."
        stack.addArrangedSubview(detailLabel)
        
        // if on 16.6 to 17.3.1, show warning about JIT
        if #available(iOS 16.6, *) {
            if #unavailable(iOS 17.4) {
                let warningLabel = UILabel()
                warningLabel.numberOfLines = 0
                warningLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
                warningLabel.adjustsFontForContentSizeCategory = true
                warningLabel.textColor = .systemRed
                warningLabel.text = "This pairing-based JIT enablement method is not working properly on the OS version you are using. You can use the browser without JIT; or if you're on an iOS/iPadOS version that supports TrollStore, consider using the TrollStore IPA instead."
                stack.addArrangedSubview(warningLabel)
            }
        }
        
        footerView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func presentPairingFilePicker() {
        let types = allowedPairingFileTypes()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    func importPairingFile(from url: URL) {
        backgroundQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.preferences.installPairingFile(from: url)
                DispatchQueue.main.async { self.refreshControls() }
            } catch {
                DispatchQueue.main.async {
                    self.presentAlert(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc func jitSwitchChanged(_ sender: UISwitch) {
        preferences.isJITEnabled = sender.isOn
        guard sender.isOn else { presentJITRestartAlert(); return }
        guard !DDIManager.shared.hasRequiredDDIFiles() else { presentJITRestartAlert(); return }
        presentDDIDownloadAlert(for: sender)
    }
    
    @objc func handleJITLessModeActivated(_ notification: Notification) {
        refreshControls()
        tableView.reloadData()
    }
    
    func presentDDIDownloadAlert(for sender: UISwitch) {
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
    
    func attachProgressView(_ progressView: UIProgressView, to alert: UIAlertController) {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else { return }
        alert.view.addSubview(progressView)
        let cancelAnchorView: UIView? = {
            if let button = alert.view.firstDescendantButton(withTitle: "Cancel") { return button }
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
    
    func startDDIDownload(for sender: UISwitch, alert: UIAlertController, progressView: UIProgressView, token: UUID) {
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self, self.activeDDIDownloadToken == token else { return }
                progressView.setProgress(Float(value), animated: true)
            },
            completion: { [weak self] result in
                guard let self, self.activeDDIDownloadToken == token else { return }
                self.activeDDIDownloadToken = nil
                sender.isEnabled = self.preferences.hasPairingFile
                switch result {
                case .success:
                    self.dismissAlertIfPresented(alert) { self.presentJITRestartAlert() }
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
    
    func cancelDDIDownload(for sender: UISwitch, token: UUID) {
        guard activeDDIDownloadToken == token else { return }
        activeDDIDownloadToken = nil
        DDIManager.shared.cancelActiveDownload()
        preferences.isJITEnabled = false
        sender.setOn(false, animated: true)
        sender.isEnabled = preferences.hasPairingFile
    }
    
    func dismissAlertIfPresented(_ alert: UIAlertController, completion: @escaping () -> Void) {
        guard presentedViewController === alert else { completion(); return }
        alert.dismiss(animated: true, completion: completion)
    }
    
    func presentJITRestartAlert() {
        let alert = UIAlertController(
            title: "Restart Required",
            message: "The app will now close for the JIT setting to take effect.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                exit(EXIT_SUCCESS)
            }
        })
        present(alert, animated: true)
    }
}

func allowedPairingFileTypes() -> [UTType] {
    var types = [UTType.propertyList]
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { ext in
        if let type = UTType(filenameExtension: ext), !types.contains(type) {
            types.append(type)
        }
    }
    return types
}
