//
//  TabBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol TabBarDataSource: AnyObject {
    var tabs: [Tab] { get }
    var selectedTabID: UUID? { get }
    var selectedMode: TabMode { get }
    
    func selectTab(at index: Int, mode: TabMode)
    func closeTab(at index: Int, mode: TabMode)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode)
}

final class TabBar: UIView {
    private enum UX {
        static let tabBarHeight: CGFloat = 36
        static let tabBarBottomPadding: CGFloat = 2
    }
    
    enum Visibility: Equatable {
        case hidden
        case layoutReserved
        case visible
    }
    
    enum ReorderState: Equatable {
        case idle
        case pending
        case active
    }
    
    struct CellLayout {
        let width: CGFloat
        let mode: TabBarCell.LayoutMode
    }
    
    weak var dataSource: TabBarDataSource?
    
    private(set) var visibility: Visibility = .hidden
    private(set) var reorderState: ReorderState = .idle
    private var pendingExpandedTabID: UUID?
    private var displayedTabIDs: [UUID]?
    
    var pendingExpandedTabIndex: Int? {
        guard let pendingExpandedTabID else {
            return nil
        }
        return dataSource?.tabs.firstIndex { $0.id == pendingExpandedTabID }
    }
    
    var standardHeight: CGFloat {
        return UX.tabBarHeight + UX.tabBarBottomPadding
    }
    
    private let tabCollection = TabBarCollection()
    private lazy var presentation = TabBarPresentation(tabBar: self)
    
    private var heightConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureTabCollection()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self && tabCollection.transform.ty < 0 ? nil : hitView
    }
    
    // MARK: - Layout
    
    func setVisibility(_ visibility: Visibility, animated: Bool) {
        presentation.setVisibility(visibility, animated: animated)
    }
    
    func setCollapseOffset(_ offset: CGFloat) {
        alpha = 1 - offset / max(bounds.height, 1)
        tabCollection.transform = CGAffineTransform(translationX: 0, y: -offset)
    }
    
    func invalidateLayout() {
        tabCollection.invalidateLayout()
    }
    
    func updateLayout() {
        clearInvalidPendingExpansion()
        tabCollection.updateLayout()
    }
    
    func cellLayout(at index: Int) -> CellLayout {
        let tabs = dataSource?.tabs ?? []
        let horizontalInset = tabCollection.adjustedContentInset.left + tabCollection.adjustedContentInset.right
        let containerWidth = tabCollection.bounds.width > 1 ? tabCollection.bounds.width : bounds.width
        let availableWidth = max(0, containerWidth - horizontalInset)
        let layoutTabCount = max(1, tabs.count)
        let equalTabWidth = floor(availableWidth / CGFloat(layoutTabCount))
        
        if equalTabWidth >= TabBarCell.expandedMinimumWidth {
            return CellLayout(width: equalTabWidth, mode: .expanded)
        }
        
        let usesExpandedLayout = isExpandedTab(at: index, in: tabs)
        let expandedTabCount = max(1, tabs.indices.reduce(0) { count, tabIndex in
            count + (isExpandedTab(at: tabIndex, in: tabs) ? 1 : 0)
        })
        let unselectedTabCount = max(0, layoutTabCount - expandedTabCount)
        
        let unselectedTabWidth: CGFloat
        let usesFaviconOnlyLayout: Bool
        if unselectedTabCount == 0 {
            unselectedTabWidth = availableWidth
            usesFaviconOnlyLayout = false
        } else {
            let availableUnselectedWidth = availableWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedTabCount))
            unselectedTabWidth = floor(availableUnselectedWidth / CGFloat(unselectedTabCount))
            usesFaviconOnlyLayout = unselectedTabWidth <= TabBarCell.collapsedMinimumWidth
        }
        
        if usesExpandedLayout {
            return CellLayout(width: TabBarCell.expandedMinimumWidth, mode: .expanded)
        }
        
        if usesFaviconOnlyLayout {
            return CellLayout(width: TabBarCell.collapsedMinimumWidth, mode: .faviconOnly)
        }
        
        return CellLayout(width: max(0, unselectedTabWidth), mode: .expanded)
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        clearInvalidPendingExpansion()
        let tabs = dataSource?.tabs ?? []
        let (insertedIndices, deletedIndices) = changedTabIndices(in: tabs)
        if !insertedIndices.isEmpty && deletedIndices.isEmpty {
            tabCollection.updateTabs(inserting: insertedIndices)
        } else if insertedIndices.isEmpty && !deletedIndices.isEmpty {
            tabCollection.updateTabs(deleting: deletedIndices)
        } else {
            tabCollection.reloadTabs()
        }
        displayedTabIDs = tabs.map { $0.id }
    }
    
    func reloadTab(at index: Int) {
        tabCollection.reloadTab(at: index)
    }
    
    func setPendingExpansion(at index: Int?) {
        pendingExpandedTabID = index.flatMap { dataSource?.tabs[safe: $0]?.id }
        if index != nil {
            tabCollection.reloadTabs()
        }
    }
    
    func isTabSelected(at index: Int) -> Bool {
        guard let tabs = dataSource?.tabs,
              tabs.indices.contains(index) else {
            return false
        }
        
        return isTabSelected(id: tabs[index].id)
    }
    
    func isTabSelected(id: UUID) -> Bool {
        guard let tabs = dataSource?.tabs else {
            return false
        }
        
        let selectedTabID = pendingExpandedTabID.flatMap { pendingTabID in
            tabs.first { $0.id == pendingTabID }?.id
        }
        ?? dataSource?.selectedTabID
        return id == selectedTabID
    }
    
    func setPresentationAlpha(_ alpha: CGFloat) {
        presentation.setAlpha(alpha)
    }
    
    private func changedTabIndices(in tabs: [Tab]) -> (inserted: [Int], deleted: [Int]) {
        guard let displayedTabIDs,
              !displayedTabIDs.isEmpty,
              displayedTabIDs.count != tabs.count else {
            return ([], [])
        }
        
        let currentTabIDs = tabs.map { $0.id }
        let displayedTabIDSet = Set(displayedTabIDs)
        let currentTabIDSet = Set(currentTabIDs)
        if displayedTabIDs.count < currentTabIDs.count {
            guard displayedTabIDSet.isSubset(of: currentTabIDSet) else {
                return ([], [])
            }
            return (currentTabIDs.indices.filter { !displayedTabIDSet.contains(currentTabIDs[$0]) }, [])
        }
        
        guard currentTabIDSet.isSubset(of: displayedTabIDSet) else {
            return ([], [])
        }
        return ([], displayedTabIDs.indices.filter { !currentTabIDSet.contains(displayedTabIDs[$0]) })
    }
    
    // MARK: - Collection Coordination
    
    func updateReorderState(_ state: ReorderState) {
        reorderState = state
    }
    
    func requestSelectTab(at index: Int) {
        guard let dataSource else {
            return
        }
        dataSource.selectTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestCloseTab(at index: Int) {
        pendingExpandedTabID = nil
        guard let dataSource else {
            return
        }
        dataSource.closeTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestMoveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard let dataSource else {
            return
        }
        dataSource.moveTab(from: sourceIndex, to: destinationIndex, mode: dataSource.selectedMode)
        displayedTabIDs = dataSource.tabs.map { $0.id }
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = true
        isHidden = true
    }
    
    private func configureHierarchy() {
        addSubview(tabCollection)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        let tabCollectionHeightConstraint = tabCollection.heightAnchor.constraint(equalToConstant: UX.tabBarHeight)
        NSLayoutConstraint.activate([
            tabCollection.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabCollection.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabCollection.topAnchor.constraint(equalTo: topAnchor),
            tabCollectionHeightConstraint,
            heightConstraint,
        ])
    }
    
    private func configureTabCollection() {
        tabCollection.attach(to: self)
    }
    
    // MARK: - Layout State
    
    private func clearInvalidPendingExpansion() {
        guard pendingExpandedTabID != nil else {
            return
        }
        
        if pendingExpandedTabIndex == nil {
            pendingExpandedTabID = nil
        }
    }
    
    private func isExpandedTab(at index: Int, in tabs: [Tab]) -> Bool {
        guard let tab = displayedTab(at: index, in: tabs) else {
            return false
        }
        return isTabSelected(id: tab.id)
    }
    
    private func displayedTab(at index: Int, in tabs: [Tab]) -> Tab? {
        guard tabs.indices.contains(index) else {
            return nil
        }
        
        guard let sourceIndex = tabCollection.dragSourceIndex,
              let targetIndex = tabCollection.dragDestinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return tabs[index]
        }
        
        var reorderedTabs = tabs
        let movedTab = reorderedTabs.remove(at: sourceIndex)
        reorderedTabs.insert(movedTab, at: targetIndex)
        return reorderedTabs[index]
    }
    
    // MARK: - Presentation Coordination
    
    func applyVisibility(_ visibility: Visibility) {
        self.visibility = visibility
        let isHidden = visibility == .hidden
        heightConstraint.constant = isHidden ? 0 : standardHeight
    }
}
