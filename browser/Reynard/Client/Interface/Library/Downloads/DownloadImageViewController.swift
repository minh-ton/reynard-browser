//
//  DownloadImageViewController.swift
//  Reynard
//

import UIKit

final class DownloadImageViewController: UIViewController, UIScrollViewDelegate {
    private enum UX {
        static let maximumZoomMultiplier: CGFloat = 8
        static let horizontalLockTolerance: CGFloat = 0.5
    }

    private let fileURL: URL
    private let fileName: String
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private var image: UIImage?
    private var appliedInitialZoom = false
    private var previousViewportSize = CGSize.zero
    private var isApplyingHorizontalLock = false

    init(fileURL: URL, fileName: String) {
        self.fileURL = fileURL
        self.fileName = fileName
        super.init(nibName: nil, bundle: nil)
        title = fileName
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scrollView.bounds.size != previousViewportSize else { return }
        previousViewportSize = scrollView.bounds.size
        updateZoomScales(preservingPosition: appliedInitialZoom)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageIfNeeded()
        lockHorizontalPositionIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lockHorizontalPositionIfNeeded()
    }

    private func configureView() {
        view.backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        view.addSubview(scrollView)

        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .linear
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(imageDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.startAnimating()
        view.addSubview(loadingIndicator)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.text = "Unable to display this image."
        errorLabel.textColor = .secondaryLabel
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        view.addSubview(errorLabel)

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.backgroundColor = UIColor(white: 0.12, alpha: 0.82)
        shareButton.layer.cornerRadius = 22
        shareButton.accessibilityLabel = "Share"
        shareButton.addTarget(self, action: #selector(shareImage), for: .touchUpInside)
        shareButton.isEnabled = false
        shareButton.alpha = 0.45
        view.addSubview(shareButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            shareButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            shareButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func loadImage() {
        let fileURL = self.fileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = UIImage(contentsOfFile: fileURL.path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingIndicator.stopAnimating()
                guard let image, image.size.width > 0, image.size.height > 0 else {
                    self.errorLabel.isHidden = false
                    return
                }
                self.image = image
                self.imageView.image = image
                self.imageView.frame = CGRect(origin: .zero, size: image.size)
                self.scrollView.contentSize = image.size
                self.shareButton.isEnabled = true
                self.shareButton.alpha = 1
                self.updateZoomScales(preservingPosition: false)
            }
        }
    }

    private func updateZoomScales(preservingPosition: Bool) {
        guard let image, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else {
            return
        }

        let widthScale = scrollView.bounds.width / image.size.width
        let heightScale = scrollView.bounds.height / image.size.height
        let minimumScale = min(widthScale, heightScale)
        let previousScale = scrollView.zoomScale

        scrollView.minimumZoomScale = minimumScale
        scrollView.maximumZoomScale = max(1, minimumScale * UX.maximumZoomMultiplier)
        if !preservingPosition || !appliedInitialZoom {
            scrollView.zoomScale = minimumScale
            scrollView.contentOffset = .zero
            appliedInitialZoom = true
        } else {
            scrollView.zoomScale = min(max(previousScale, minimumScale), scrollView.maximumZoomScale)
        }
        centerImageIfNeeded()
        lockHorizontalPositionIfNeeded()
    }

    private func centerImageIfNeeded() {
        let horizontalInset = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let verticalInset = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func lockHorizontalPositionIfNeeded() {
        guard !isApplyingHorizontalLock else {
            return
        }

        let centeredOffsetX: CGFloat
        if scrollView.contentSize.width <= scrollView.bounds.width {
            centeredOffsetX = -scrollView.contentInset.left
        } else {
            centeredOffsetX = (scrollView.contentSize.width - scrollView.bounds.width) / 2
        }
        guard abs(scrollView.contentOffset.x - centeredOffsetX) > UX.horizontalLockTolerance else {
            return
        }

        isApplyingHorizontalLock = true
        scrollView.contentOffset = CGPoint(
            x: centeredOffsetX,
            y: scrollView.contentOffset.y
        )
        isApplyingHorizontalLock = false
    }

    @objc private func imageDoubleTapped(_ recognizer: UITapGestureRecognizer) {
        let minimumScale = scrollView.minimumZoomScale
        if scrollView.zoomScale > minimumScale * 1.25 {
            scrollView.setZoomScale(minimumScale, animated: true)
            return
        }

        let fitWidthScale = scrollView.bounds.width / imageView.bounds.width
        let targetScale = min(
            scrollView.maximumZoomScale,
            max(fitWidthScale, minimumScale * 3)
        )
        let point = recognizer.location(in: imageView)
        let width = scrollView.bounds.width / targetScale
        let height = scrollView.bounds.height / targetScale
        scrollView.zoom(
            to: CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            ),
            animated: true
        )
    }

    @objc private func shareImage() {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        controller.popoverPresentationController?.sourceRect = shareButton.bounds
        present(controller, animated: true)
    }
}
