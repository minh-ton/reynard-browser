//
//  FilePicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

@MainActor
final class FilePicker: NSObject {
    private enum Mode: String, Sendable {
        case single
        case multiple
        case folder
    }
    
    private enum Capture: Int {
        case none = 0
        case any = 1
        case user = 2
        case environment = 3
    }
    
    private enum PickerAction {
        case photoLibrary
        case camera
        case chooseFile
    }
    
    private struct AcceptedTypes: Sendable {
        let documentTypeIdentifiers: [String]
        let legacyDocumentTypes: [String]
        let mediaTypes: [String]
    }
    
    private struct FolderEntry: Sendable {
        let filePath: String
        let relativePath: String
        let name: String
        let type: String
        let lastModified: Double
        
        var dictionary: [String: Any] {
            [
                "filePath": filePath,
                "relativePath": relativePath,
                "name": name,
                "type": type,
                "lastModified": lastModified,
            ]
        }
    }
    
    private struct SelectionResult: Sendable {
        let files: [String]
        let filesInWebKitDirectory: [FolderEntry]
        
        var promptResult: [String: Any] {
            var result: [String: Any] = ["files": files]
            if !filesInWebKitDirectory.isEmpty {
                result["filesInWebKitDirectory"] = filesInWebKitDirectory.map(\.dictionary)
            }
            return result
        }
    }
    
    private let promptId: String
    private let mode: Mode
    private let capture: Capture
    private let anchorRect: CGRect
    private weak var geckoView: UIView?
    
    private let acceptedTypes: AcceptedTypes
    private let stagingDirectoryURL: URL
    
    private var continuation: CheckedContinuation<[String: Any]?, Never>?
    private var anchorButton: FileMenuAnchorButton?
    private weak var presentedController: UIViewController?
    private var launchedFollowupPicker = false
    
    init(
        promptId: String,
        mode: String,
        mimeTypes: [String],
        capture: Int,
        anchorRect: CGRect,
        geckoView: UIView
    ) {
        self.promptId = promptId
        self.mode = Mode(rawValue: mode) ?? .single
        self.capture = Capture(rawValue: capture) ?? .none
        self.anchorRect = anchorRect
        self.geckoView = geckoView
        self.acceptedTypes = Self.resolveAcceptedTypes(from: mimeTypes)
        self.stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeckoFilePicker", isDirectory: true)
            .appendingPathComponent(promptId, isDirectory: true)
        super.init()
    }
    
    func present() async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let actions = availableActions
            if actions.count == 1, let action = actions.first {
                DispatchQueue.main.async { [weak self] in
                    self?.performAction(action)
                }
            } else {
                showMenu()
            }
        }
    }
    
    func cancelAndDismiss() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        presentedController?.dismiss(animated: false)
        presentedController = nil
        finish(with: nil)
    }
    
    private func showMenu() {
        guard let geckoView = geckoView else {
            finish(with: nil)
            return
        }

        guard #available(iOS 14.0, *) else {
            showActionSheet(in: geckoView)
            return
        }
        
        if anchorRect.isEmpty {
            showActionSheet(in: geckoView)
            return
        }
        
        let button = FileMenuAnchorButton(frame: anchorRect)
        button.backgroundColor = .clear
        button.menu = buildMenu()
        button.showsMenuAsPrimaryAction = true
        button.onMenuDismissed = { [weak self] in
            self?.handleMenuDismissed()
        }
        
        geckoView.addSubview(button)
        anchorButton = button
        
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.anchorButton else { return }
            let interaction = button.interactions.compactMap { $0 as? UIContextMenuInteraction }.first
            guard let interaction else {
                self?.handleMenuDismissed()
                return
            }
            
            let selector = NSSelectorFromString("_presentMenuAtLocation:")
            if interaction.responds(to: selector) {
                let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                let imp = interaction.method(for: selector)
                typealias PresentFunc = @convention(c) (AnyObject, Selector, CGPoint) -> Void
                let present = unsafeBitCast(imp, to: PresentFunc.self)
                present(interaction, selector, center)
            } else {
                self?.handleMenuDismissed()
            }
        }
    }
    
    private func buildMenu() -> UIMenu {
        let photoAction = UIAction(
            title: "Photo Library",
            image: UIImage(systemName: "photo.on.rectangle"),
            attributes: canUsePhotoLibrary ? [] : .disabled
        ) { [weak self] _ in
            self?.launchFollowupPicker {
                self?.performAction(.photoLibrary)
            }
        }
        
        let cameraAction = UIAction(
            title: "Take Photo",
            image: UIImage(systemName: "camera"),
            attributes: canUseCamera ? [] : .disabled
        ) { [weak self] _ in
            self?.launchFollowupPicker {
                self?.performAction(.camera)
            }
        }
        
        let chooserTitle = mode == .folder ? "Choose Folder" : "Choose File"
        let chooserAction = UIAction(
            title: chooserTitle,
            image: UIImage(systemName: "doc"),
            attributes: []
        ) { [weak self] _ in
            self?.launchFollowupPicker {
                self?.performAction(.chooseFile)
            }
        }
        
        return UIMenu(children: [photoAction, cameraAction, chooserAction])
    }
    
    private var canUsePhotoLibrary: Bool {
        !acceptedTypes.mediaTypes.isEmpty &&
        UIImagePickerController.isSourceTypeAvailable(.photoLibrary) &&
        !resolvedAvailableMediaTypes(for: .photoLibrary).isEmpty
    }
    
    private var canUseCamera: Bool {
        !acceptedTypes.mediaTypes.isEmpty &&
        UIImagePickerController.isSourceTypeAvailable(.camera) &&
        !resolvedAvailableMediaTypes(for: .camera).isEmpty
    }
    
    private var availableActions: [PickerAction] {
        var actions: [PickerAction] = []
        if canUsePhotoLibrary {
            actions.append(.photoLibrary)
        }
        if canUseCamera {
            actions.append(.camera)
        }
        actions.append(.chooseFile)
        return actions
    }
    
    private func launchFollowupPicker(_ action: @escaping @MainActor () -> Void) {
        launchedFollowupPicker = true
        DispatchQueue.main.async(execute: action)
    }
    
    private func showActionSheet(in geckoView: UIView) {
        guard let presentingVC = geckoView.nearestViewController() else {
            finish(with: nil)
            return
        }
        
        let chooserTitle = mode == .folder ? "Choose Folder" : "Choose File"
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if canUsePhotoLibrary {
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
                self?.launchFollowupPicker {
                    self?.performAction(.photoLibrary)
                }
            })
        }
        
        if canUseCamera {
            alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.launchFollowupPicker {
                    self?.performAction(.camera)
                }
            })
        }
        
        alert.addAction(UIAlertAction(title: chooserTitle, style: .default) { [weak self] _ in
            self?.launchFollowupPicker {
                self?.performAction(.chooseFile)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(with: nil)
        })
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = CGRect(x: geckoView.bounds.midX, y: geckoView.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presentingVC.present(alert, animated: true)
        presentedController = alert
    }
    
    private func performAction(_ action: PickerAction) {
        switch action {
        case .photoLibrary:
            presentMediaPicker(sourceType: .photoLibrary)
        case .camera:
            presentMediaPicker(sourceType: .camera)
        case .chooseFile:
            presentDocumentPicker()
        }
    }
    
    private func handleMenuDismissed() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        if launchedFollowupPicker {
            return
        }
        finish(with: nil)
    }
    
    private func presentDocumentPicker() {
        guard let geckoView = geckoView,
              let presentingVC = geckoView.nearestViewController() else {
            finish(with: nil)
            return
        }
        
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            if mode == .folder {
                picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [UTType.folder],
                    asCopy: false
                )
            } else {
                let contentTypes = acceptedTypes.documentTypeIdentifiers.compactMap { UTType($0) }
                picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: contentTypes.isEmpty ? [UTType.item] : contentTypes
                )
            }
        } else {
            let legacyTypes = acceptedTypes.legacyDocumentTypes.isEmpty
                ? [kUTTypeItem as String]
                : acceptedTypes.legacyDocumentTypes
            picker = UIDocumentPickerViewController(documentTypes: legacyTypes, in: .open)
        }
        picker.delegate = self
        picker.presentationController?.delegate = self
        picker.allowsMultipleSelection = mode == .multiple
        presentingVC.present(picker, animated: true)
        presentedController = picker
    }
    
    private func presentMediaPicker(sourceType: UIImagePickerController.SourceType) {
        guard let geckoView = geckoView,
              let presentingVC = geckoView.nearestViewController() else {
            finish(with: nil)
            return
        }
        
        let mediaTypes = resolvedAvailableMediaTypes(for: sourceType)
        guard !mediaTypes.isEmpty else {
            finish(with: nil)
            return
        }
        
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        picker.mediaTypes = mediaTypes
        if sourceType == .camera {
            picker.modalPresentationStyle = .fullScreen
            picker.isModalInPresentation = true
        }
        picker.presentationController?.delegate = self
        
        if sourceType == .camera {
            let preferredDevice = resolvedCameraDevice()
            if UIImagePickerController.isCameraDeviceAvailable(preferredDevice) {
                picker.cameraDevice = preferredDevice
            }
            if mediaTypes == [kUTTypeMovie as String] {
                picker.cameraCaptureMode = .video
            }
        }
        
        presentingVC.present(picker, animated: true)
        presentedController = picker
    }
    
    private func resolvedAvailableMediaTypes(
        for sourceType: UIImagePickerController.SourceType
    ) -> [String] {
        let availableTypes = Set(UIImagePickerController.availableMediaTypes(for: sourceType) ?? [])
        return acceptedTypes.mediaTypes.filter { availableTypes.contains($0) }
    }
    
    private func resolvedCameraDevice() -> UIImagePickerController.CameraDevice {
        switch capture {
        case .user:
            return .front
        case .environment, .any, .none:
            return .rear
        }
    }
    
    private func finish(with result: [String: Any]?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
    
    private static func resolveAcceptedTypes(from mimeTypes: [String]) -> AcceptedTypes {
        let filters = mimeTypes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        if filters.isEmpty || filters.contains("*/*") {
            return AcceptedTypes(
                documentTypeIdentifiers: [kUTTypeItem as String],
                legacyDocumentTypes: [kUTTypeItem as String],
                mediaTypes: [kUTTypeImage as String, kUTTypeMovie as String]
            )
        }
        
        var documentTypeIdentifiers: [String] = []
        var legacyDocumentTypes: [String] = []
        var mediaTypes: Set<String> = []
        
        for filter in filters {
            switch filter {
            case "image/*":
                documentTypeIdentifiers.append(kUTTypeImage as String)
                legacyDocumentTypes.append(kUTTypeImage as String)
                mediaTypes.insert(kUTTypeImage as String)
                continue
            case "video/*":
                documentTypeIdentifiers.append(kUTTypeMovie as String)
                legacyDocumentTypes.append(kUTTypeMovie as String)
                mediaTypes.insert(kUTTypeMovie as String)
                continue
            case "audio/*":
                documentTypeIdentifiers.append(kUTTypeAudio as String)
                legacyDocumentTypes.append(kUTTypeAudio as String)
                continue
            default:
                break
            }

            documentTypeIdentifiers.append(filter)
            legacyDocumentTypes.append(filter)
            if filter.hasPrefix("image/") {
                mediaTypes.insert(kUTTypeImage as String)
            }
            if filter.hasPrefix("video/") {
                mediaTypes.insert(kUTTypeMovie as String)
            }
        }
        
        if documentTypeIdentifiers.isEmpty {
            documentTypeIdentifiers = [kUTTypeItem as String]
        }
        if legacyDocumentTypes.isEmpty {
            legacyDocumentTypes = [kUTTypeItem as String]
        }
        
        return AcceptedTypes(
            documentTypeIdentifiers: Array(Set(documentTypeIdentifiers)).sorted(),
            legacyDocumentTypes: Array(Set(legacyDocumentTypes)).sorted(),
            mediaTypes: Array(mediaTypes).sorted()
        )
    }
    
    private func prepareDocumentResult(from urls: [URL]) async -> SelectionResult? {
        let selectedURLs = mode == .multiple ? urls : Array(urls.prefix(1))
        let mode = self.mode
        let stagingDirectoryURL = self.stagingDirectoryURL
        
        return await Task.detached(priority: .userInitiated) {
            switch mode {
            case .folder:
                guard let url = selectedURLs.first else { return nil }
                return try? Self.stageFolder(from: url, in: stagingDirectoryURL)
            case .single, .multiple:
                return try? Self.stageFiles(from: selectedURLs, in: stagingDirectoryURL)
            }
        }.value
    }
    
    private func prepareMediaResult(
        mediaURL: URL?,
        imageURL: URL?,
        imageData: Data?
    ) async -> SelectionResult? {
        let stagingDirectoryURL = self.stagingDirectoryURL
        
        return await Task.detached(priority: .userInitiated) {
            if let mediaURL {
                return try? Self.stageFiles(from: [mediaURL], in: stagingDirectoryURL)
            }
            if let imageURL {
                return try? Self.stageFiles(from: [imageURL], in: stagingDirectoryURL)
            }
            if let imageData {
                return try? Self.stageImageData(imageData, in: stagingDirectoryURL)
            }
            return nil
        }.value
    }
    
    nonisolated private static func stageFiles(from urls: [URL], in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        let copiedURLs = try urls.map { try copyItem(at: $0, into: directory, preferredName: nil) }
        return SelectionResult(files: copiedURLs.map(\.path), filesInWebKitDirectory: [])
    }
    
    nonisolated private static func stageImageData(_ imageData: Data, in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        let destinationURL = uniqueDestinationURL(in: directory, preferredName: "photo.jpg")
        try imageData.write(to: destinationURL, options: .atomic)
        return SelectionResult(files: [destinationURL.path], filesInWebKitDirectory: [])
    }
    
    nonisolated private static func stageFolder(from url: URL, in directory: URL) throws -> SelectionResult {
        try prepareDirectory(directory)
        
        let rootName = sanitizeFileName(url.lastPathComponent.isEmpty ? "Folder" : url.lastPathComponent)
        let destinationURL = directory.appendingPathComponent(rootName, isDirectory: true)
        
        try withSecurityScopedAccess(to: url) {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
        }
        
        let enumerator = FileManager.default.enumerator(
            at: destinationURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var entries: [FolderEntry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }
            
            let relativeComponent = fileURL.path.replacingOccurrences(of: destinationURL.path + "/", with: "")
            let relativePath = rootName + "/" + relativeComponent
            entries.append(
                FolderEntry(
                    filePath: fileURL.path,
                    relativePath: relativePath,
                    name: fileURL.lastPathComponent,
                    type: mimeType(for: fileURL),
                    lastModified: (resourceValues.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000
                )
            )
        }
        
        return SelectionResult(files: [destinationURL.path], filesInWebKitDirectory: entries)
    }
    
    nonisolated private static func prepareDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    
    nonisolated private static func copyItem(at sourceURL: URL, into directory: URL, preferredName: String?) throws -> URL {
        try withSecurityScopedAccess(to: sourceURL) {
            let fileManager = FileManager.default
            let destinationURL = uniqueDestinationURL(
                in: directory,
                preferredName: preferredName ?? sourceURL.lastPathComponent
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }
    
    nonisolated private static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }
    
    nonisolated private static func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let sanitizedName = sanitizeFileName(preferredName.isEmpty ? "File" : preferredName)
        let extensionPart = URL(fileURLWithPath: sanitizedName).pathExtension
        let baseName = extensionPart.isEmpty
        ? sanitizedName
        : String(sanitizedName.dropLast(extensionPart.count + 1))
        
        var candidate = directory.appendingPathComponent(sanitizedName, isDirectory: false)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = "-\(index)"
            let fileName = extensionPart.isEmpty ? baseName + suffix : baseName + suffix + "." + extensionPart
            candidate = directory.appendingPathComponent(fileName, isDirectory: false)
            index += 1
        }
        return candidate
    }
    
    nonisolated private static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\n")
        let pieces = name.components(separatedBy: invalidCharacters)
        let sanitized = pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "File" : sanitized
    }
    
    nonisolated private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension as CFString
        guard let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            ext,
            nil
        )?.takeRetainedValue() else {
            return "application/octet-stream"
        }
        guard let mime = UTTypeCopyPreferredTagWithClass(
            uti,
            kUTTagClassMIMEType
        )?.takeRetainedValue() else {
            return "application/octet-stream"
        }
        return mime as String
    }
}

extension FilePicker: UIDocumentPickerDelegate {
    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentedController = nil
            let result = await prepareDocumentResult(from: urls)
            finish(with: result?.promptResult)
        }
    }
    
    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentedController = nil
            finish(with: nil)
        }
    }
}

extension FilePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            picker.dismiss(animated: true)
            presentedController = nil
            finish(with: nil)
        }
    }
    
    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let mediaURL = info[.mediaURL] as? URL
        let imageURL = info[.imageURL] as? URL
        let imageData = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92)
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            picker.dismiss(animated: true)
            presentedController = nil
            let result = await prepareMediaResult(mediaURL: mediaURL, imageURL: imageURL, imageData: imageData)
            finish(with: result?.promptResult)
        }
    }
}

extension FilePicker: UIAdaptivePresentationControllerDelegate {
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentedController = nil
            finish(with: nil)
        }
    }
}

private final class FileMenuAnchorButton: UIButton {
    var onMenuDismissed: (() -> Void)?
    
    @available(iOS 14.0, *)
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onMenuDismissed?()
    }
}
