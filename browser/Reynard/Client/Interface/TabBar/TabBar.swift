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
    private(set) var pendingExpandedTabIndex: Int?
    
    var standardHeight: CGFloat {
        return UX.tabBarHeight
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
    
    // MARK: - Layout
    
    func setVisibility(_ visibility: Visibility, animated: Bool) {
        presentation.setVisibility(visibility, animated: animated)
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
        tabCollection.reloadTabs()
    }
    
    func reloadTab(at index: Int) {
        tabCollection.reloadTab(at: index)
    }
    
    func setPendingExpansion(at index: Int?) {
        pendingExpandedTabIndex = index
        if index != nil {
            tabCollection.reloadTabs()
        }
    }
    
    func isTabSelected(at index: Int) -> Bool {
        guard let tabs = dataSource?.tabs,
              tabs.indices.contains(index) else {
            return false
        }
        
        let selectedTabID = pendingExpandedTabIndex.flatMap { tabs[safe: $0]?.id }
        ?? dataSource?.selectedTabID
        return tabs[index].id == selectedTabID
    }
    
    func setPresentationAlpha(_ alpha: CGFloat) {
        presentation.setAlpha(alpha)
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
        pendingExpandedTabIndex = nil
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
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGray6
        isHidden = true
    }
    
    private func configureHierarchy() {
        addSubview(tabCollection)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            tabCollection.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabCollection.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabCollection.topAnchor.constraint(equalTo: topAnchor),
            tabCollection.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }
    
    private func configureTabCollection() {
        tabCollection.attach(to: self)
    }
    
    // MARK: - Layout State
    
    private func clearInvalidPendingExpansion() {
        guard let pendingExpandedTabIndex else {
            return
        }
        
        if dataSource?.tabs.indices.contains(pendingExpandedTabIndex) != true {
            self.pendingExpandedTabIndex = nil
        }
    }
    
    private func isExpandedTab(at index: Int, in tabs: [Tab]) -> Bool {
        guard let tab = displayedTab(at: index, in: tabs) else {
            return false
        }
        
        let selectedTabID = pendingExpandedTabIndex.flatMap { tabs[safe: $0]?.id }
        ?? dataSource?.selectedTabID
        return tab.id == selectedTabID
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
        heightConstraint.constant = visibility == .hidden ? 0 : UX.tabBarHeight
    }
}
