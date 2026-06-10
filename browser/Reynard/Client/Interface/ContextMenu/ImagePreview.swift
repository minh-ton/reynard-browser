//
//  ImagePreview.swift
//  Reynard
//
//  Created by Minh Ton on 16/5/26.
//

import Photos
import UIKit

enum ImagePreviewMenu {
    static func configuration(
        for context: ContextMenuContext,
        presentingController: UIViewController,
        sourceView: UIView
    ) -> UIContextMenuConfiguration? {
        guard case .image(let url) = context.target else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: UUID().uuidString as NSString) {
            ImagePreviewViewController(url: url)
        } actionProvider: { _ in
            let shareImageAction = UIAction(
                title: "Share Image",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                Task {
                    guard let image = await ImagePreviewLoader.image(from: url) else {
                        return
                    }
                    await MainActor.run {
                        presentShareSheet(image: image, from: presentingController, sourceView: sourceView)
                    }
                }
            }
            
            let saveToPhotosAction = UIAction(
                title: "Save to Photos",
                image: UIImage(systemName: "square.and.arrow.down")
            ) { _ in
                Task {
                    guard let image = await ImagePreviewLoader.image(from: url) else {
                        return
                    }
                    await MainActor.run {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                }
            }
            
            let copyAction = UIAction(
                title: "Copy",
                image: UIImage(systemName: "document.on.document")
            ) { _ in
                Task {
                    guard let image = await ImagePreviewLoader.image(from: url) else {
                        return
                    }
                    await MainActor.run {
                        UIPasteboard.general.image = image
                    }
                }
            }
            
            return UIMenu(title: "", children: [shareImageAction, saveToPhotosAction, copyAction])
        }
    }
    
    private static func presentShareSheet(image: UIImage, from controller: UIViewController, sourceView: UIView) {
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        controller.present(sheet, animated: true)
    }
}

final class ImagePreviewViewController: UIViewController {
    private let url: URL
    private let imageView = UIImageView()
    private var imageLoadTask: Task<Void, Never>?
    
    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        imageLoadTask?.cancel()
    }
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .systemBackground
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        view.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.image = nil
        imageLoadTask = Task { [weak self, url] in
            guard let image = await ImagePreviewLoader.image(from: url),
                  !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self,
                      self.imageLoadTask?.isCancelled == false else {
                    return
                }
                self.imageView.image = image
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
                    self.preferredContentSize = image.size
                    self.view.superview?.layoutIfNeeded()
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        imageLoadTask?.cancel()
        imageLoadTask = nil
        imageView.image = nil
    }
}

enum ImagePreviewLoader {
    static func image(from url: URL) async -> UIImage? {
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        
        if url.scheme?.lowercased() == "data" {
            return imageFromDataURL(url.absoluteString)
        }
        
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    private static func imageFromDataURL(_ value: String) -> UIImage? {
        guard let commaIndex = value.firstIndex(of: ",") else {
            return nil
        }
        
        let payload = value[value.index(after: commaIndex)...]
        let data: Data?
        if value[..<commaIndex].lowercased().contains(";base64") {
            data = Data(base64Encoded: String(payload))
        } else {
            data = String(payload).removingPercentEncoding?.data(using: .utf8)
        }
        
        guard let data else {
            return nil
        }
        return UIImage(data: data)
    }
}
