//
//  TabOverviewCollection.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewCollectionLayout: UICollectionViewFlowLayout {
    private var insertedIndexPaths = Set<IndexPath>()
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        insertedIndexPaths = Set(updateItems.compactMap { item in
            item.updateAction == .insert ? item.indexPathAfterUpdate : nil
        })
    }
    
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes ??
        layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if insertedIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
            attributes?.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths.removeAll()
    }
}

final class TabOverviewCollection {
    typealias TabCollectionHandler = UICollectionViewDataSource & UICollectionViewDelegate & UICollectionViewDelegateFlowLayout
    static let fakeInsertionReuseIdentifier = "TabOverviewFakeInsertionCell"
    
    enum Mode: Int {
        case privateTabs = 0
        case regularTabs = 1
    }
    
    lazy var tabsCollection: UICollectionView = {
        makeCollectionView()
    }()
    
    lazy var privateTabsCollection: UICollectionView = {
        let view = makeCollectionView()
        view.transform = CGAffineTransform(translationX: -1, y: 0)
        view.isUserInteractionEnabled = false
        view.backgroundView = privateModeIntroView
        return view
    }()
    
    private lazy var privateModeIntroView: UIView = {
        let container = UIView()
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isUserInteractionEnabled = false
        
        let imageView = UIImageView(image: UIImage(named: "private.mode.icon")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Private Browsing"
        titleLabel.textAlignment = .center
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Reynard won't remember any of your browsing history or cookies. However, downloads and new bookmarks will be saved."
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        
        let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        container.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -48),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
        
        return container
    }()
    
    private(set) var mode: Mode = .regularTabs
    private var verticalOffset: CGFloat = 0
    
    var allCollectionViews: [UICollectionView] {
        [privateTabsCollection, tabsCollection]
    }
    
    private func makeCollectionView() -> UICollectionView {
        let layout = TabOverviewCollectionLayout()
        layout.minimumLineSpacing = overviewSpacing
        layout.minimumInteritemSpacing = overviewSpacing
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.contentInset = UIEdgeInsets(top: overviewInset, left: overviewInset, bottom: overviewInset, right: overviewInset)
        view.dataSource = tabCollectionHandler
        view.delegate = tabCollectionHandler
        let reorderGesture = UILongPressGestureRecognizer(
            target: tabCollectionHandler as AnyObject,
            action: #selector(BrowserViewController.handleOverviewReorderLongPress(_:))
        )
        reorderGesture.minimumPressDuration = 0.35
        reorderGesture.delegate = tabCollectionHandler as? UIGestureRecognizerDelegate
        view.addGestureRecognizer(reorderGesture)
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Self.fakeInsertionReuseIdentifier)
        view.register(TabOverviewCard.self, forCellWithReuseIdentifier: TabOverviewCard.reuseIdentifier)
        return view
    }
    
    var topPhoneConstraint: NSLayoutConstraint!
    var bottomPhoneConstraint: NSLayoutConstraint!
    var topPadConstraint: NSLayoutConstraint!
    var bottomPadConstraint: NSLayoutConstraint!
    var privateTopPhoneConstraint: NSLayoutConstraint!
    var privateBottomPhoneConstraint: NSLayoutConstraint!
    var privateTopPadConstraint: NSLayoutConstraint!
    var privateBottomPadConstraint: NSLayoutConstraint!
    
    private let overviewInset: CGFloat
    private let overviewSpacing: CGFloat
    private let tabCollectionHandler: TabCollectionHandler
    
    init(overviewInset: CGFloat, overviewSpacing: CGFloat, tabCollectionHandler: TabCollectionHandler) {
        self.overviewInset = overviewInset
        self.overviewSpacing = overviewSpacing
        self.tabCollectionHandler = tabCollectionHandler
    }
    
    func applyVerticalOffset(_ offset: CGFloat) {
        verticalOffset = offset
        applyTransforms()
    }
    
    func setMode(_ mode: Mode, in containerView: UIView, animated: Bool) {
        let modeChanged = mode != self.mode
        self.mode = mode
        privateTabsCollection.isUserInteractionEnabled = mode == .privateTabs
        tabsCollection.isUserInteractionEnabled = mode == .regularTabs
        containerView.layoutIfNeeded()
        
        let animations = {
            self.applyTransforms()
        }
        
        if animated && modeChanged {
            UIView.animate(withDuration: 0.65, delay: 0, usingSpringWithDamping: 0.95, initialSpringVelocity: 1, options: [.curveEaseInOut], animations: animations)
        } else {
            animations()
        }
    }
    
    func applyTransforms() {
        guard let containerView = tabsCollection.superview,
              tabsCollection.bounds.width > 1,
              privateTabsCollection.bounds.width > 1 else {
            privateTabsCollection.transform = CGAffineTransform(translationX: -1, y: verticalOffset)
            tabsCollection.transform = CGAffineTransform(translationX: 0, y: verticalOffset)
            return
        }
        
        let privateLeading = privateTabsCollection.center.x - (privateTabsCollection.bounds.width / 2)
        let regularLeading = tabsCollection.center.x - (tabsCollection.bounds.width / 2)
        let privateOffscreenLeft = -(privateLeading + privateTabsCollection.bounds.width)
        let regularOffscreenRight = containerView.bounds.width - regularLeading
        
        switch mode {
        case .privateTabs:
            privateTabsCollection.transform = CGAffineTransform(translationX: 0, y: verticalOffset)
            tabsCollection.transform = CGAffineTransform(translationX: regularOffscreenRight, y: verticalOffset)
        case .regularTabs:
            privateTabsCollection.transform = CGAffineTransform(translationX: privateOffscreenLeft, y: verticalOffset)
            tabsCollection.transform = CGAffineTransform(translationX: 0, y: verticalOffset)
        }
    }
}
