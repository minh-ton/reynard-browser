//
//  ImagePreviewViewController.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

final class ImagePreviewViewController: UIViewController {
    private enum UX {
        static let previewResizeAnimationDuration: TimeInterval = 0.22
    }
    
    private let url: URL
    private var imageLoadTask: Task<Void, Never>?
    
    private let imageView = UIImageView()
    
    // MARK: - Lifecycle
    
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
        configureView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadImage()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelImageLoad()
    }
    
    // MARK: - Configuration
    
    private func configureView() {
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
    
    // MARK: - Image Loading
    
    private func loadImage() {
        imageView.image = nil
        imageLoadTask = Task { [weak self, url] in
            guard let image = await ImagePreviewLoader.image(from: url),
                  !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.applyLoadedImage(image)
            }
        }
    }
    
    private func applyLoadedImage(_ image: UIImage) {
        guard imageLoadTask?.isCancelled == false else {
            return
        }
        
        imageView.image = image
        UIView.animate(withDuration: UX.previewResizeAnimationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.preferredContentSize = image.size
            self.view.superview?.layoutIfNeeded()
        }
    }
    
    private func cancelImageLoad() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        imageView.image = nil
    }
}
