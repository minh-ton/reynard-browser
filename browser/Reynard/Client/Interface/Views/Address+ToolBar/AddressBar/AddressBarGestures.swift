//
//  AddressBarGestures.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class AddressBarGestures: NSObject {
    private enum SearchPanMode {
        case undecided
        case horizontalTabs
        case blocked
    }
    
    private unowned let controller: BrowserViewController
    private let swipeHaptic = UIImpactFeedbackGenerator(style: .rigid)
    
    private var searchPanMode: SearchPanMode = .blocked
    private var horizontalDirection = 0
    private var horizontalTargetIndex: Int?
    private var horizontalTargetContentView: UIView?
    private var horizontalTargetBarView: UIView?
    
    init(controller: BrowserViewController) {
        self.controller = controller
    }
    
    func configureGestures() {
        let phonePan = UIPanGestureRecognizer(target: self, action: #selector(handleSearchPan(_:)))
        phonePan.maximumNumberOfTouches = 1
        phonePan.cancelsTouchesInView = false
        phonePan.delegate = self
        
        let phoneSwipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSearchSwipeUp(_:)))
        phoneSwipeUp.direction = .up
        phoneSwipeUp.numberOfTouchesRequired = 1
        phoneSwipeUp.cancelsTouchesInView = false
        phoneSwipeUp.delegate = self
        
        phonePan.require(toFail: phoneSwipeUp)
        
        controller.browserUI.addressBar.addGestureRecognizer(phoneSwipeUp)
        controller.browserUI.addressBar.addGestureRecognizer(phonePan)
    }
    
    func resetHorizontalTransition() {
        controller.browserUI.geckoView.transform = .identity
        controller.activeAddressBar.transform = .identity
        
        horizontalTargetContentView?.removeFromSuperview()
        horizontalTargetBarView?.removeFromSuperview()
        
        horizontalTargetContentView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
    }
    
    func animateAutomaticNewTabTransition(completion: @escaping () -> Void) {
        guard !controller.usesPadChrome,
              !controller.tabOverviewPresentation.isVisible,
              !controller.tabOverviewPresentation.isTransitionRunning else {
            completion()
            return
        }
        
        let width = controller.browserUI.geckoView.bounds.width
        guard width > 1 else {
            completion()
            return
        }
        
        searchPanMode = .blocked
        resetHorizontalTransition()
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(translationX: -width * 0.34, y: 0)
            self.controller.browserUI.geckoView.transform = transform
            self.controller.activeAddressBar.transform = transform
        } completion: { _ in
            self.resetHorizontalTransition()
            completion()
        }
    }
    
    func animateAutomaticNewTabTransition(to tab: Tab, completion: @escaping () -> Void) {
        guard !controller.usesPadChrome,
              !controller.tabOverviewPresentation.isVisible,
              !controller.tabOverviewPresentation.isTransitionRunning else {
            completion()
            return
        }
        
        let width = controller.browserUI.geckoView.bounds.width
        guard width > 1 else {
            completion()
            return
        }
        
        searchPanMode = .blocked
        resetHorizontalTransition()
        horizontalDirection = 1
        
        let targetContent = createContentPreview(for: tab)
        targetContent.frame = controller.browserUI.geckoView.frame.offsetBy(dx: width, dy: 0)
        controller.view.insertSubview(targetContent, belowSubview: controller.browserUI.geckoView)
        horizontalTargetContentView = targetContent
        
        if let barHost = controller.activeAddressBar.superview {
            let targetBar = createAddressBarPreview(for: tab)
            let outsidePadding: CGFloat = 24
            let horizontalOffset = controller.activeAddressBar.bounds.width + outsidePadding
            targetBar.frame = controller.activeAddressBar.frame.offsetBy(dx: horizontalOffset, dy: 0)
            barHost.addSubview(targetBar)
            horizontalTargetBarView = targetBar
        }
        
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(translationX: -width, y: 0)
            self.controller.browserUI.geckoView.transform = transform
            self.controller.activeAddressBar.transform = transform
            self.horizontalTargetContentView?.transform = transform
            self.horizontalTargetBarView?.transform = transform
        } completion: { _ in
            self.resetHorizontalTransition()
            completion()
        }
    }
    
    private func createAddressBarPreview(for tab: Tab) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.12
        container.layer.shadowRadius = 10
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.clipsToBounds = false
        
        let leadingButton = AddressBarButton(type: .system)
        leadingButton.translatesAutoresizingMaskIntoConstraints = false
        leadingButton.tintColor = tab.url != nil ? .label : .secondaryLabel
        if #available(iOS 14.0, *) {
            leadingButton.showsMenuAsPrimaryAction = true
        }
        leadingButton.isUserInteractionEnabled = false
        leadingButton.setImage(UIImage(systemName: tab.url != nil ? "list.bullet.below.rectangle" : "magnifyingglass"), for: .normal)
        
        let trailingButton = AddressBarButton(type: .system)
        trailingButton.translatesAutoresizingMaskIntoConstraints = false
        trailingButton.tintColor = .label
        trailingButton.isUserInteractionEnabled = false
        trailingButton.setImage(UIImage(systemName: tab.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        trailingButton.isHidden = !tab.isLoading && tab.url == nil
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textAlignment = .left
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.attributedText = previewText(for: tab)
        
        container.addSubview(leadingButton)
        container.addSubview(label)
        container.addSubview(trailingButton)
        
        NSLayoutConstraint.activate([
            leadingButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            leadingButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leadingButton.widthAnchor.constraint(equalToConstant: 18),
            leadingButton.heightAnchor.constraint(equalToConstant: 18),
            
            trailingButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            trailingButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: 18),
            trailingButton.heightAnchor.constraint(equalToConstant: 18),
            
            label.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        
        return container
    }
    
    private func previewText(for tab: Tab) -> NSAttributedString {
        let trimmedTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlText = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlText.isEmpty else {
            return placeholderPreviewText()
        }
        
        guard let host = URL(string: urlText)?.host,
              !host.isEmpty else {
            return NSAttributedString(
                string: urlText,
                attributes: [.foregroundColor: UIColor.label]
            )
        }
        
        let attributedText = NSMutableAttributedString(
            string: host,
            attributes: [.foregroundColor: UIColor.label]
        )
        attributedText.append(
            NSAttributedString(
                string: " / ",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        )
        if !trimmedTitle.isEmpty {
            attributedText.append(
                NSAttributedString(
                    string: trimmedTitle,
                    attributes: [.foregroundColor: UIColor.secondaryLabel]
                )
            )
        }
        return attributedText
    }
    
    private func placeholderPreviewText() -> NSAttributedString {
        NSAttributedString(
            string: AddressBar.placeholderText,
            attributes: [.foregroundColor: UIColor.placeholderText]
        )
    }
    
    private func createContentPreview(for tab: Tab) -> UIView {
        let preview = UIView()
        preview.backgroundColor = .systemBackground
        
        if let image = tab.thumbnail {
            let imageView = UIImageView(image: image)
            imageView.frame = preview.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            preview.addSubview(imageView)
        }
        
        return preview
    }
    
    private func updateHorizontalTabInteraction(translationX: CGFloat) {
        let direction = translationX < 0 ? 1 : -1
        
        if horizontalDirection != direction {
            resetHorizontalTransition()
            horizontalDirection = direction
        }
        
        if horizontalTargetIndex == nil {
            let candidate = controller.tabManager.selectedTabIndex + direction
            if controller.tabManager.tabs.indices.contains(candidate) {
                horizontalTargetIndex = candidate
                
                let targetTab = controller.tabManager.tabs[candidate]
                
                let targetContent = createContentPreview(for: targetTab)
                targetContent.frame = controller.browserUI.geckoView.frame.offsetBy(dx: CGFloat(direction) * controller.browserUI.geckoView.bounds.width, dy: 0)
                controller.view.insertSubview(targetContent, belowSubview: controller.browserUI.geckoView)
                horizontalTargetContentView = targetContent
                
                if let barHost = controller.activeAddressBar.superview {
                    let targetBar = createAddressBarPreview(for: targetTab)
                    let outsidePadding: CGFloat = 24
                    let horizontalOffset = CGFloat(direction) * (controller.activeAddressBar.bounds.width + outsidePadding)
                    targetBar.frame = controller.activeAddressBar.frame.offsetBy(dx: horizontalOffset, dy: 0)
                    barHost.addSubview(targetBar)
                    horizontalTargetBarView = targetBar
                }
            }
        }
        
        if horizontalTargetIndex == nil {
            let damped = translationX * 0.18
            controller.browserUI.geckoView.transform = CGAffineTransform(translationX: damped, y: 0)
            controller.activeAddressBar.transform = CGAffineTransform(translationX: damped, y: 0)
            return
        }
        
        let transform = CGAffineTransform(translationX: translationX, y: 0)
        controller.browserUI.geckoView.transform = transform
        controller.activeAddressBar.transform = transform
        horizontalTargetContentView?.transform = transform
        horizontalTargetBarView?.transform = transform
    }
    
    private func finishHorizontalTabInteraction(translationX: CGFloat, velocityX: CGFloat) {
        let width = controller.browserUI.geckoView.bounds.width
        let shouldSwitch = horizontalTargetIndex != nil && (abs(translationX) > width * 0.28 || abs(velocityX) > 700)
        let shouldCreateNewTab = !controller.usesPadChrome
        && horizontalTargetIndex == nil
        && controller.tabManager.selectedTabIndex == controller.tabManager.tabs.count - 1
        && horizontalDirection == 1
        && (abs(translationX) > width * 0.28 || velocityX < -700)
        
        if shouldSwitch, let targetIndex = horizontalTargetIndex {
            let finalTranslation = CGFloat(-horizontalDirection) * width
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
                let transform = CGAffineTransform(translationX: finalTranslation, y: 0)
                self.controller.browserUI.geckoView.transform = transform
                self.controller.activeAddressBar.transform = transform
                self.horizontalTargetContentView?.transform = transform
                self.horizontalTargetBarView?.transform = transform
            } completion: { _ in
                self.resetHorizontalTransition()
                self.controller.selectTab(at: targetIndex, animated: true)
            }
        } else if shouldCreateNewTab {
            swipeHaptic.impactOccurred()
            animateAutomaticNewTabTransition {
                _ = self.controller.createTab(selecting: true)
            }
        } else {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                self.controller.browserUI.geckoView.transform = .identity
                self.controller.activeAddressBar.transform = .identity
                self.horizontalTargetContentView?.transform = .identity
                self.horizontalTargetBarView?.transform = .identity
            } completion: { _ in
                self.resetHorizontalTransition()
            }
        }
    }
    
    @objc private func handleSearchPan(_ recognizer: UIPanGestureRecognizer) {
        if controller.usesPadChrome {
            resetHorizontalTransition()
            searchPanMode = .blocked
            return
        }
        
        if controller.isSearchFocused && recognizer.state == .began {
            return
        }
        
        let translation = recognizer.translation(in: controller.view)
        let velocity = recognizer.velocity(in: controller.view)
        
        switch recognizer.state {
        case .began:
            searchPanMode = .undecided
            resetHorizontalTransition()
            swipeHaptic.prepare()
            
        case .changed:
            if searchPanMode == .undecided {
                if abs(translation.x) < 6, abs(translation.y) < 6 {
                    return
                }
                
                if abs(translation.x) > abs(translation.y) {
                    let newMode: SearchPanMode = (!controller.tabOverviewPresentation.isVisible && !controller.isSearchFocused) ? .horizontalTabs : .blocked
                    searchPanMode = newMode
                    if newMode == .horizontalTabs {
                        swipeHaptic.impactOccurred()
                    }
                } else {
                    searchPanMode = .blocked
                }
            }
            
            if searchPanMode == .horizontalTabs {
                updateHorizontalTabInteraction(translationX: translation.x)
            }
            
        case .ended, .cancelled, .failed:
            if searchPanMode == .horizontalTabs {
                finishHorizontalTabInteraction(translationX: translation.x, velocityX: velocity.x)
            } else {
                resetHorizontalTransition()
            }
            searchPanMode = .blocked
            
        default:
            break
        }
    }
    
    @objc private func handleSearchSwipeUp(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended,
              !controller.usesPadChrome,
              !controller.isSearchFocused,
              !controller.tabOverviewPresentation.isVisible,
              !controller.tabOverviewPresentation.isTransitionRunning else {
            return
        }
        
        controller.setTabOverviewVisible(true, animated: true)
    }
}

extension AddressBarGestures: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIButton)
    }
}
