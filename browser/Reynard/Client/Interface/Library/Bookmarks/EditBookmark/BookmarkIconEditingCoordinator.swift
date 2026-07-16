//
//  BookmarkIconEditingCoordinator.swift
//  Reynard
//

@preconcurrency import PhotosUI
import UniformTypeIdentifiers
import UIKit

final class BookmarkIconEditingCoordinator: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private weak var presenter: UIViewController?
    private let completion: (BookmarkCustomIcon) -> Void

    init(presenter: UIViewController, completion: @escaping (BookmarkCustomIcon) -> Void) {
        self.presenter = presenter
        self.completion = completion
    }

    func choosePhoto() {
        if #available(iOS 14.0, *) {
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            presenter?.present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image"]
            picker.delegate = self
            presenter?.present(picker, animated: true)
        }
    }

    func chooseFile() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .import)
        }
        picker.allowsMultipleSelection = false
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    func chooseSymbol(initialIcon: BookmarkCustomIcon?) {
        let picker = BookmarkSymbolPickerViewController(
            initialIcon: initialIcon,
            completion: completion
        )
        let navigationController = UINavigationController(rootViewController: picker)
        navigationController.modalPresentationStyle = .pageSheet
        presenter?.present(navigationController, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        processImageFile(at: url)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let cgImage = image.cgImage,
              BookmarkIconImagePolicy.acceptsPixelDimensions(width: cgImage.width, height: cgImage.height) else {
            presentError(for: BookmarkIconImageProcessingError.inputTooLarge)
            return
        }
        presentCrop(for: image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func processImageFile(at url: URL) {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  BookmarkIconImagePolicy.acceptsInputByteCount(fileSize) else {
                throw BookmarkIconImageProcessingError.inputTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let image = try BookmarkIconImageProcessor.validatedImage(from: data)
            DispatchQueue.main.async { [weak self] in
                self?.presentCrop(for: image)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.presentError(for: error)
            }
        }
    }

    private func presentCrop(for image: UIImage) {
        let crop = BookmarkIconCropViewController(image: image) { [completion] data in
            completion(.raster(data))
        }
        let navigationController = UINavigationController(rootViewController: crop)
        navigationController.modalPresentationStyle = .fullScreen
        presenter?.present(navigationController, animated: true)
    }

    private func presentError(for error: Error) {
        let message: String
        if case BookmarkIconImageProcessingError.inputTooLarge = error {
            message = NSLocalizedString("Choose a smaller image and try again.", comment: "")
        } else {
            message = NSLocalizedString("Choose a valid image and try again.", comment: "")
        }
        let alert = UIAlertController(
            title: NSLocalizedString("Unable to Use Image", comment: ""),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        presenter?.present(alert, animated: true)
    }
}

@available(iOS 14.0, *)
extension BookmarkIconEditingCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            guard let self, let url else {
                return
            }
            self.processImageFile(at: url)
        }
    }
}
