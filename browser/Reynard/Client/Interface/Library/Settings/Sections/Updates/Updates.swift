//
//  Updates.swift
//  Reynard
//
//  Created by Minh Ton on 21/4/26.
//

import UIKit

extension SettingsRootViewController {
    var installedThroughTrollStore: Bool {
        let tsPath = Bundle.main.bundlePath + "/../_TrollStore"
        return access(tsPath, F_OK) == 0
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard visibleSections.indices.contains(indexPath.section),
              visibleSections[indexPath.section] == .updates,
              indexPath.row == 0 else {
            return UITableView.automaticDimension
        }
        return min(tableView.bounds.height * 0.55, 320)
    }
    
    func makeReleaseNotesCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        
        var appName = "Reynard Browser"
        var latestVersionStr = AppUpdates.shared.latestVersion
        var sizeStr = ""
        
        if let data = AppUpdates.shared.sourceData,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apps = json["apps"] as? [[String: Any]],
           let firstApp = apps.first {
            if let name = firstApp["name"] as? String { appName = name }
            if let versions = firstApp["versions"] as? [[String: Any]], let latestEntry = versions.first {
                if let v = latestEntry["version"] as? String { latestVersionStr = v }
                if let size = latestEntry["size"] as? Int {
                    sizeStr = String(format: "%.1f MB", Double(size) / (1024 * 1024))
                }
            }
        }
        
        let iconImageView = UIImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 13
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.backgroundColor = .secondarySystemFill
        iconImageView.image = appIconImage()
        
        let nameLabel = UILabel()
        nameLabel.text = appName
        nameLabel.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        nameLabel.numberOfLines = 1
        
        let versionLabel = UILabel()
        versionLabel.text = "Version \(latestVersionStr)"
        versionLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        versionLabel.textColor = .secondaryLabel
        
        let sizeLabel = UILabel()
        sizeLabel.text = sizeStr
        sizeLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        sizeLabel.textColor = .secondaryLabel
        
        let infoStack = UIStackView(arrangedSubviews: [nameLabel, versionLabel, sizeLabel])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.alignment = .leading
        
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(iconImageView)
        headerView.addSubview(infoStack)
        
        if AppUpdates.shared.cachedReleaseNotes == nil {
            AppUpdates.shared.cachedReleaseNotes = processReleaseNotes()
        }
        let releaseNotes = AppUpdates.shared.cachedReleaseNotes!
        
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.attributedText = releaseNotes
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        
        cell.contentView.addSubview(headerView)
        cell.contentView.addSubview(textView)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 56),
            iconImageView.heightAnchor.constraint(equalToConstant: 56),
            
            infoStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            infoStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 64),
            
            textView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
        ])
        
        return cell
    }
    
    func makeTrollStoreUpdateFooterView() -> UIView {
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.text = "Make sure TrollStore's URL Scheme is enabled."
        
        footerView.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func makeUpdateNowCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Update Now"
        cell.textLabel?.textColor = view.tintColor
        cell.textLabel?.textAlignment = .center
        return cell
    }
    
    private func processReleaseNotes() -> NSAttributedString {
        guard let data = AppUpdates.shared.sourceData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["apps"] as? [[String: Any]],
              let firstApp = apps.first,
              let versions = firstApp["versions"] as? [[String: Any]],
              let latestEntry = versions.first,
              let desc = latestEntry["localizedDescription"] as? String else {
            return NSAttributedString(string: "No release notes available.",
                                      attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote)])
        }
        
        let noteFont = UIFont.preferredFont(forTextStyle: .footnote)
        let h2Font = UIFont.boldSystemFont(ofSize: noteFont.pointSize + 3)
        let h3Font = UIFont.boldSystemFont(ofSize: noteFont.pointSize + 1)
        
        let normalized = desc
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        
        let result = NSMutableAttributedString()
        var pendingNewline = false
        
        for line in lines {
            if line.hasPrefix("<") || line.hasPrefix("![") { continue }
            
            if pendingNewline {
                result.append(NSAttributedString(string: "\n"))
            }
            pendingNewline = true
            
            if line.hasPrefix("## ") {
                let text = String(line.dropFirst(3))
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.paragraphSpacing = 4
                result.append(NSAttributedString(string: text, attributes: [.font: h2Font, .paragraphStyle: paraStyle]))
            } else if line.hasPrefix("### ") || line.hasPrefix("#### ") {
                let prefixLen = line.hasPrefix("#### ") ? 5 : 4
                let text = String(line.dropFirst(prefixLen))
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.paragraphSpacing = 2
                result.append(NSAttributedString(string: text, attributes: [.font: h3Font, .paragraphStyle: paraStyle]))
            } else {
                result.append(parseInlineMarkdown(line, defaultFont: noteFont))
            }
        }
        
        return result
    }
    
    private func parseInlineMarkdown(_ text: String, defaultFont: UIFont) -> NSAttributedString {
        if #available(iOS 15.0, *) {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
            if let attrStr = try? AttributedString(markdown: text, options: options) {
                let nsAttr = NSMutableAttributedString(attrStr)
                let fullRange = NSRange(location: 0, length: nsAttr.length)
                nsAttr.enumerateAttribute(.font, in: fullRange, options: []) { value, subrange, _ in
                    let sourceFont = (value as? UIFont) ?? defaultFont
                    let traits = sourceFont.fontDescriptor.symbolicTraits
                    let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits) ?? defaultFont.fontDescriptor
                    nsAttr.addAttribute(.font, value: UIFont(descriptor: descriptor, size: defaultFont.pointSize), range: subrange)
                }
                return nsAttr
            }
        }
        return processInlineBold(text, noteFont: defaultFont, boldFont: UIFont.boldSystemFont(ofSize: defaultFont.pointSize))
    }
    
    private func processInlineBold(_ text: String, noteFont: UIFont, boldFont: UIFont) -> NSAttributedString {
        var source = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        let result = NSMutableAttributedString()
        while !source.isEmpty {
            if let range = source.range(of: "**") {
                let before = String(source[..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: [.font: noteFont]))
                }
                source = String(source[range.upperBound...])
                if let closing = source.range(of: "**") {
                    let bold = String(source[..<closing.lowerBound])
                    result.append(NSAttributedString(string: bold, attributes: [.font: boldFont]))
                    source = String(source[closing.upperBound...])
                } else {
                    result.append(NSAttributedString(string: "**" + source, attributes: [.font: noteFont]))
                    source = ""
                }
            } else {
                result.append(NSAttributedString(string: source, attributes: [.font: noteFont]))
                break
            }
        }
        return result
    }
    
    private func appIconImage() -> UIImage? {
        let icons = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        ?? (Bundle.main.infoDictionary?["CFBundleIcons~ipad"] as? [String: Any])
        if let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastName = iconFiles.last,
           let image = UIImage(named: lastName) {
            return image
        }
        return UIImage(named: "AppIcon")
    }
    
    func presentUpdateAlert() {
        guard let data = AppUpdates.shared.sourceData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["apps"] as? [[String: Any]],
              let firstApp = apps.first,
              let versions = firstApp["versions"] as? [[String: Any]],
              let latestEntry = versions.first,
              let downloadURLStr = latestEntry["downloadURL"] as? String,
              let downloadURL = URL(string: downloadURLStr) else {
            presentAlert(title: "Update Unavailable", message: "Could not retrieve the download URL.")
            return
        }
        
        let expectedSize = latestEntry["size"] as? Int
        if installedThroughTrollStore {
            let tsURLStr = downloadURLStr.replacingOccurrences(of: "Reynard.ipa", with: "Reynard-TrollStore.tipa")
            let encoded = tsURLStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tsURLStr
            
            if let schemeURL = URL(string: "apple-magnifier://install?url=" + encoded),
               UIApplication.shared.canOpenURL(schemeURL) {
                UIApplication.shared.open(schemeURL)
                return
            }
        } else {
            startUpdateDownload(
                from: downloadURL,
                fileName: "Reynard.ipa",
                expectedSize: expectedSize,
                message: "When the download finishes, choose the app that you used to sideload Reynard in the share sheet to install the update."
            )
        }
    }
    
    private func startUpdateDownload(from url: URL, fileName: String, expectedSize: Int?, message: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dest = docs.appendingPathComponent(fileName)
        
        if isCurrentDownloadedUpdate(at: dest, expectedSize: expectedSize) {
            presentDownloadedUpdate(at: dest)
            return
        }
        
        let alert = UIAlertController(
            title: "Downloading Update",
            message: message,
            preferredStyle: .alert
        )
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0
        
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self, weak alert] location, _, error in
            DispatchQueue.main.async {
                self?.updateProgressObservation = nil
                self?.activeUpdateTask = nil
                guard let alert else { return }
                if let error = error {
                    let nsErr = error as NSError
                    guard nsErr.domain != NSURLErrorDomain || nsErr.code != NSURLErrorCancelled else { return }
                    self?.dismissAlertIfPresented(alert) {
                        self?.presentAlert(title: "Download Failed", message: error.localizedDescription)
                    }
                    return
                }
                guard let location else { return }
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: location, to: dest)
                self?.dismissAlertIfPresented(alert) {
                    self?.presentDownloadedUpdate(at: dest)
                }
            }
        }
        activeUpdateTask = task
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.activeUpdateTask?.cancel()
            self?.activeUpdateTask = nil
            self?.updateProgressObservation = nil
        })
        
        present(alert, animated: true) { [weak self] in
            guard let self else { return }
            self.attachProgressView(progressView, to: alert)
            self.updateProgressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak progressView] progress, _ in
                DispatchQueue.main.async {
                    progressView?.setProgress(Float(progress.fractionCompleted), animated: true)
                }
            }
            task.resume()
        }
    }
    
    private func isCurrentDownloadedUpdate(at fileURL: URL, expectedSize: Int?) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let expectedSize,
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let cachedSize = attributes[.size] as? NSNumber else { return false }
        
        return cachedSize.int64Value == Int64(expectedSize)
    }
    
    private func presentDownloadedUpdate(at fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(activity, animated: true)
    }
}
