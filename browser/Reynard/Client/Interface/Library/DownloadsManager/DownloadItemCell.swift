//
//  DownloadItemCell.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import MobileCoreServices

final class DownloadItemCell: UITableViewCell {
    static let reuseIdentifier = "DownloadItemCell"
    
    private static let sizeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private let iconView: UIImageView = {
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
    
    private let detailsLabel: UILabel = {
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
    private var representedItemID: UUID?
    private var lastDetailsLabelUpdateTime: TimeInterval = 0
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        let labelsStack = UIStackView(arrangedSubviews: [fileNameLabel, detailsLabel, progressView])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = 4
        
        contentView.addSubview(iconView)
        contentView.addSubview(labelsStack)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            
            labelsStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 13),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 13),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),
        ])
        
        separatorInset.left = 73
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layoutIfNeeded()
        let guideFrameInContent = contentView.layoutMarginsGuide.layoutFrame
        let guideFrameInCell = convert(guideFrameInContent, from: contentView)
        let rightInset = bounds.width - guideFrameInCell.maxX
        separatorInset = UIEdgeInsets(
            top: separatorInset.top,
            left: separatorInset.left,
            bottom: separatorInset.bottom,
            right: rightInset
        )
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        representedFileURL = nil
        representedItemID = nil
        lastDetailsLabelUpdateTime = 0
        contentView.alpha = 1
        fileNameLabel.textColor = .label
        detailsLabel.textColor = .secondaryLabel
        iconView.image = nil
        iconView.transform = .identity
        iconView.tintColor = .label
    }
    
    func apply(item: DownloadItemSnapshot) {
        fileNameLabel.text = item.fileName
        let isDeleted = item.state == .completed && !item.fileExists
        contentView.alpha = isDeleted ? 0.45 : 1
        fileNameLabel.textColor = isDeleted ? .secondaryLabel : .label
        detailsLabel.textColor = .secondaryLabel
        
        switch item.state {
        case .downloading:
            representedFileURL = nil
            let previousItemID = representedItemID
            representedItemID = item.id
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
            if previousItemID != item.id || now - lastDetailsLabelUpdateTime >= 0.5 || detailsLabel.text == nil {
                detailsLabel.text = detailsText
                lastDetailsLabelUpdateTime = now
            }
            progressView.isHidden = false
            if let totalBytes = item.totalBytes, totalBytes > 0 {
                progressView.progress = min(max(Float(item.downloadedBytes) / Float(totalBytes), 0), 1)
            } else {
                progressView.progress = 0
            }
            let placeholderIcon = Self.iconProvider.genericPlaceholderIcon()
            iconView.image = placeholderIcon
            iconView.transform = .identity
            iconView.tintColor = placeholderIcon == nil ? .label : nil
            
        case .completed:
            representedItemID = item.id
            lastDetailsLabelUpdateTime = 0
            detailsLabel.text = item.fileExists ? (item.totalBytes.map { Self.formattedByteCount($0) } ?? "Unknown size") : "Deleted"
            progressView.isHidden = true
            progressView.progress = 0
            iconView.transform = .identity
            iconView.tintColor = nil
            
            guard item.fileExists else {
                representedFileURL = nil
                iconView.image = Self.iconProvider.genericPlaceholderIcon()
                return
            }
            
            representedFileURL = item.fileURL
            iconView.image = item.fileURL.flatMap { Self.iconProvider.cachedIcon(for: $0) } ?? Self.iconProvider.genericPlaceholderIcon()
            
            guard let fileURL = item.fileURL else {
                return
            }
            
            Self.iconProvider.icon(for: fileURL, size: CGSize(width: 56, height: 56)) { [weak self] image in
                guard let self, self.representedFileURL == fileURL else {
                    return
                }
                
                if let image {
                    self.iconView.image = image
                } else {
                    self.iconView.image = Self.iconProvider.placeholderIcon(for: fileURL) ?? Self.iconProvider.genericPlaceholderIcon()
                }
            }
        }
    }
    
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

private final class DownloadFileIconProvider {
    static let shared = DownloadFileIconProvider()
    
    private let generator = QLThumbnailGenerator.shared
    private let cache = NSCache<NSURL, UIImage>()
    private let genericCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    
    func placeholderIcon(for fileURL: URL) -> UIImage? {
        placeholderIcon(fileName: fileURL.lastPathComponent, mimeType: nil)
    }
    
    func placeholderIcon(fileName: String, mimeType: String?) -> UIImage? {
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: mimeType)
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let placeholderURL = placeholderURL(fileName: fileName, mimeType: mimeType),
              let image = documentInteractionIcon(for: placeholderURL) else {
            return nil
        }
        
        genericCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    func genericPlaceholderIcon() -> UIImage? {
        let cacheKey: NSString = "generic"
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let placeholderURL = placeholderURL(fileName: "generic-file", mimeType: nil),
              let image = documentInteractionIcon(
                for: placeholderURL,
                uti: kUTTypeData as String,
                name: "Downloading"
              ) else {
            return nil
        }
        
        genericCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    func icon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        if let cachedImage = cache.object(forKey: fileURL as NSURL) {
            completion(cachedImage)
            return
        }
        
        generateIcon(for: fileURL, size: size, contentTypeIdentifier: nil) { [weak self] image in
            if let image {
                self?.cache.setObject(image, forKey: fileURL as NSURL)
                completion(image)
                return
            }
            
            self?.genericIcon(for: fileURL, size: size, completion: completion)
        }
    }
    
    func cachedIcon(for fileURL: URL) -> UIImage? {
        cache.object(forKey: fileURL as NSURL)
    }
    
    private func generateIcon(
        for fileURL: URL,
        size: CGSize,
        contentTypeIdentifier: String?,
        representationTypes: QLThumbnailGenerator.Request.RepresentationTypes = .all,
        completion: @escaping (UIImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: UIScreen.main.scale,
            representationTypes: representationTypes
        )
        request.iconMode = true
        if #available(iOS 14.0, *),
           let contentTypeIdentifier,
           let contentType = UTType(contentTypeIdentifier) {
            request.contentType = contentType
        }
        
        generator.generateBestRepresentation(for: request) { thumbnail, _ in
            DispatchQueue.main.async {
                completion(thumbnail?.uiImage)
            }
        }
    }
    
    private func genericIcon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let fileName = fileURL.lastPathComponent
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: nil)
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        guard let placeholderURL = placeholderURL(fileName: fileName, mimeType: nil) else {
            completion(nil)
            return
        }
        
        generateIcon(
            for: placeholderURL,
            size: size,
            contentTypeIdentifier: resolvedContentTypeIdentifier(fileName: fileName, mimeType: nil),
            representationTypes: .icon
        ) { [weak self] image in
            let resolvedImage = image ?? self?.documentInteractionIcon(for: placeholderURL)
            if let resolvedImage {
                self?.genericCache.setObject(resolvedImage, forKey: cacheKey)
            }
            completion(resolvedImage)
        }
    }
    
    private func placeholderURL(fileName: String, mimeType: String?) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let placeholderDirectory = cachesDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("IconPlaceholders", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: placeholderDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        
        let contentTypeIdentifier = resolvedContentTypeIdentifier(fileName: fileName, mimeType: mimeType)
        let existingExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let preferredExtension = existingExtension.isEmpty
        ? (preferredFilenameExtension(from: contentTypeIdentifier) ?? "")
        : existingExtension
        let placeholderName = preferredExtension.isEmpty ? "generic-file" : "generic-file.\(preferredExtension)"
        let placeholderURL = placeholderDirectory.appendingPathComponent(placeholderName)
        
        if !fileManager.fileExists(atPath: placeholderURL.path) {
            fileManager.createFile(atPath: placeholderURL.path, contents: Data())
        }
        
        return placeholderURL
    }
    
    private func placeholderCacheKey(fileName: String, mimeType: String?) -> NSString {
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension as NSString
        }
        if let mimeType, !mimeType.isEmpty {
            return mimeType.lowercased() as NSString
        }
        return "generic"
    }
    
    private func resolvedContentTypeIdentifier(fileName: String, mimeType: String?) -> String? {
        if let mimeType {
            if let uti = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
            )?.takeRetainedValue() {
                return uti as String
            }
        }
        
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension
        guard !pathExtension.isEmpty else {
            return nil
        }
        
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as CFString,
            nil
        )?.takeRetainedValue() as String?
    }
    
    private func preferredFilenameExtension(from contentTypeIdentifier: String?) -> String? {
        guard let contentTypeIdentifier else {
            return nil
        }
        return UTTypeCopyPreferredTagWithClass(
            contentTypeIdentifier as CFString,
            kUTTagClassFilenameExtension
        )?.takeRetainedValue() as String?
    }
    
    private func documentInteractionIcon(for fileURL: URL, uti: String? = nil, name: String? = nil) -> UIImage? {
        let controller = UIDocumentInteractionController(url: fileURL)
        controller.uti = uti
        controller.name = name
        
        return preferredDocumentInteractionIcon(from: controller.icons)
    }
    
    private func preferredDocumentInteractionIcon(from icons: [UIImage]) -> UIImage? {
        icons.last
    }
}

private extension DownloadItemCell {
    static let iconProvider = DownloadFileIconProvider.shared
}
