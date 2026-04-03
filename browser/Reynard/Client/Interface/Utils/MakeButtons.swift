//
//  MakeButtons.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit
import Darwin
import Symbols

enum MakeButtons {
    static let hasLiquidGlass = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_UISolariumEnabled") != nil && _UISolariumEnabled()
    
    static func makeToolbarButton(target: AnyObject, imageName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: imageName), for: .normal)
        if imageName == "plus" {
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
                forImageIn: .normal
            )
        }
        button.tintColor = .label
        button.addTarget(target, action: action, for: .touchUpInside)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        return button
    }
    
    static func makeToolbarButton(controller: BrowserViewController, imageName: String, action: Selector) -> UIButton {
        makeToolbarButton(target: controller, imageName: imageName, action: action)
    }
    
    static func makeDownloadToolbarButton(target: AnyObject, action: Selector) -> DownloadToolbarButton {
        let button = DownloadToolbarButton()
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }
    
    static func makeTabOverviewBarButton(controller: BrowserViewController, imageName: String, isFilled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = isFilled ? .systemBackground : .label
        button.backgroundColor = isFilled ? .label : .quaternarySystemFill
        button.layer.borderWidth = isFilled ? 0 : 1
        button.layer.borderColor = isFilled ? UIColor.clear.cgColor : UIColor.systemFill.cgColor
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 21
        button.addTarget(controller, action: action, for: .touchUpInside)
        return button
    }
    
    static func makeTabOverviewBarButtonItem(controller: BrowserViewController, systemItem: UIBarButtonItem.SystemItem, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: systemItem, target: controller, action: action)
        item.tintColor = .label
        return item
    }
}

final class DownloadToolbarButton: UIButton {
    private let buttonSideLength: CGFloat = 40
    private let progressTrackWidth: CGFloat = 18
    
    private let iconSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    
    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .label
        view.clipsToBounds = false
        return view
    }()
    
    private let progressTrackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = 1.25
        view.isHidden = true
        return view
    }()
    
    private let progressFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .label
        view.layer.cornerRadius = 1.25
        view.isHidden = true
        return view
    }()
    
    private lazy var progressFillWidthConstraint = progressFillView.widthAnchor.constraint(equalToConstant: 0)
    
    private(set) var isShowingDownloads = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        tintColor = .label
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        clipsToBounds = false
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setImage(nil, for: .normal)
        
        addSubview(iconView)
        addSubview(progressTrackView)
        addSubview(progressFillView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            progressTrackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressTrackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            progressTrackView.widthAnchor.constraint(equalToConstant: progressTrackWidth),
            progressTrackView.heightAnchor.constraint(equalToConstant: 2.5),
            
            progressFillView.leadingAnchor.constraint(equalTo: progressTrackView.leadingAnchor),
            progressFillView.centerYAnchor.constraint(equalTo: progressTrackView.centerYAnchor),
            progressFillView.heightAnchor.constraint(equalTo: progressTrackView.heightAnchor),
            progressFillWidthConstraint,
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: buttonSideLength, height: buttonSideLength)
    }
    
    func apply(summary: DownloadStoreSummary) {
        let shouldShowDownloads = summary.showsToolbarButton
        if shouldShowDownloads != isShowingDownloads {
            isShowingDownloads = shouldShowDownloads
            if shouldShowDownloads {
                playBounceAnimation()
            }
        }
        
        iconView.image = UIImage(systemName: "arrow.down.circle", withConfiguration: iconSymbolConfiguration)
        
        let progress = min(max(CGFloat(summary.aggregateProgress), 0), 1)
        let showsProgress = summary.activeCount > 0
        progressTrackView.isHidden = !showsProgress
        progressFillView.isHidden = !showsProgress
        progressFillWidthConstraint.constant = progressTrackWidth * progress
        accessibilityLabel = "Downloads"
    }
    
    private func playBounceAnimation() {
        if #available(iOS 17.0, *) {
            iconView.addSymbolEffect(.bounce)
        }
    }
}
