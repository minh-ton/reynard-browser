//
//  FilePicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit

@MainActor
final class FilePicker: NSObject {
    enum UX {
        static let imageCompressionQuality: CGFloat = 0.92
    }
    
    enum Mode: String, Sendable {
        case single
        case multiple
        case folder
    }
    
    enum Capture: Int {
        case none = 0
        case any = 1
        case user = 2
        case environment = 3
    }
    
    enum PickerAction {
        case photoLibrary
        case camera
        case chooseFile
    }
    
    enum MediaKind: Sendable {
        case image
        case video
    }
    
    struct AcceptedTypes: Sendable {
        let documentTypeIdentifiers: [String]
        let legacyDocumentTypes: [String]
        let mediaTypes: [String]
        let captureMediaKind: MediaKind?
    }
    
    struct FolderEntry: Sendable {
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
    
    struct SelectionResult: Sendable {
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
    
    let mode: Mode
    let capture: Capture
    let anchorRect: CGRect
    weak var geckoView: UIView?
    
    let acceptedTypes: AcceptedTypes
    let stagingDirectoryURL: URL
    
    var continuation: CheckedContinuation<[String: Any]?, Never>?
    var anchorButton: FilePickerMenuAnchorButton?
    weak var presentedController: UIViewController?
    var launchedFollowupPicker = false
    
    // MARK: - Lifecycle
    
    init(
        promptId: String,
        mode: String,
        mimeTypes: [String],
        capture: Int,
        anchorRect: CGRect,
        geckoView: UIView
    ) {
        self.mode = Mode(rawValue: mode) ?? .single
        self.capture = Capture(rawValue: capture) ?? .none
        self.anchorRect = anchorRect
        self.geckoView = geckoView
        self.acceptedTypes = Self.resolveAcceptedTypes(from: mimeTypes)
        self.stagingDirectoryURL = Self.stagingDirectoryURL(promptId: promptId)
        super.init()
    }
    
    // MARK: - Presentation
    
    func present() async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            if let preferredInitialAction {
                DispatchQueue.main.async { [weak self] in
                    self?.performAction(preferredInitialAction)
                }
                return
            }
            
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
    
    // MARK: - Actions
    
    func performAction(_ action: PickerAction) {
        switch action {
        case .photoLibrary:
            presentMediaPicker(sourceType: .photoLibrary)
        case .camera:
            presentMediaPicker(sourceType: .camera)
        case .chooseFile:
            presentDocumentPicker()
        }
    }
    
    // MARK: - Completion
    
    func finish(with result: [String: Any]?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
    
    // MARK: - Helpers
    
    static func stagingDirectoryURL(promptId: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GeckoFilePicker", isDirectory: true)
            .appendingPathComponent(promptId, isDirectory: true)
    }
}
