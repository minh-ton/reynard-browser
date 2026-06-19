//
//  UpdatesSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class UpdatesSettingsSection {
    private enum UX {
        static let releaseNotesHeightRatio: CGFloat = 0.55
        static let maximumReleaseNotesHeight: CGFloat = 320
    }
    
    enum Row: CaseIterable {
        case releaseNotes
        case updateNow
    }
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    var installedThroughTrollStore: Bool {
        let trollStoreMarkerPath = Bundle.main.bundlePath + "/../_TrollStore"
        return access(trollStoreMarkerPath, F_OK) == 0
    }
    
    private var activeUpdateTask: URLSessionDownloadTask?
    private var updateProgressObservation: NSKeyValueObservation?
    
    func rowHeight(at index: Int, in tableView: UITableView) -> CGFloat {
        guard Row.allCases.indices.contains(index) else {
            return UITableView.automaticDimension
        }
        
        switch Row.allCases[index] {
        case .releaseNotes:
            return min(
                tableView.bounds.height * UX.releaseNotesHeightRatio,
                UX.maximumReleaseNotesHeight
            )
        case .updateNow:
            return UITableView.automaticDimension
        }
    }
    
    func cell(at index: Int, tintColor: UIColor?) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .releaseNotes:
            return UpdateReleaseNotesCell()
        case .updateNow:
            let cell = SettingsViewUtils.actionCell(title: "Update Now", tintColor: tintColor)
            cell.textLabel?.textAlignment = .center
            return cell
        }
    }
    
    func trollStoreFooterView() -> UIView {
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true
        
        let footerLabel = UILabel()
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.numberOfLines = 0
        footerLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        footerLabel.adjustsFontForContentSizeCategory = true
        footerLabel.textColor = .secondaryLabel
        footerLabel.text = "Make sure TrollStore's URL Scheme is enabled."
        
        footerView.contentView.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerLabel.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            footerLabel.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index), Row.allCases[index] == .updateNow else {
            return
        }
        beginUpdate(from: viewController)
    }
    
    private func beginUpdate(from viewController: UIViewController) {
        guard let updateFeedData = BrowserUpdates.shared.sourceData,
              let updateFeed = try? JSONSerialization.jsonObject(with: updateFeedData) as? [String: Any],
              let appEntries = updateFeed["apps"] as? [[String: Any]],
              let appEntry = appEntries.first,
              let versions = appEntry["versions"] as? [[String: Any]],
              let latestEntry = versions.first,
              let packageURLString = latestEntry["downloadURL"] as? String,
              let packageURL = URL(string: packageURLString) else {
            AlertPresenter.show(title: "Update Unavailable", message: "Could not retrieve the download URL.")
            return
        }
        
        let expectedSize = latestEntry["size"] as? Int
        if installedThroughTrollStore {
            let trollStorePackageURLString = packageURLString.replacingOccurrences(
                of: "Reynard.ipa",
                with: "Reynard-TrollStore.tipa"
            )
            let encodedPackageURLString = trollStorePackageURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ??
            trollStorePackageURLString
            
            if let schemeURL = URL(string: "apple-magnifier://install?url=" + encodedPackageURLString),
               UIApplication.shared.canOpenURL(schemeURL) {
                UIApplication.shared.open(schemeURL)
                return
            }
        } else {
            downloadUpdate(
                from: packageURL,
                fileName: "Reynard.ipa",
                expectedSize: expectedSize,
                message: "When the download finishes, choose the app that you used to sideload Reynard in the share sheet to install the update.",
                viewController: viewController
            )
        }
    }
    
    private func downloadUpdate(
        from url: URL,
        fileName: String,
        expectedSize: Int?,
        message: String,
        viewController: UIViewController
    ) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let destinationURL = documentsURL.appendingPathComponent(fileName)
        if isDownloadedUpdateCurrent(at: destinationURL, expectedSize: expectedSize) {
            shareDownloadedUpdate(at: destinationURL, from: viewController)
            return
        }
        
        let alert = UIAlertController(title: "Downloading Update", message: message, preferredStyle: .alert)
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0
        
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self, weak viewController, weak alert] location, _, error in
            DispatchQueue.main.async {
                guard let self,
                      let viewController,
                      let alert else {
                    return
                }
                
                self.updateProgressObservation = nil
                self.activeUpdateTask = nil
                
                if let error {
                    let nsError = error as NSError
                    guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else {
                        return
                    }
                    
                    SettingsViewUtils.dismissPresentedAlert(alert, from: viewController) {
                        AlertPresenter.show(title: "Download Failed", message: error.localizedDescription)
                    }
                    return
                }
                
                guard let location else {
                    return
                }
                
                try? FileManager.default.removeItem(at: destinationURL)
                try? FileManager.default.moveItem(at: location, to: destinationURL)
                SettingsViewUtils.dismissPresentedAlert(alert, from: viewController) {
                    self.shareDownloadedUpdate(at: destinationURL, from: viewController)
                }
            }
        }
        activeUpdateTask = task
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.activeUpdateTask?.cancel()
            self?.activeUpdateTask = nil
            self?.updateProgressObservation = nil
        })
        
        viewController.present(alert, animated: true) { [weak self, weak task] in
            guard let self,
                  let task else {
                return
            }
            
            SettingsViewUtils.addProgressView(progressView, to: alert)
            self.updateProgressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak progressView] progress, _ in
                DispatchQueue.main.async {
                    progressView?.setProgress(Float(progress.fractionCompleted), animated: true)
                }
            }
            task.resume()
        }
    }
    
    private func isDownloadedUpdateCurrent(at updateFileURL: URL, expectedSize: Int?) -> Bool {
        guard FileManager.default.fileExists(atPath: updateFileURL.path),
              let expectedSize,
              let attributes = try? FileManager.default.attributesOfItem(atPath: updateFileURL.path),
              let cachedSize = attributes[.size] as? NSNumber else {
            return false
        }
        
        return cachedSize.int64Value == Int64(expectedSize)
    }
    
    private func shareDownloadedUpdate(at updateFileURL: URL, from viewController: UIViewController) {
        let activityController = UIActivityViewController(activityItems: [updateFileURL], applicationActivities: nil)
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        viewController.present(activityController, animated: true)
    }
}
