//
//  BookmarkSymbolPickerViewController.swift
//  Reynard
//

import UIKit

private final class BookmarkSymbolCell: UICollectionViewCell {
    static let reuseIdentifier = "BookmarkSymbolCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.48),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.48),
        ])
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(symbolName: String, color: UIColor, isSelected: Bool) {
        imageView.image = UIImage(systemName: symbolName)
        imageView.tintColor = color
        backgroundColor = isSelected ? .tertiarySystemFill : .secondarySystemBackground
        accessibilityLabel = symbolName.replacingOccurrences(of: ".", with: " ")
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

final class BookmarkSymbolPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private static let symbols = [
        "star.fill", "heart.fill", "house.fill", "bookmark.fill", "book.fill", "globe",
        "folder.fill", "bolt.fill", "flame.fill", "leaf.fill", "pawprint.fill", "gamecontroller.fill",
        "music.note", "film.fill", "cart.fill", "bag.fill", "briefcase.fill", "graduationcap.fill",
        "fork.knife", "cup.and.saucer.fill", "airplane", "car.fill", "bicycle", "figure.walk",
        "camera.fill", "photo.fill", "paintbrush.fill", "wrench.and.screwdriver.fill", "gearshape.fill",
    ]

    private let completion: (BookmarkCustomIcon) -> Void
    private var selectedSymbol = symbols[0]
    private var selectedColor = UIColor.systemBlue

    private let previewView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var colorButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let title = NSLocalizedString("Choose Color", comment: "")
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.image = UIImage(systemName: "paintpalette.fill")
            configuration.imagePadding = 8
            button.configuration = configuration
        } else {
            button.setTitle(title, for: .normal)
        }
        button.addTarget(self, action: #selector(chooseColor), for: .touchUpInside)
        return button
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.dataSource = self
        view.delegate = self
        view.register(BookmarkSymbolCell.self, forCellWithReuseIdentifier: BookmarkSymbolCell.reuseIdentifier)
        return view
    }()

    init(
        initialIcon: BookmarkCustomIcon?,
        completion: @escaping (BookmarkCustomIcon) -> Void
    ) {
        self.completion = completion
        if case let .symbol(name, color) = initialIcon {
            selectedSymbol = Self.symbols.contains(name) ? name : Self.symbols[0]
            selectedColor = UIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Symbol & Color", comment: "")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )

        view.addSubview(previewView)
        view.addSubview(colorButton)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            previewView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 64),
            previewView.heightAnchor.constraint(equalToConstant: 64),
            colorButton.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 12),
            colorButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.topAnchor.constraint(equalTo: colorButton.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updatePreview()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.symbols.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: BookmarkSymbolCell.reuseIdentifier,
            for: indexPath
        ) as? BookmarkSymbolCell else {
            return UICollectionViewCell()
        }
        let symbolName = Self.symbols[indexPath.item]
        cell.configure(symbolName: symbolName, color: selectedColor, isSelected: symbolName == selectedSymbol)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedSymbol = Self.symbols[indexPath.item]
        updatePreview()
        collectionView.reloadData()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let columns: CGFloat = 5
        let totalSpacing: CGFloat = 12 * (columns - 1)
        let side = floor((collectionView.bounds.width - totalSpacing) / columns)
        return CGSize(width: side, height: side)
    }

    @objc private func chooseColor() {
        if #available(iOS 14.0, *) {
            let picker = UIColorPickerViewController()
            picker.selectedColor = selectedColor
            picker.supportsAlpha = false
            picker.delegate = self
            present(picker, animated: true)
        } else {
            let colors: [(String, UIColor)] = [
                (NSLocalizedString("Blue", comment: ""), .systemBlue),
                (NSLocalizedString("Red", comment: ""), .systemRed),
                (NSLocalizedString("Orange", comment: ""), .systemOrange),
                (NSLocalizedString("Green", comment: ""), .systemGreen),
                (NSLocalizedString("Purple", comment: ""), .systemPurple),
            ]
            let alert = UIAlertController(title: NSLocalizedString("Choose Color", comment: ""), message: nil, preferredStyle: .actionSheet)
            colors.forEach { name, color in
                alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                    self?.applySelectedColor(color)
                })
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.popoverPresentationController?.sourceView = colorButton
            alert.popoverPresentationController?.sourceRect = colorButton.bounds
            present(alert, animated: true)
        }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func done() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard selectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              let color = BookmarkIconColor.normalizedSRGB(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
              ) else {
            return
        }
        completion(
            .symbol(
                name: selectedSymbol,
                color: color
            )
        )
        dismiss(animated: true)
    }

    private func updatePreview() {
        previewView.image = UIImage(systemName: selectedSymbol)
        previewView.tintColor = selectedColor
    }

    private func applySelectedColor(_ color: UIColor) {
        selectedColor = color
        updatePreview()
        collectionView.reloadData()
    }
}

@available(iOS 14.0, *)
extension BookmarkSymbolPickerViewController: UIColorPickerViewControllerDelegate {
    nonisolated func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        MainActor.assumeIsolated {
            applySelectedColor(viewController.selectedColor)
        }
    }

    nonisolated func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        MainActor.assumeIsolated {
            applySelectedColor(viewController.selectedColor)
        }
    }
}
