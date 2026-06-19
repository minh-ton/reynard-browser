//
//  JITSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

final class JITSettingsSection: NSObject {
    private enum UX {
        static let footerSpacing: CGFloat = 4
    }
    
    enum Row: CaseIterable {
        case enableJIT
        case importPairingFile
    }
    
    weak var settingsController: SettingsViewController?
    
    var hasEntitledJIT: Bool {
        return getEntitlementValue("com.apple.private.security.no-sandbox")
    }
    
    private let jitSwitch = UISwitch()
    private let backgroundQueue = DispatchQueue(label: "com.minh-ton.Reynard.JITSettingsSection.Queue", qos: .userInitiated)
    private var isJITLessModeActive = false
    private var activeDDIDownloadToken: UUID?
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    func attach(to settingsController: SettingsViewController) {
        self.settingsController = settingsController
        connectSwitchActions()
    }
    
    func cell(at index: Int, tintColor: UIColor?) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .enableJIT:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Enable JIT"
            cell.selectionStyle = .none
            cell.accessoryView = jitSwitch
            return cell
        case .importPairingFile:
            let cell = SettingsViewUtils.actionCell(title: "Import Pairing File...", tintColor: tintColor)
            
            if #available(iOS 16.6, *) {
                if #unavailable(iOS 17.4) {
                    cell.textLabel?.textColor = .secondaryLabel
                    cell.selectionStyle = .none
                    cell.isUserInteractionEnabled = false
                }
            }
            
            return cell
        }
    }
    
    func footerView() -> UIView {
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = UX.footerSpacing
        
        if isJITLessModeActive {
            stackView.addArrangedSubview(jitlessStatusLabel())
        }
        stackView.addArrangedSubview(performanceDetailLabel())
        
        if #available(iOS 16.6, *) {
            if #unavailable(iOS 17.4) {
                stackView.addArrangedSubview(unsupportedVersionWarningLabel())
            }
        }
        
        footerView.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func refreshDisplayedState() {
        jitSwitch.isEnabled = Prefs.JITSettings.hasPairingFile
        jitSwitch.isOn = Prefs.JITSettings.isJITEnabled
        isJITLessModeActive = JITController.shared.isJITLessModeActive
    }
    
    @objc private func jitSwitchChanged(_ sender: UISwitch) {
        Prefs.JITSettings.isJITEnabled = sender.isOn
        guard sender.isOn else {
            showRestartAlert()
            return
        }
        guard !DDIManager.shared.hasRequiredDDIFiles() else {
            showRestartAlert()
            return
        }
        
        confirmDDIDownload(for: sender)
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index), Row.allCases[index] == .importPairingFile else {
            return
        }
        choosePairingFile(from: viewController)
    }
    
    private func choosePairingFile(from viewController: UIViewController) {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedPairingFileTypes(), asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: allowedPairingDocumentTypeIdentifiers(), in: .import)
        }
        
        picker.delegate = settingsController
        picker.allowsMultipleSelection = false
        viewController.present(picker, animated: true)
    }
    
    func savePairingFile(from url: URL) {
        backgroundQueue.async { [weak self] in
            guard let self else {
                return
            }
            
            do {
                try installPairingFile(from: url)
                DispatchQueue.main.async {
                    self.refreshDisplayedState()
                    self.settingsController?.tableView.reloadData()
                }
            } catch {
                DispatchQueue.main.async {
                    AlertPresenter.show(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func confirmDDIDownload(for sender: UISwitch) {
        guard let settingsController else {
            return
        }
        
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
            self?.cancelDDI(for: sender, token: token)
        })
        
        settingsController.present(alert, animated: true) { [weak self] in
            self?.downloadDDI(for: sender, alert: alert, progressView: progressView, token: token)
        }
    }
    
    private func downloadDDI(
        for sender: UISwitch,
        alert: UIAlertController,
        progressView: UIProgressView,
        token: UUID
    ) {
        SettingsViewUtils.addProgressView(progressView, to: alert)
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self,
                      self.activeDDIDownloadToken == token else {
                    return
                }
                
                progressView.setProgress(Float(value), animated: true)
            },
            completion: { [weak self] result in
                guard let self,
                      let settingsController = self.settingsController,
                      self.activeDDIDownloadToken == token else {
                    return
                }
                
                self.activeDDIDownloadToken = nil
                sender.isEnabled = Prefs.JITSettings.hasPairingFile
                
                switch result {
                case .success:
                    SettingsViewUtils.dismissPresentedAlert(alert, from: settingsController) {
                        self.showRestartAlert()
                    }
                case .failure(let error):
                    Prefs.JITSettings.isJITEnabled = false
                    sender.setOn(false, animated: true)
                    SettingsViewUtils.dismissPresentedAlert(alert, from: settingsController) {
                        AlertPresenter.show(title: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        )
    }
    
    private func cancelDDI(for sender: UISwitch, token: UUID) {
        guard activeDDIDownloadToken == token else {
            return
        }
        
        activeDDIDownloadToken = nil
        DDIManager.shared.cancelActiveDownload()
        Prefs.JITSettings.isJITEnabled = false
        sender.setOn(false, animated: true)
        sender.isEnabled = Prefs.JITSettings.hasPairingFile
    }
    
    private func showRestartAlert() {
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
        settingsController?.present(alert, animated: true)
    }
    
    private func connectSwitchActions() {
        jitSwitch.addTarget(self, action: #selector(jitSwitchChanged(_:)), for: .valueChanged)
    }
    
    private func jitlessStatusLabel() -> UILabel {
        let footerPointSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        let statusBoldFont = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.systemFont(ofSize: footerPointSize, weight: .semibold))
        let statusLabel = UILabel()
        statusLabel.numberOfLines = 0
        statusLabel.font = statusBoldFont
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .systemOrange
        statusLabel.text = "\u{25B2} JIT-Less Mode is Currently Active"
        return statusLabel
    }
    
    private func performanceDetailLabel() -> UILabel {
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.text = "Enabling JIT improves performance significantly and is required for features like WebAssembly."
        return detailLabel
    }
    
    private func unsupportedVersionWarningLabel() -> UILabel {
        let warningLabel = UILabel()
        warningLabel.numberOfLines = 0
        warningLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        warningLabel.adjustsFontForContentSizeCategory = true
        warningLabel.textColor = .systemRed
        warningLabel.text = "This pairing-based JIT enablement method is not working properly on the OS version you are using. You can use the browser without JIT; or if you're on an iOS/iPadOS version that supports TrollStore, consider using the TrollStore IPA instead."
        return warningLabel
    }
}

@available(iOS 14.0, *)
private func allowedPairingFileTypes() -> [UTType] {
    var types = [UTType.propertyList]
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { fileExtension in
        if let type = UTType(filenameExtension: fileExtension),
           !types.contains(type) {
            types.append(type)
        }
    }
    return types
}

private func allowedPairingDocumentTypeIdentifiers() -> [String] {
    var identifiers = [kUTTypePropertyList as String]
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { fileExtension in
        if let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            fileExtension as CFString,
            nil
        )?.takeRetainedValue() as String?,
           !identifiers.contains(uti) {
            identifiers.append(uti)
        }
    }
    return identifiers
}

private func installPairingFile(from downloadLocation: URL) throws {
    let fileManager = FileManager.default
    let destinationURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pairingFile.plist", isDirectory: false)
    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    
    let normalizedSourceURL = downloadLocation.standardizedFileURL
    let normalizedDestinationURL = destinationURL.standardizedFileURL
    
    guard normalizedSourceURL != normalizedDestinationURL else {
        Prefs.JITSettings.isJITEnabled = false
        return
    }
    
    if fileManager.fileExists(atPath: normalizedDestinationURL.path) {
        try fileManager.removeItem(at: normalizedDestinationURL)
    }
    
    try fileManager.copyItem(at: normalizedSourceURL, to: normalizedDestinationURL)
    Prefs.JITSettings.isJITEnabled = false
}
