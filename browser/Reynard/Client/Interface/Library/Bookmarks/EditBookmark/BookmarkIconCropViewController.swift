//
//  BookmarkIconCropViewController.swift
//  Reynard
//

import UIKit

final class BookmarkIconCropViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let completion: (Data) -> Void
    private var configuredViewportSize: CGSize = .zero

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.bouncesZoom = true
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        view.layer.borderWidth = 1
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        return view
    }()

    init(image: UIImage, completion: @escaping (Data) -> Void) {
        self.image = image
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Crop Icon", comment: "")
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Use", comment: "Use the cropped bookmark icon"),
            style: .done,
            target: self,
            action: #selector(useCrop)
        )

        scrollView.delegate = self
        imageView.image = image
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scrollView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            scrollView.heightAnchor.constraint(equalTo: scrollView.widthAnchor),
            scrollView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scrollView.bounds.size.width > 0,
              scrollView.bounds.size != configuredViewportSize else {
            return
        }
        configuredViewportSize = scrollView.bounds.size
        configureZoom()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func useCrop() {
        let visibleRect = scrollView.convert(scrollView.bounds, to: imageView)
        let sourceSize = imageView.bounds.size
        let visibleSide = min(visibleRect.width, visibleRect.height)
        let availableX = max(0, sourceSize.width - visibleSide)
        let availableY = max(0, sourceSize.height - visibleSide)
        let crop = BookmarkIconNormalizedCrop(
            x: availableX > 0 ? Double(visibleRect.minX / availableX) : 0,
            y: availableY > 0 ? Double(visibleRect.minY / availableY) : 0,
            side: Double(visibleSide / min(sourceSize.width, sourceSize.height))
        )
        do {
            let data = try BookmarkIconImageProcessor.normalizedPNG(from: image, crop: crop)
            completion(data)
            dismiss(animated: true)
        } catch {
            presentProcessingError()
        }
    }

    private func configureZoom() {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize
        let minimumScale = max(
            scrollView.bounds.width / imageSize.width,
            scrollView.bounds.height / imageSize.height
        )
        scrollView.minimumZoomScale = minimumScale
        scrollView.maximumZoomScale = max(minimumScale * 6, minimumScale)
        scrollView.zoomScale = minimumScale
        scrollView.contentOffset = CGPoint(
            x: max(0, (imageSize.width * minimumScale - scrollView.bounds.width) / 2),
            y: max(0, (imageSize.height * minimumScale - scrollView.bounds.height) / 2)
        )
    }

    private func presentProcessingError() {
        let alert = UIAlertController(
            title: NSLocalizedString("Unable to Use Image", comment: ""),
            message: NSLocalizedString("Choose a valid image and try again.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
