//
//  BrowserViewController+VerticalBar.swift
//  Reynard
//

import UIKit

/// The bottom toolbar's buttons, shown in the system vertical bar (iOS 27.1)
/// instead. On a folded foldable iPhone the status bar sits in a column at one
/// side of the window; the system shows navigation items at the top of that
/// column and toolbar items at the bottom, and draws, sizes and places them.
final class BrowserVerticalBarItems: NSObject {
    let back: UIBarButtonItem
    let forward: UIBarButtonItem
    let share: UIBarButtonItem
    let library: UIBarButtonItem
    let tabOverview: UIBarButtonItem
    
    private let onBack: () -> Void
    private let onForward: () -> Void
    private let onShare: () -> Void
    private let onLibrary: () -> Void
    private let onTabOverview: () -> Void
    
    init(
        onBack: @escaping () -> Void,
        onForward: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onLibrary: @escaping () -> Void,
        onTabOverview: @escaping () -> Void
    ) {
        self.onBack = onBack
        self.onForward = onForward
        self.onShare = onShare
        self.onLibrary = onLibrary
        self.onTabOverview = onTabOverview
        back = Self.makeItem(imageName: "reynard.chevron.backward", title: NSLocalizedString("Back", comment: ""))
        forward = Self.makeItem(imageName: "reynard.chevron.forward", title: NSLocalizedString("Forward", comment: ""))
        share = Self.makeItem(imageName: "reynard.square.and.arrow.up", title: NSLocalizedString("Share", comment: ""))
        library = Self.makeItem(imageName: "reynard.ellipsis.circle", title: NSLocalizedString("Library", comment: ""))
        tabOverview = Self.makeItem(imageName: "reynard.square.on.square", title: NSLocalizedString("Tabs", comment: ""))
        super.init()
        for (item, action) in [
            (back, #selector(backTapped)),
            (forward, #selector(forwardTapped)),
            (share, #selector(shareTapped)),
            (library, #selector(libraryTapped)),
            (tabOverview, #selector(tabOverviewTapped)),
        ] {
            item.target = self
            item.action = action
        }
        back.isEnabled = false
        forward.isEnabled = false
        share.isEnabled = false
    }
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
        share.isEnabled = canShare
    }
    
    private static func makeItem(imageName: String, title: String) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(named: imageName), style: .plain, target: nil, action: nil)
        item.title = title
        if #available(iOS 27.1, *) {
            item.axisBehavior = .verticalPreferred
        }
        return item
    }
    
    @objc private func backTapped() { onBack() }
    @objc private func forwardTapped() { onForward() }
    @objc private func shareTapped() { onShare() }
    @objc private func libraryTapped() { onLibrary() }
    @objc private func tabOverviewTapped() { onTabOverview() }
}

extension BrowserViewController {
    /// Shows the toolbar buttons, or the tab overview's buttons while it is
    /// open, in the system vertical bar while the layout uses it, and keeps the
    /// navigation bar and toolbar hidden otherwise, when the browser chrome
    /// draws its own buttons.
    func syncVerticalBarItems(animated: Bool) {
        guard let navigationController else {
            return
        }
        guard #available(iOS 27.1, *) else {
            // No system vertical bar: the browser chrome draws every button.
            navigationController.setNavigationBarHidden(true, animated: animated)
            navigationItem.leftBarButtonItems = []
            navigationItem.leftBarButtonItem = nil
            return
        }
        
        let usesVerticalBar = browserLayout.usesVerticalBar && !isShowingFullscreenMedia
        let showsTabOverviewItems = usesVerticalBar && tabOverview.isPresented
        tabOverview.setActionsShownInVerticalBar(showsTabOverviewItems)
        
        let leadingItems: [UIBarButtonItem]
        let bottomItems: [UIBarButtonItem]
        if showsTabOverviewItems {
            leadingItems = [tabOverview.verticalBarClearItem]
            bottomItems = [tabOverview.verticalBarAddItem, tabOverview.verticalBarDoneItem]
        } else if usesVerticalBar {
            leadingItems = [verticalBarItems.back, verticalBarItems.forward]
            bottomItems = [verticalBarItems.share, verticalBarItems.library, verticalBarItems.tabOverview]
        } else {
            leadingItems = []
            bottomItems = []
        }
        
        let currentLeadingItems = navigationItem.leadingItemGroups.flatMap(\.barButtonItems)
        if currentLeadingItems != leadingItems {
            navigationItem.leadingItemGroups = leadingItems.isEmpty
            ? []
            : [UIBarButtonItemGroup.fixedGroup(items: leadingItems)]
        }
        // The leading flexible space is new each time; compare the buttons only.
        let currentBottomItems = Array((self.toolbarItems ?? []).dropFirst())
        if currentBottomItems != bottomItems {
            setToolbarItems(bottomItems.isEmpty ? [] : [.flexibleSpace()] + bottomItems, animated: false)
        }
        if leadingItems.isEmpty {
            navigationItem.leftBarButtonItems = []
            navigationItem.leftBarButtonItem = nil
        }
        
        let showsBars = !bottomItems.isEmpty
        if navigationController.isNavigationBarHidden == showsBars {
            navigationController.setNavigationBarHidden(!showsBars, animated: animated)
        }
        if navigationController.isToolbarHidden == showsBars {
            navigationController.setToolbarHidden(!showsBars, animated: animated)
        }
    }
}
