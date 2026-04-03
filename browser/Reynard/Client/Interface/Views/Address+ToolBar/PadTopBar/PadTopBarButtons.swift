//
//  TopBarButtons.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class PadTopBarButtons {
    lazy var sidebarButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "sidebar.left", action: #selector(BrowserViewController.librarySidebarTapped))
    
    lazy var backButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "chevron.backward", action: #selector(BrowserViewController.padBackTapped))
    lazy var forwardButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "chevron.forward", action: #selector(BrowserViewController.padForwardTapped))
    lazy var menuButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "ellipsis.circle", action: #selector(BrowserViewController.topBarMenuTapped))
    lazy var downloadButton = MakeButtons.makeDownloadToolbarButton(target: controller, action: #selector(BrowserViewController.topBarDownloadsTapped))
    lazy var shareButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "square.and.arrow.up", action: #selector(BrowserViewController.shareTapped))
    lazy var newTabButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "plus", action: #selector(BrowserViewController.newTabTapped))
    lazy var tabOverviewButton = MakeButtons.makeToolbarButton(controller: controller, imageName: "square.on.square", action: #selector(BrowserViewController.tabsTapped))
    
    lazy var leftStack: UIStackView = {
        downloadButton.isHidden = true
        
        let stack = UIStackView(arrangedSubviews: [sidebarButton, downloadButton, backButton, forwardButton, menuButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        return stack
    }()
    
    lazy var rightStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [shareButton, newTabButton, tabOverviewButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        return stack
    }()
    
    var leftLeadingConstraint: NSLayoutConstraint!
    var rightTrailingConstraint: NSLayoutConstraint!
    var leftWidthConstraint: NSLayoutConstraint!
    var rightWidthConstraint: NSLayoutConstraint!
    var leftHeightConstraint: NSLayoutConstraint!
    var rightHeightConstraint: NSLayoutConstraint!
    
    private unowned let controller: BrowserViewController
    
    init(controller: BrowserViewController) {
        self.controller = controller
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        SidebarToggleButtonConfiguration.configure(sidebarButton, in: splitViewController)
    }
    
    func updateLayout(isPadLayout: Bool, showsCompactPadChrome: Bool, sidebarVisible: Bool) {
        let showsSidebarButton = isPadLayout && !showsCompactPadChrome
        let showsMenuControls = !isPadLayout && !showsCompactPadChrome
        
        sidebarButton.isHidden = !showsSidebarButton || sidebarVisible
        menuButton.isHidden = !showsMenuControls
        downloadButton.isHidden = showsCompactPadChrome || !downloadButton.isShowingDownloads
    }
    
    func updateDownloadButton(summary: DownloadStoreSummary) {
        downloadButton.apply(summary: summary)
        downloadButton.isHidden = controller.usesCompactPadChromeMode || !downloadButton.isShowingDownloads
    }
}
