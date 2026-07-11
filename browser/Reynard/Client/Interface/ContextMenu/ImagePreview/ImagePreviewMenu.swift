//
//  ImagePreviewMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

struct ImagePreviewMenu {
    static func configuration(
        for context: ContextMenuContext,
        showsPreview: Bool,
        presentingController: UIViewController,
        sourceView: UIView
    ) -> UIContextMenuConfiguration? {
        guard case .image(let url) = context.target else {
            return nil
        }
        
        let previewProvider: UIContextMenuContentPreviewProvider? = showsPreview ? {
            ImagePreviewViewController(url: url)
        } : nil
        
        return UIContextMenuConfiguration(identifier: UUID().uuidString as NSString, previewProvider: previewProvider) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "Share Image", image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                    loadImage(from: url) { image in
                        presentShareSheet(
                            image: image,
                            from: presentingController,
                            sourceView: sourceView,
                            sourcePoint: context.point
                        )
                    }
                },
                UIAction(title: "Save to Photos", image: UIImage(named: "reynard.square.and.arrow.down")) { _ in
                    loadImage(from: url) { image in
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                },
                UIAction(title: "Copy", image: UIImage(named: "reynard.document.on.document")) { _ in
                    loadImage(from: url) { image in
                        UIPasteboard.general.image = image
                    }
                },
            ])
        }
    }
    
    private static func loadImage(from url: URL, completion: @escaping @MainActor (UIImage) -> Void) {
        Task {
            guard let image = await ImagePreviewLoader.image(from: url) else {
                return
            }
            await MainActor.run {
                completion(image)
            }
        }
    }
    
    private static func presentShareSheet(
        image: UIImage,
        from controller: UIViewController,
        sourceView: UIView,
        sourcePoint: CGPoint
    ) {
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = CGRect(origin: sourcePoint, size: .zero)
        }
        controller.present(sheet, animated: true)
    }
}
