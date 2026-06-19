//
//  DownloadItemCell.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import UIKit

final class DownloadItemCell: UITableViewCell {
    private enum UX {
        static let labelsStackSpacing: CGFloat = 4
        static let iconSize: CGFloat = 44
        static let iconVerticalInset: CGFloat = 8
        static let labelsLeadingSpacing: CGFloat = 13
        static let labelsVerticalInset: CGFloat = 13
        static let separatorLeftInset: CGFloat = 73
        static let thumbnailRequestSize = CGSize(width: 56, height: 56)
    }
    
    static let reuseIdentifier = "DownloadItemCell"
    
    private static let iconProvider = DownloadFileIconProvider.shared
    
    private static let sizeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private let fileIconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .label
        return view
    }()
    
    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()
    
    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trackTintColor = .tertiarySystemFill
        view.progressTintColor = .label
        view.isHidden = true
        return view
    }()
    
    private var representedFileURL: URL?
    private var representedDownloadID: UUID?
    private var lastStatusUpdateTime: TimeInterval = 0
    
    // MARK: - Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        let labelsStack = UIStackView(arrangedSubviews: [fileNameLabel, statusLabel, progressView])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = UX.labelsStackSpacing
        
        contentView.addSubview(fileIconView)
        contentView.addSubview(labelsStack)
        
        NSLayoutConstraint.activate([
            fileIconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            fileIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileIconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.iconVerticalInset),
            fileIconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.iconVerticalInset),
            fileIconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            fileIconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            labelsStack.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: UX.labelsLeadingSpacing),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.labelsVerticalInset),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.labelsVerticalInset),
        ])
        
        separatorInset.left = UX.separatorLeftInset
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        LibrarySharedUtils.alignSeparatorWithReadableContent(in: self)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedFileURL = nil
        representedDownloadID = nil
        lastStatusUpdateTime = 0
        contentView.alpha = 1
        fileNameLabel.textColor = .label
        statusLabel.textColor = .secondaryLabel
        fileIconView.image = nil
        fileIconView.transform = .identity
        fileIconView.tintColor = .label
    }
    
    // MARK: - Configuration
    
    func configure(with item: DownloadItemSnapshot) {
        fileNameLabel.text = item.fileName
        let isDeleted = item.state == .completed && !item.fileExists
        contentView.alpha = isDeleted ? 0.45 : 1
        fileNameLabel.textColor = isDeleted ? .secondaryLabel : .label
        statusLabel.textColor = .secondaryLabel
        
        switch item.state {
        case .downloading:
            representedFileURL = nil
            let previousItemID = representedDownloadID
            representedDownloadID = item.id
            let downloadedText = Self.formattedByteCount(item.downloadedBytes)
            let sizeText = item.totalBytes.map { Self.formattedByteCount($0) }
            let speedText: String?
            if item.bytesPerSecond > 0 {
                speedText = "\(Self.formattedByteCount(item.bytesPerSecond))/sec"
            } else {
                speedText = nil
            }
            
            var detailsText = downloadedText
            if let sizeText {
                detailsText += " of \(sizeText)"
            }
            if let speedText {
                detailsText += " (\(speedText))"
            }
            
            let now = ProcessInfo.processInfo.systemUptime
            if previousItemID != item.id || now - lastStatusUpdateTime >= 0.5 || statusLabel.text == nil {
                statusLabel.text = detailsText
                lastStatusUpdateTime = now
            }
            progressView.isHidden = false
            if let totalBytes = item.totalBytes, totalBytes > 0 {
                progressView.progress = min(max(Float(item.downloadedBytes) / Float(totalBytes), 0), 1)
            } else {
                progressView.progress = 0
            }
            let placeholderIcon = Self.iconProvider.genericPlaceholderIcon()
            fileIconView.image = placeholderIcon
            fileIconView.transform = .identity
            fileIconView.tintColor = placeholderIcon == nil ? .label : nil
            
        case .completed:
            representedDownloadID = item.id
            lastStatusUpdateTime = 0
            statusLabel.text = item.fileExists ? (item.totalBytes.map { Self.formattedByteCount($0) } ?? "Unknown size") : "Deleted"
            progressView.isHidden = true
            progressView.progress = 0
            fileIconView.transform = .identity
            fileIconView.tintColor = nil
            
            guard item.fileExists else {
                representedFileURL = nil
                fileIconView.image = Self.iconProvider.genericPlaceholderIcon()
                return
            }
            
            representedFileURL = item.fileURL
            fileIconView.image = item.fileURL.flatMap { Self.iconProvider.cachedIcon(for: $0) } ?? Self.iconProvider.genericPlaceholderIcon()
            
            guard let fileURL = item.fileURL else {
                return
            }
            
            Self.iconProvider.icon(for: fileURL, size: UX.thumbnailRequestSize) { [weak self] image in
                guard let self, self.representedFileURL == fileURL else {
                    return
                }
                
                if let image {
                    self.fileIconView.image = image
                } else {
                    self.fileIconView.image = Self.iconProvider.placeholderIcon(for: fileURL) ?? Self.iconProvider.genericPlaceholderIcon()
                }
            }
        }
    }
    
    // MARK: - Formatting
    
    private static func formattedByteCount(_ byteCount: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(abs(byteCount))
        var unitIndex = 0
        
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            let bytesText = Int64(value)
            return "\(byteCount < 0 ? -bytesText : bytesText) \(units[unitIndex])"
        }
        
        let formattedValue = sizeNumberFormatter.string(from: NSNumber(value: byteCount < 0 ? -value : value)) ?? String(format: "%.1f", byteCount < 0 ? -value : value)
        return "\(formattedValue) \(units[unitIndex])"
    }
}
