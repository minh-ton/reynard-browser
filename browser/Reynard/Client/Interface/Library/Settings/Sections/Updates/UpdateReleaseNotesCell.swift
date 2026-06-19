//
//  UpdateReleaseNotesCell.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class UpdateReleaseNotesCell: UITableViewCell {
    private enum UX {
        static let iconSize: CGFloat = 56
        static let iconCornerRadius: CGFloat = 13
        static let contentInset: CGFloat = 16
        static let headerTopInset: CGFloat = 12
        static let headerHeight: CGFloat = 64
        static let iconToTextSpacing: CGFloat = 12
        static let textViewTopSpacing: CGFloat = 8
        static let releaseNotesBottomInset: CGFloat = 16
        static let infoStackSpacing: CGFloat = 2
    }
    
    init() {
        super.init(style: .default, reuseIdentifier: nil)
        configureCell()
        installContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Setup
    
    private func configureCell() {
        selectionStyle = .none
    }
    
    private func installContent() {
        let updateInfo = currentUpdateInfo()
        let iconView = appIconView()
        let infoStackView = metadataStackView(updateInfo: updateInfo)
        let headerView = releaseNotesHeaderView(iconView: iconView, infoStackView: infoStackView)
        let releaseNotesView = releaseNotesTextView()
        
        contentView.addSubview(headerView)
        contentView.addSubview(releaseNotesView)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            infoStackView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: UX.iconToTextSpacing),
            infoStackView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            infoStackView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.headerTopInset),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.contentInset),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.contentInset),
            headerView.heightAnchor.constraint(equalToConstant: UX.headerHeight),
            
            releaseNotesView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: UX.textViewTopSpacing),
            releaseNotesView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            releaseNotesView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.contentInset),
            releaseNotesView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.contentInset),
        ])
    }
    
    private func appIconView() -> UIImageView {
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = UX.iconCornerRadius
        iconView.layer.cornerCurve = .continuous
        iconView.backgroundColor = .secondarySystemFill
        iconView.image = appIconImage()
        return iconView
    }
    
    private func metadataStackView(updateInfo: UpdateInfo) -> UIStackView {
        let nameLabel = UILabel()
        nameLabel.text = updateInfo.appName
        nameLabel.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        nameLabel.numberOfLines = 1
        
        let versionLabel = UILabel()
        versionLabel.text = "Version \(updateInfo.version)"
        versionLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        versionLabel.textColor = .secondaryLabel
        
        let sizeLabel = UILabel()
        sizeLabel.text = updateInfo.size
        sizeLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        sizeLabel.textColor = .secondaryLabel
        
        let infoStackView = UIStackView(arrangedSubviews: [nameLabel, versionLabel, sizeLabel])
        infoStackView.translatesAutoresizingMaskIntoConstraints = false
        infoStackView.axis = .vertical
        infoStackView.spacing = UX.infoStackSpacing
        infoStackView.alignment = .leading
        return infoStackView
    }
    
    private func releaseNotesHeaderView(iconView: UIImageView, infoStackView: UIStackView) -> UIView {
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(iconView)
        headerView.addSubview(infoStackView)
        return headerView
    }
    
    private func releaseNotesTextView() -> UITextView {
        if BrowserUpdates.shared.cachedReleaseNotes == nil {
            BrowserUpdates.shared.cachedReleaseNotes = processReleaseNotes()
        }
        
        let releaseNotesView = UITextView()
        releaseNotesView.translatesAutoresizingMaskIntoConstraints = false
        releaseNotesView.isEditable = false
        releaseNotesView.isScrollEnabled = true
        releaseNotesView.showsVerticalScrollIndicator = false
        releaseNotesView.isSelectable = false
        releaseNotesView.backgroundColor = .clear
        releaseNotesView.attributedText = BrowserUpdates.shared.cachedReleaseNotes
        releaseNotesView.textColor = .label
        releaseNotesView.textContainerInset = UIEdgeInsets(top: UX.textViewTopSpacing, left: 0, bottom: 0, right: 0)
        releaseNotesView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: UX.releaseNotesBottomInset, right: 0)
        releaseNotesView.textContainer.lineFragmentPadding = 0
        return releaseNotesView
    }
    
    // MARK: - Data
    
    private struct UpdateInfo {
        let appName: String
        let version: String
        let size: String
    }
    
    private func currentUpdateInfo() -> UpdateInfo {
        var appName = "Reynard Browser"
        var latestVersionString = BrowserUpdates.shared.latestVersion
        var sizeString = ""
        
        if let updateFeedData = BrowserUpdates.shared.sourceData,
           let updateFeed = try? JSONSerialization.jsonObject(with: updateFeedData) as? [String: Any],
           let appEntries = updateFeed["apps"] as? [[String: Any]],
           let appEntry = appEntries.first {
            if let name = appEntry["name"] as? String {
                appName = name
            }
            if let versions = appEntry["versions"] as? [[String: Any]],
               let latestEntry = versions.first {
                if let version = latestEntry["version"] as? String {
                    latestVersionString = version
                }
                if let size = latestEntry["size"] as? Int {
                    sizeString = String(format: "%.1f MB", Double(size) / (1024 * 1024))
                }
            }
        }
        
        return UpdateInfo(appName: appName, version: latestVersionString, size: sizeString)
    }
    
    // MARK: - Release Notes
    
    private func processReleaseNotes() -> NSAttributedString {
        guard let updateFeedData = BrowserUpdates.shared.sourceData,
              let updateFeed = try? JSONSerialization.jsonObject(with: updateFeedData) as? [String: Any],
              let appEntries = updateFeed["apps"] as? [[String: Any]],
              let appEntry = appEntries.first,
              let versions = appEntry["versions"] as? [[String: Any]],
              let latestEntry = versions.first,
              let description = latestEntry["localizedDescription"] as? String else {
            return NSAttributedString(
                string: "No release notes available.",
                attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote)]
            )
        }
        
        let noteFont = UIFont.preferredFont(forTextStyle: .footnote)
        let h2Font = UIFont.boldSystemFont(ofSize: noteFont.pointSize + 3)
        let h3Font = UIFont.boldSystemFont(ofSize: noteFont.pointSize + 1)
        let normalizedDescription = description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedDescription.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var needsNewline = false
        
        for line in lines {
            if line.hasPrefix("<") || line.hasPrefix("![") {
                continue
            }
            
            if needsNewline {
                result.append(NSAttributedString(string: "\n"))
            }
            needsNewline = true
            
            if line.hasPrefix("## ") {
                appendHeading(String(line.dropFirst(3)), font: h2Font, spacing: 4, to: result)
            } else if line.hasPrefix("### ") || line.hasPrefix("#### ") {
                let prefixLength = line.hasPrefix("#### ") ? 5 : 4
                appendHeading(String(line.dropFirst(prefixLength)), font: h3Font, spacing: 2, to: result)
            } else {
                result.append(parseInlineMarkdown(line, defaultFont: noteFont))
            }
        }
        
        return result
    }
    
    private func appendHeading(_ text: String, font: UIFont, spacing: CGFloat, to result: NSMutableAttributedString) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = spacing
        result.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraphStyle]))
    }
    
    private func parseInlineMarkdown(_ text: String, defaultFont: UIFont) -> NSAttributedString {
        if #available(iOS 15.0, *) {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
            if let attributedString = try? AttributedString(markdown: text, options: options) {
                let nsAttributedString = NSMutableAttributedString(attributedString)
                let fullRange = NSRange(location: 0, length: nsAttributedString.length)
                nsAttributedString.enumerateAttribute(.font, in: fullRange, options: []) { value, subrange, _ in
                    let sourceFont = (value as? UIFont) ?? defaultFont
                    let traits = sourceFont.fontDescriptor.symbolicTraits
                    let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits) ?? defaultFont.fontDescriptor
                    nsAttributedString.addAttribute(
                        .font,
                        value: UIFont(descriptor: descriptor, size: defaultFont.pointSize),
                        range: subrange
                    )
                }
                return nsAttributedString
            }
        }
        
        return processInlineBold(
            text,
            noteFont: defaultFont,
            boldFont: UIFont.boldSystemFont(ofSize: defaultFont.pointSize)
        )
    }
    
    private func processInlineBold(_ text: String, noteFont: UIFont, boldFont: UIFont) -> NSAttributedString {
        var remainingMarkdown = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        let result = NSMutableAttributedString()
        
        while !remainingMarkdown.isEmpty {
            if let range = remainingMarkdown.range(of: "**") {
                let before = String(remainingMarkdown[..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: [.font: noteFont]))
                }
                
                remainingMarkdown = String(remainingMarkdown[range.upperBound...])
                if let closingRange = remainingMarkdown.range(of: "**") {
                    let bold = String(remainingMarkdown[..<closingRange.lowerBound])
                    result.append(NSAttributedString(string: bold, attributes: [.font: boldFont]))
                    remainingMarkdown = String(remainingMarkdown[closingRange.upperBound...])
                } else {
                    result.append(NSAttributedString(string: "**" + remainingMarkdown, attributes: [.font: noteFont]))
                    remainingMarkdown = ""
                }
            } else {
                result.append(NSAttributedString(string: remainingMarkdown, attributes: [.font: noteFont]))
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
}
