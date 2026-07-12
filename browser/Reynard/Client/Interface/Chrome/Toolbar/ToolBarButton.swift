//
//  ToolbarButton.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class ToolbarButton: UIButton {
    private enum UX {
        static let toolbarButtonCornerRadius: CGFloat = 10
        static let downloadIconSize: CGFloat = 24
        static let downloadIconVerticalOffset: CGFloat = -1
        static let downloadProgressTrackWidth: CGFloat = 18
        static let downloadProgressTrackHeight: CGFloat = 2.5
        static let downloadProgressTrackBottomInset: CGFloat = 1
        static let downloadProgressTrackCornerRadius: CGFloat = 1.25
        static let standardButtonSideLength: CGFloat = 30
        static let standardSymbolPointSize: CGFloat = 20
        static let newTabSymbolPointSize: CGFloat = 20
        static let downloadSymbolPointSize: CGFloat = 17
    }
    
    enum ButtonType {
        case back
        case forward
        case share
        case library
        case bookmarks
        case history
        case settings
        case tabOverview
        case download
        case newTab
        case closeTab
        case reload
        case pageZoom
        case sidebar
    }
    
    private lazy var downloadIconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .label
        view.clipsToBounds = false
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressTrackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = UX.downloadProgressTrackCornerRadius
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .label
        view.layer.cornerRadius = UX.downloadProgressTrackCornerRadius
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressFillWidthConstraint = downloadProgressFillView.widthAnchor.constraint(equalToConstant: 0)
    
    private let toolbarButtonType: ButtonType
    private(set) var isShowingDownloads = false
    
    // MARK: - Lifecycle
    
    init(buttonType: ButtonType, target: AnyObject, action: Selector) {
        toolbarButtonType = buttonType
        super.init(frame: .zero)
        configureAppearance()
        configureImage()
        configureTarget(target, action: action)
        configureDownloadViewsIfNeeded()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UX.standardButtonSideLength, height: UX.standardButtonSideLength)
    }
    
    // MARK: - Updates
    
    func applyDownloadSummary(_ summary: DownloadStoreSummary) {
        guard toolbarButtonType == .download else {
            return
        }
        
        let shouldShowDownloads = summary.showsToolbarButton
        if shouldShowDownloads != isShowingDownloads {
            isShowingDownloads = shouldShowDownloads
            if shouldShowDownloads {
                playDownloadBounceAnimation()
            }
        }
        
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.downloadSymbolPointSize, weight: .regular)
        downloadIconView.image = UIImage(named: "reynard.arrow.down.circle", in: .main, with: configuration)
        
        let progress = min(max(CGFloat(summary.aggregateProgress), 0), 1)
        let showsProgress = summary.activeCount > 0
        downloadProgressTrackView.isHidden = !showsProgress
        downloadProgressFillView.isHidden = !showsProgress
        downloadProgressFillWidthConstraint.constant = UX.downloadProgressTrackWidth * progress
        accessibilityLabel = NSLocalizedString("Downloads", comment: "")
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = .label
        layer.cornerRadius = UX.toolbarButtonCornerRadius
        layer.cornerCurve = .continuous
        accessibilityLabel = buttonTitle
    }
    
    private func configureImage() {
        guard toolbarButtonType != .download else {
            return
        }
        setImage(UIImage(named: symbolName), for: .normal)
        let pointSize = toolbarButtonType == .newTab
        ? UX.newTabSymbolPointSize
        : UX.standardSymbolPointSize
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular),
            forImageIn: .normal
        )
    }
    
    private func configureTarget(_ target: AnyObject, action: Selector) {
        addTarget(self, action: #selector(playTapHaptic), for: .touchUpInside)
        addTarget(target, action: action, for: .touchUpInside)
    }

    @objc private func playTapHaptic() {
        guard Prefs.AppearanceSettings.toolbarButtonHapticsEnabled else {
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func configureDownloadViewsIfNeeded() {
        guard toolbarButtonType == .download else {
            return
        }
        
        layer.masksToBounds = false
        clipsToBounds = false
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.downloadSymbolPointSize, weight: .regular)
        downloadIconView.image = UIImage(named: "reynard.arrow.down.circle", in: .main, with: configuration)
        downloadIconView.isHidden = false
        addSubview(downloadIconView)
        addSubview(downloadProgressTrackView)
        addSubview(downloadProgressFillView)
        
        NSLayoutConstraint.activate([
            downloadIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadIconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: UX.downloadIconVerticalOffset),
            downloadIconView.widthAnchor.constraint(equalToConstant: UX.downloadIconSize),
            downloadIconView.heightAnchor.constraint(equalToConstant: UX.downloadIconSize),
            
            downloadProgressTrackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadProgressTrackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UX.downloadProgressTrackBottomInset),
            downloadProgressTrackView.widthAnchor.constraint(equalToConstant: UX.downloadProgressTrackWidth),
            downloadProgressTrackView.heightAnchor.constraint(equalToConstant: UX.downloadProgressTrackHeight),
            
            downloadProgressFillView.leadingAnchor.constraint(equalTo: downloadProgressTrackView.leadingAnchor),
            downloadProgressFillView.centerYAnchor.constraint(equalTo: downloadProgressTrackView.centerYAnchor),
            downloadProgressFillView.heightAnchor.constraint(equalTo: downloadProgressTrackView.heightAnchor),
            downloadProgressFillWidthConstraint,
        ])
    }
    
    // MARK: - Button
    
    private var symbolName: String {
        switch toolbarButtonType {
        case .back: return "reynard.chevron.backward"
        case .forward: return "reynard.chevron.forward"
        case .share: return "reynard.square.and.arrow.up"
        case .library: return "reynard.ellipsis.circle"
        case .bookmarks: return "reynard.book"
        case .history: return "reynard.clock"
        case .settings: return "reynard.gearshape"
        case .tabOverview: return "reynard.square.on.square"
        case .download: return "reynard.arrow.down.circle"
        case .newTab: return "reynard.plus"
        case .closeTab: return "reynard.xmark"
        case .reload: return "reynard.arrow.clockwise"
        case .pageZoom: return "reynard.textformat.size"
        case .sidebar: return "reynard.sidebar.left"
        }
    }

    private var buttonTitle: String {
        switch toolbarButtonType {
        case .back: return "Back"
        case .forward: return "Forward"
        case .share: return "Share"
        case .library: return "Library"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .settings: return "Settings"
        case .tabOverview: return "Tabs"
        case .download: return "Downloads"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .reload: return "Reload"
        case .pageZoom: return "Page Zoom"
        case .sidebar: return "Sidebar"
        }
    }
    
    private func playDownloadBounceAnimation() {
        if #available(iOS 17.0, *) {
            downloadIconView.addSymbolEffect(.bounce)
        }
    }
}
