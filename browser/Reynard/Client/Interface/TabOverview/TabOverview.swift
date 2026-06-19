//
//  TabOverview.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol TabOverviewDataSource: AnyObject {
    var regularTabs: [Tab] { get }
    var privateTabs: [Tab] { get }
    var selectedMode: TabMode { get }
    var selectedIndex: Int { get }
    
    func selectTab(at index: Int, mode: TabMode)
    func closeTab(at index: Int, mode: TabMode)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode)
    func captureThumbnailForVisibleTab(at index: Int)
}

protocol TabOverviewDelegate: AnyObject {
    func tabOverviewDidRequestClearTabs(_ tabOverview: TabOverview)
    func tabOverviewDidRequestNewTab(_ tabOverview: TabOverview)
    func tabOverviewDidRequestDone(_ tabOverview: TabOverview)
    func tabOverviewDidRequestDismiss(_ tabOverview: TabOverview, animated: Bool)
    func tabOverviewDidRequestClearPendingTabExpansion(_ tabOverview: TabOverview)
}

protocol TabOverviewPresentationContext: AnyObject {
    var containerView: UIView { get }
    var contentView: ContentView { get }
    var browserChrome: BrowserChrome { get }
    var tabBar: TabBar { get }
    var browserLayout: BrowserLayout { get }
    
    func setSearchFocused(_ focused: Bool, animated: Bool)
    func endEditing()
    func updateLayout(animated: Bool, duration: TimeInterval)
}

final class TabOverview: UIView {
    private enum UX {
        static let tabCollectionContentInset: CGFloat = 16
        static let tabCollectionItemSpacing: CGFloat = 16
        static let bottomToolbarContainerHeight: CGFloat = 144
        static let topToolbarContainerHeight: CGFloat = 76
        static let layoutAnimationDuration: TimeInterval = 0.22
    }
    
    enum Mode: Int {
        case privateTabs = 0
        case regularTabs = 1
        
        init(tabMode: TabMode) {
            self = tabMode == .private ? .privateTabs : .regularTabs
        }
        
        var tabMode: TabMode {
            return self == .privateTabs ? .private : .regular
        }
    }
    
    enum ToolbarPosition {
        case top
        case bottom
    }
    
    weak var dataSource: TabOverviewDataSource?
    weak var delegate: TabOverviewDelegate?
    weak var presentationContext: TabOverviewPresentationContext?
    
    private(set) var toolbarPosition: ToolbarPosition = .bottom
    
    var mode: Mode {
        return collection.mode
    }
    
    var isPresented: Bool {
        return presentation.isPresented
    }
    
    var isTransitionRunning: Bool {
        return presentation.isTransitionRunning
    }
    
    var previewAspectRatio: CGFloat {
        guard let contentView = presentationContext?.contentView else {
            return 1
        }
        
        let width = max(contentView.bounds.width, 1)
        return max(contentView.bounds.height, 1) / width
    }
    
    let collection: TabOverviewCollection
    let topToolbar = TabOverviewTopToolbar()
    let bottomToolbar = TabOverviewBottomToolbar()
    private(set) lazy var presentation = TabOverviewPresentation(tabOverview: self)
    
    private var regularTabsCollectionTopToContainerConstraint: NSLayoutConstraint!
    private var regularTabsCollectionTopToToolbarConstraint: NSLayoutConstraint!
    private var regularTabsCollectionBottomToContainerConstraint: NSLayoutConstraint!
    private var regularTabsCollectionBottomToToolbarConstraint: NSLayoutConstraint!
    private var privateTabsCollectionTopToContainerConstraint: NSLayoutConstraint!
    private var privateTabsCollectionTopToToolbarConstraint: NSLayoutConstraint!
    private var privateTabsCollectionBottomToContainerConstraint: NSLayoutConstraint!
    private var privateTabsCollectionBottomToToolbarConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        collection = TabOverviewCollection(
            contentInset: UX.tabCollectionContentInset,
            itemSpacing: UX.tabCollectionItemSpacing
        )
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureActions()
        collection.configure(tabOverview: self)
        applyLayout(toolbarPosition: .bottom, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Configuration
    
    func configure(
        dataSource: TabOverviewDataSource,
        delegate: TabOverviewDelegate,
        presentationContext: TabOverviewPresentationContext
    ) {
        self.dataSource = dataSource
        self.delegate = delegate
        self.presentationContext = presentationContext
    }
    
    // MARK: - Updates
    
    func applyLayout(toolbarPosition: ToolbarPosition, animated: Bool) {
        self.toolbarPosition = toolbarPosition
        let usesBottomToolbar = toolbarPosition == .bottom
        topToolbar.isHidden = usesBottomToolbar
        bottomToolbar.isHidden = !usesBottomToolbar
        regularTabsCollectionTopToContainerConstraint.isActive = usesBottomToolbar
        regularTabsCollectionTopToToolbarConstraint.isActive = !usesBottomToolbar
        regularTabsCollectionBottomToContainerConstraint.isActive = !usesBottomToolbar
        regularTabsCollectionBottomToToolbarConstraint.isActive = usesBottomToolbar
        privateTabsCollectionTopToContainerConstraint.isActive = usesBottomToolbar
        privateTabsCollectionTopToToolbarConstraint.isActive = !usesBottomToolbar
        privateTabsCollectionBottomToContainerConstraint.isActive = !usesBottomToolbar
        privateTabsCollectionBottomToToolbarConstraint.isActive = usesBottomToolbar
        updateToolbarState()
        
        let changes = {
            self.layoutIfNeeded()
            self.collection.applyPresentationTransforms()
        }
        animated ? UIView.animate(withDuration: UX.layoutAnimationDuration, animations: changes) : changes()
    }
    
    func setActiveToolbarAlpha(_ alpha: CGFloat) {
        switch toolbarPosition {
        case .top:
            topToolbar.alpha = alpha
        case .bottom:
            bottomToolbar.alpha = alpha
        }
    }
    
    func setPresented(_ presented: Bool, animated: Bool) {
        presentation.setPresented(presented, animated: animated)
    }
    
    func setMode(_ mode: Mode, animated: Bool) {
        collection.setMode(mode, containerWidth: bounds.width, animated: animated)
        topToolbar.setMode(mode)
        bottomToolbar.setMode(mode)
        updateToolbarState()
    }
    
    func restoreMode(_ mode: Mode) {
        setMode(mode, animated: false)
        collection.refreshTabIdentitySnapshot()
    }
    
    func reloadTabs() {
        collection.reloadTabCards()
        updateToolbarState()
    }
    
    func applyPendingTabChanges() {
        collection.applyTabCollectionChanges()
        updateToolbarState()
    }
    
    func refreshTab(at index: Int, mode: TabMode) {
        collection.refreshVisibleTabCard(at: index, mode: Mode(tabMode: mode))
    }
    
    func prepareNewTabInsertion(completion: @escaping () -> Void) {
        collection.prepareInsertionPlaceholder(for: mode, completion: completion)
    }
    
    func refreshForCurrentOrientation() {
        presentation.refreshForCurrentOrientation()
    }
    
    func invalidateCollectionLayouts() {
        collection.invalidateCardLayouts()
    }
    
    // MARK: - Presentation Access
    
    func currentCollectionView() -> UICollectionView {
        collection.collectionView(for: mode)
    }
    
    func itemIndex(forTabAt index: Int, mode: Mode? = nil) -> Int? {
        collection.itemIndex(forTabAt: index, mode: mode)
    }
    
    func prepareDismissSelection(to index: Int, mode: TabMode, previewImage: UIImage?) {
        presentation.prepareDismissSelection(to: index, mode: mode, previewImage: previewImage)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGray6
        alpha = 0
        isHidden = true
    }
    
    private func configureHierarchy() {
        addSubview(collection.privateTabsCollectionView)
        addSubview(collection.regularTabsCollectionView)
        addSubview(bottomToolbar)
        addSubview(topToolbar)
    }
    
    private func configureConstraints() {
        regularTabsCollectionTopToContainerConstraint = collection.regularTabsCollectionView.topAnchor.constraint(equalTo: topAnchor)
        regularTabsCollectionTopToToolbarConstraint = collection.regularTabsCollectionView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor)
        regularTabsCollectionBottomToContainerConstraint = collection.regularTabsCollectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        regularTabsCollectionBottomToToolbarConstraint = collection.regularTabsCollectionView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor)
        privateTabsCollectionTopToContainerConstraint = collection.privateTabsCollectionView.topAnchor.constraint(equalTo: topAnchor)
        privateTabsCollectionTopToToolbarConstraint = collection.privateTabsCollectionView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor)
        privateTabsCollectionBottomToContainerConstraint = collection.privateTabsCollectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        privateTabsCollectionBottomToToolbarConstraint = collection.privateTabsCollectionView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor)
        
        NSLayoutConstraint.activate([
            collection.regularTabsCollectionView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            collection.regularTabsCollectionView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            collection.privateTabsCollectionView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            collection.privateTabsCollectionView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            
            topToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topToolbar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topToolbar.heightAnchor.constraint(equalToConstant: UX.topToolbarContainerHeight),
            
            bottomToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: UX.bottomToolbarContainerHeight),
        ])
        
    }
    
    private func configureActions() {
        topToolbar.onTabModeChange = { [weak self] mode in self?.handleTabModeChange(mode) }
        bottomToolbar.onTabModeChange = { [weak self] mode in self?.handleTabModeChange(mode) }
        topToolbar.onClearTabs = { [weak self] in self?.requestClearTabs() }
        bottomToolbar.onClearTabs = { [weak self] in self?.requestClearTabs() }
        topToolbar.onAddTab = { [weak self] in self?.requestNewTab() }
        bottomToolbar.onAddTab = { [weak self] in self?.requestNewTab() }
        topToolbar.onDone = { [weak self] in self?.requestDone() }
        bottomToolbar.onDone = { [weak self] in self?.requestDone() }
    }
    
    // MARK: - Actions
    
    private func requestClearTabs() {
        delegate?.tabOverviewDidRequestClearTabs(self)
    }
    
    private func handleTabModeChange(_ mode: Mode) {
        setMode(mode, animated: true)
        TabManagementStore.shared.persistLastOverview(mode == .privateTabs ? .private : .regular)
    }
    
    private func requestNewTab() {
        delegate?.tabOverviewDidRequestNewTab(self)
    }
    
    private func requestDone() {
        delegate?.tabOverviewDidRequestDone(self)
    }
    
    private func updateToolbarState() {
        let regularCount = dataSource?.regularTabs.count ?? 0
        let visibleCount = mode == .privateTabs
        ? dataSource?.privateTabs.count ?? 0
        : regularCount
        topToolbar.apply(tabCount: regularCount, hasVisibleTab: visibleCount > 0)
        bottomToolbar.apply(tabCount: regularCount, hasVisibleTab: visibleCount > 0)
    }
}
