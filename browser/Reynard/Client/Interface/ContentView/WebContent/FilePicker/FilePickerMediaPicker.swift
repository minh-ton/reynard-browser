//
//  FilePickerMediaPicker.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
@preconcurrency import PhotosUI
import UIKit

extension FilePicker {
    // MARK: - Availability
    
    @available(iOS 14.0, *)
    var photoLibraryFilter: PHPickerFilter? {
        let mediaTypes = Set(acceptedTypes.mediaTypes)
        let supportsImages = mediaTypes.contains(kUTTypeImage as String)
        let supportsVideos = mediaTypes.contains(kUTTypeMovie as String)
        
        switch (supportsImages, supportsVideos) {
        case (true, true):
            return .any(of: [.images, .videos])
        case (true, false):
            return .images
        case (false, true):
            return .videos
        case (false, false):
            return nil
        }
    }
    
    var canUsePhotoLibrary: Bool {
        guard !acceptedTypes.mediaTypes.isEmpty else {
            return false
        }
        
        if #available(iOS 14.0, *) {
            return photoLibraryFilter != nil
        }
        
        return UIImagePickerController.isSourceTypeAvailable(.photoLibrary) &&
        !resolvedAvailableMediaTypes(for: .photoLibrary).isEmpty
    }
    
    var canUseCamera: Bool {
        !acceptedTypes.mediaTypes.isEmpty &&
        UIImagePickerController.isSourceTypeAvailable(.camera) &&
        !resolvedAvailableMediaTypes(for: .camera).isEmpty
    }
    
    // MARK: - Media Picker
    
    func presentMediaPicker(sourceType: UIImagePickerController.SourceType) {
        if sourceType == .photoLibrary,
           #available(iOS 14.0, *) {
            presentPhotoLibraryPicker()
            return
        }
        
        presentLegacyMediaPicker(sourceType: sourceType)
    }
    
    @available(iOS 14.0, *)
    private func presentPhotoLibraryPicker() {
        guard let presenter = UIApplication.shared.topViewController(),
              let filter = photoLibraryFilter else {
            finish(with: nil)
            return
        }
        
        var configuration = PHPickerConfiguration()
        configuration.filter = filter
        configuration.preferredAssetRepresentationMode = .current
        configuration.selectionLimit = mode == .multiple ? 0 : 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        picker.presentationController?.delegate = self
        presenter.present(picker, animated: true)
        presentedController = picker
    }
    
    private func presentLegacyMediaPicker(sourceType: UIImagePickerController.SourceType) {
        guard let presenter = UIApplication.shared.topViewController() else {
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
        picker.presentationController?.delegate = self
        configureCameraIfNeeded(picker, mediaTypes: mediaTypes, sourceType: sourceType)
        
        presenter.present(picker, animated: true)
        presentedController = picker
    }
    
    private func configureCameraIfNeeded(
        _ picker: UIImagePickerController,
        mediaTypes: [String],
        sourceType: UIImagePickerController.SourceType
    ) {
        guard sourceType == .camera else {
            return
        }
        
        picker.modalPresentationStyle = .fullScreen
        picker.isModalInPresentation = true
        if let preferredDevice = resolvedCameraDevice(),
           UIImagePickerController.isCameraDeviceAvailable(preferredDevice) {
            picker.cameraDevice = preferredDevice
        }
        if mediaTypes == [kUTTypeMovie as String] {
            picker.cameraCaptureMode = .video
        }
    }
    
    func resolvedAvailableMediaTypes(
        for sourceType: UIImagePickerController.SourceType
    ) -> [String] {
        let availableTypes = Set(UIImagePickerController.availableMediaTypes(for: sourceType) ?? [])
        return acceptedTypes.mediaTypes.filter { availableTypes.contains($0) }
    }
    
    private func resolvedCameraDevice() -> UIImagePickerController.CameraDevice? {
        switch capture {
        case .user:
            return .front
        case .environment:
            return .rear
        case .any, .none:
            return nil
        }
    }
    
    // MARK: - Result Preparation
    
    func prepareMediaResult(
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
    
    @available(iOS 14.0, *)
    func preparePhotoLibraryResult(from results: [PHPickerResult]) async -> SelectionResult? {
        let selectedResults = mode == .multiple ? results : Array(results.prefix(1))
        guard !selectedResults.isEmpty else {
            return nil
        }
        
        do {
            try Self.prepareDirectory(stagingDirectoryURL)
        } catch {
            return nil
        }
        
        var stagedFiles: [String] = []
        for result in selectedResults {
            guard let stagedURL = await Self.stageItemProvider(
                result.itemProvider,
                acceptedMediaTypes: acceptedTypes.mediaTypes,
                in: stagingDirectoryURL
            ) else {
                continue
            }
            stagedFiles.append(stagedURL.path)
        }
        
        guard !stagedFiles.isEmpty else {
            return nil
        }
        
        return SelectionResult(files: stagedFiles, filesInWebKitDirectory: [])
    }
}
