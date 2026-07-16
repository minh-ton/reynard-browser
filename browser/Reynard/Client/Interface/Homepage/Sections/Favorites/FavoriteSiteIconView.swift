//
//  FavoriteSiteIconView.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

import UIKit

final class FavoriteSiteIconView: UIView {
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .secondaryLabel
        return view
    }()
    
    private var representedBookmarkGUID: String?
    private var iconTask: Task<Void, Never>?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(bookmark: BookmarkSnapshot) {
        representedBookmarkGUID = bookmark.guid
        iconTask?.cancel()
        let cachedIcon = BookmarkIconProvider.shared.cachedIcon(for: bookmark)
        applyIcon(cachedIcon.image, tintColor: cachedIcon.tintColor)
        iconTask = Task { [weak self] in
            let icon = await BookmarkIconProvider.shared.icon(for: bookmark)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard self?.representedBookmarkGUID == bookmark.guid else {
                    return
                }
                self?.applyIcon(icon.image, tintColor: icon.tintColor)
            }
        }
    }
    
    func reset() {
        representedBookmarkGUID = nil
        iconTask?.cancel()
        iconTask = nil
        applyIcon(UIImage(named: "reynard.globe"), tintColor: .secondaryLabel)
    }
    
    private func configureView() {
        backgroundColor = .clear
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        reset()
    }
    
    private func applyIcon(_ image: UIImage?, tintColor: UIColor?) {
        imageView.image = image
        imageView.tintColor = tintColor
    }
}
