//
//  TabOverviewBarButtons.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabOverviewBarButtons {
    lazy var clearButton: UIButton = {
        MakeButtons.makeTabOverviewBarButton(controller: controller, imageName: "trash", isFilled: false, action: #selector(BrowserViewController.clearAllTabsTapped))
    }()
    
    lazy var addButton: UIButton = {
        MakeButtons.makeTabOverviewBarButton(controller: controller, imageName: "plus", isFilled: false, action: #selector(BrowserViewController.newTabTapped))
    }()
    
    lazy var doneButton: UIButton = {
        MakeButtons.makeTabOverviewBarButton(controller: controller, imageName: "checkmark", isFilled: true, action: #selector(BrowserViewController.doneTapped))
    }()
    
    lazy var clearBarButtonItem: UIBarButtonItem = {
        MakeButtons.makeTabOverviewBarButtonItem(controller: controller, systemItem: .trash, action: #selector(BrowserViewController.clearAllTabsTapped))
    }()
    
    lazy var addBarButtonItem: UIBarButtonItem = {
        MakeButtons.makeTabOverviewBarButtonItem(controller: controller, systemItem: .add, action: #selector(BrowserViewController.newTabTapped))
    }()
    
    lazy var doneBarButtonItem: UIBarButtonItem = {
        MakeButtons.makeTabOverviewBarButtonItem(controller: controller, systemItem: .done, action: #selector(BrowserViewController.doneTapped))
    }()
    
    lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [clearButton, addButton, doneButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()
    
    lazy var actionToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.items = [
            clearBarButtonItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            addBarButtonItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            doneBarButtonItem,
        ]
        return toolbar
    }()
    
    lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Private", "0 Tabs"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = TabOverviewCollection.Mode.regularTabs.rawValue
        control.addTarget(controller, action: #selector(BrowserViewController.tabOverviewModeChanged(_:)), for: .valueChanged)
        return control
    }()
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var centerYConstraint: NSLayoutConstraint?
    private var centerYFromBottomConstraint: NSLayoutConstraint?
    private var centerYFromTopConstraint: NSLayoutConstraint?
    private var modeLeadingConstraint: NSLayoutConstraint?
    private var modeTrailingConstraint: NSLayoutConstraint?
    private var modeHeightConstraint: NSLayoutConstraint?
    private var modeWidthConstraint: NSLayoutConstraint?
    private var modeCenterYConstraint: NSLayoutConstraint?
    private var modeTrailingToButtonsConstraint: NSLayoutConstraint?
    private var modeBottomConstraint: NSLayoutConstraint?
    private var modeTopConstraint: NSLayoutConstraint?
    
    private unowned let controller: BrowserViewController
    
    init(controller: BrowserViewController) {
        self.controller = controller
        
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 42),
            clearButton.heightAnchor.constraint(equalTo: clearButton.widthAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 42),
            addButton.heightAnchor.constraint(equalTo: addButton.widthAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 42),
            doneButton.heightAnchor.constraint(equalTo: doneButton.widthAnchor),
        ])
    }
    
    func attach(to hostView: UIView, verticalPhoneMode: Bool) {
        let controlsView = MakeButtons.hasLiquidGlass ? actionToolbar : actionStack
        
        NSLayoutConstraint.deactivate([
            leadingConstraint,
            trailingConstraint,
            widthConstraint,
            centerYConstraint,
            centerYFromBottomConstraint,
            centerYFromTopConstraint,
            modeLeadingConstraint,
            modeTrailingConstraint,
            modeHeightConstraint,
            modeWidthConstraint,
            modeCenterYConstraint,
            modeTrailingToButtonsConstraint,
            modeBottomConstraint,
            modeTopConstraint,
        ].compactMap { $0 })
        
        actionStack.removeFromSuperview()
        actionToolbar.removeFromSuperview()
        modeControl.removeFromSuperview()
        
        leadingConstraint = nil
        trailingConstraint = nil
        widthConstraint = nil
        centerYConstraint = nil
        centerYFromBottomConstraint = nil
        centerYFromTopConstraint = nil
        modeLeadingConstraint = nil
        modeTrailingConstraint = nil
        modeHeightConstraint = nil
        modeWidthConstraint = nil
        modeCenterYConstraint = nil
        modeTrailingToButtonsConstraint = nil
        modeBottomConstraint = nil
        modeTopConstraint = nil
        
        hostView.addSubview(controlsView)
        hostView.addSubview(modeControl)
        
        modeLeadingConstraint = modeControl.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor, constant: 32)
        modeHeightConstraint = modeControl.heightAnchor.constraint(equalToConstant: 32)
        
        if verticalPhoneMode {
            actionStack.distribution = .equalSpacing
            actionStack.spacing = 0
            leadingConstraint = controlsView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor, constant: 32)
            trailingConstraint = controlsView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor, constant: -32)
            modeTrailingConstraint = modeControl.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor, constant: -32)
            centerYFromBottomConstraint = controlsView.centerYAnchor.constraint(equalTo: hostView.bottomAnchor, constant: -54)
            modeBottomConstraint = modeControl.bottomAnchor.constraint(equalTo: controlsView.topAnchor, constant: -18)
        } else {
            actionStack.distribution = .fill
            actionStack.spacing = 10
            trailingConstraint = controlsView.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor, constant: -32)
            widthConstraint = controlsView.widthAnchor.constraint(equalToConstant: 146)
            centerYFromTopConstraint = controlsView.centerYAnchor.constraint(equalTo: hostView.topAnchor, constant: 38)
            modeCenterYConstraint = modeControl.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor)
            modeWidthConstraint = modeControl.widthAnchor.constraint(equalToConstant: 375)
            modeWidthConstraint?.priority = .defaultHigh
            modeTrailingToButtonsConstraint = modeControl.trailingAnchor.constraint(lessThanOrEqualTo: controlsView.leadingAnchor, constant: -16)
        }
        
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            widthConstraint,
            centerYConstraint,
            centerYFromBottomConstraint,
            centerYFromTopConstraint,
            modeLeadingConstraint,
            modeTrailingConstraint,
            modeHeightConstraint,
            modeWidthConstraint,
            modeCenterYConstraint,
            modeTrailingToButtonsConstraint,
            modeTopConstraint,
            modeBottomConstraint,
        ].compactMap { $0 })
    }
    
    func setTabCount(_ tabCount: Int) {
        modeControl.setTitle("\(tabCount)" + (tabCount == 1 ? " Tab" : " Tabs"), forSegmentAt: TabOverviewCollection.Mode.regularTabs.rawValue)
        
        // Unrelated, too lazy to make a separate func
        let hasVisibleTab: Bool
        switch controller.browserUI.tabOverviewCollection.mode {
        case .privateTabs:
            hasVisibleTab = !controller.tabManager.privateTabs.isEmpty
        case .regularTabs:
            hasVisibleTab = !controller.tabManager.regularTabs.isEmpty
        }
        
        doneButton.isEnabled = hasVisibleTab
        doneButton.alpha = hasVisibleTab ? 1 : 0.35
        doneBarButtonItem.isEnabled = hasVisibleTab
    }
}
