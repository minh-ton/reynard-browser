//
//  BottomToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol BottomToolbarDelegate: AnyObject {
    func backButtonClicked()
    func forwardButtonClicked()
    func shareButtonClicked()
    func menuButtonClicked()
    func downloadsButtonClicked()
    func tabsButtonClicked()
}

final class BottomToolbar: UIView {
    weak var delegate: BottomToolbarDelegate?
    
    private lazy var backButton: UIButton = {
        MakeButtons.makeToolbarButton(target: self, imageName: "chevron.backward", action: #selector(backButtonClicked))
    }()
    
    private lazy var forwardButton: UIButton = {
        MakeButtons.makeToolbarButton(target: self, imageName: "chevron.forward", action: #selector(forwardButtonClicked))
    }()
    
    private lazy var shareButton: UIButton = {
        MakeButtons.makeToolbarButton(target: self, imageName: "square.and.arrow.up", action: #selector(shareButtonClicked))
    }()
    
    private lazy var menuButton: UIButton = {
        MakeButtons.makeToolbarButton(target: self, imageName: "ellipsis.circle", action: #selector(menuButtonClicked))
    }()
    
    private lazy var downloadButton = MakeButtons.makeDownloadToolbarButton(target: self, action: #selector(toolbarDownloadButtonClicked))
    
    private lazy var tabsButton: UIButton = {
        MakeButtons.makeToolbarButton(target: self, imageName: "square.on.square", action: #selector(tabsButtonClicked))
    }()
    
    private lazy var buttonsStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, shareButton, menuButton, downloadButton, tabsButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        shareButton.isEnabled = false
        downloadButton.isHidden = true
        
        addSubview(buttonsStack)
        
        NSLayoutConstraint.activate([
            buttonsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonsStack.topAnchor.constraint(equalTo: topAnchor),
            buttonsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateBackButton(canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }
    
    func updateForwardButton(canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }
    
    func updateShareButton(isEnabled: Bool) {
        shareButton.isEnabled = isEnabled
    }
    
    func updateDownloadButton(summary: DownloadStoreSummary) {
        downloadButton.apply(summary: summary)
        downloadButton.isHidden = !downloadButton.isShowingDownloads
    }
    
    @objc func backButtonClicked() {
        delegate?.backButtonClicked()
    }
    
    @objc func forwardButtonClicked() {
        delegate?.forwardButtonClicked()
    }
    
    @objc func shareButtonClicked() {
        delegate?.shareButtonClicked()
    }
    
    @objc func toolbarDownloadButtonClicked() {
        delegate?.downloadsButtonClicked()
    }
    
    @objc func menuButtonClicked() {
        delegate?.menuButtonClicked()
    }
    
    @objc func tabsButtonClicked() {
        delegate?.tabsButtonClicked()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        menuButton.setImage(hasUpdate ? UIImage(named: "ellipsis.circle.badge") : UIImage(systemName: "ellipsis.circle"), for: .normal)
    }
    
    func setButtonsHidden(_ hidden: Bool) {
        buttonsStack.alpha = hidden ? 0 : 1
        buttonsStack.isUserInteractionEnabled = !hidden
    }
}
