//
//  AddressBarGestures.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class AddressBarGestures: NSObject {
    // MARK: - UX

    private enum UX {
        static let addressBarAutomaticNewTabTransitionDuration: TimeInterval = 0.2
        static let addressBarTabSwitchTransitionDuration: TimeInterval = 0.24
        static let addressBarTabSwitchCancellationDuration: TimeInterval = 0.22
        static let addressBarAutomaticNewTabTranslationRatio: CGFloat = 0.34
        static let addressBarPreviewOutsidePadding: CGFloat = 24
        static let addressBarPreviewCornerRadius: CGFloat = 16
        static let addressBarPreviewShadowOpacity: Float = 0.12
        static let addressBarPreviewShadowRadius: CGFloat = 10
        static let addressBarPreviewShadowOffset = CGSize(width: 0, height: 2)
        static let addressBarPreviewHorizontalInset: CGFloat = 12
        static let addressBarPreviewButtonSpacing: CGFloat = 8
        static let addressBarPreviewButtonSize: CGFloat = 18
        static let addressBarPreviewFontSize: CGFloat = 17
        static let addressBarEdgeSwipeTranslationDamping: CGFloat = 0.18
        static let addressBarTabSwitchCompletionDistanceRatio: CGFloat = 0.28
        static let addressBarTabSwitchVelocityThreshold: CGFloat = 700
        static let addressBarPanDirectionDetectionThreshold: CGFloat = 6
    }

    private enum SearchPanMode {
        case undecided
        case horizontalTabs
        case blocked
    }
    
    private unowned let addressBar: AddressBar
    private unowned let controller: BrowserViewController
    private let swipeHaptic = UIImpactFeedbackGenerator(style: .rigid)
    
    private var searchPanMode: SearchPanMode = .blocked

    // Preview views are disposable snapshots; the actual tab selection changes only after completion.
    private var horizontalDirection = 0
    private var horizontalTargetIndex: Int?
    private var horizontalTargetContentView: UIView?
    private var horizontalTargetBarView: UIView?

    // MARK: - Lifecycle
    
    init(addressBar: AddressBar, controller: BrowserViewController) {
        self.addressBar = addressBar
        self.controller = controller
    }

    // MARK: - Configuration
    
    func configure() {
        let phonePan = UIPanGestureRecognizer(target: self, action: #selector(handleSearchPan(_:)))
        phonePan.maximumNumberOfTouches = 1
        phonePan.cancelsTouchesInView = false
        phonePan.delegate = self
        
        let phoneSwipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSearchSwipeUp(_:)))
        phoneSwipeUp.direction = .up
        phoneSwipeUp.numberOfTouchesRequired = 1
        phoneSwipeUp.cancelsTouchesInView = false
        phoneSwipeUp.delegate = self
        
        // Give the explicit overview swipe priority before interpreting movement as a tab switch.
        phonePan.require(toFail: phoneSwipeUp)
        
        addressBar.addGestureRecognizer(phoneSwipeUp)
        addressBar.addGestureRecognizer(phonePan)
    }

    // MARK: - Transition Lifecycle
    
    func resetHorizontalTransition() {
        // Every exit path funnels through here to avoid leaving transformed chrome or orphan previews.
        controller.contentView.setTransitionTransform(.identity)
        addressBar.transform = .identity
        
        horizontalTargetContentView?.removeFromSuperview()
        horizontalTargetBarView?.removeFromSuperview()
        
        horizontalTargetContentView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
    }

    func animateAutomaticNewTabTransition(completion: @escaping () -> Void) {
        guard controller.browserLayout.browserChromeMode == .phone,
              !controller.tabOverview.isPresented,
              !controller.tabOverview.isTransitionRunning else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        let width = controller.contentView.bounds.width
        guard width > 1 else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        searchPanMode = .blocked
        resetHorizontalTransition()

        UIView.animate(withDuration: UX.addressBarAutomaticNewTabTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(translationX: -width * UX.addressBarAutomaticNewTabTranslationRatio, y: 0)
            self.controller.contentView.setTransitionTransform(transform)
            self.addressBar.transform = transform
        } completion: { _ in
            self.resetHorizontalTransition()
            completion()
        }
    }

    func animateAutomaticNewTabTransition(to tab: Tab, completion: @escaping () -> Void) {
        guard controller.browserLayout.browserChromeMode == .phone,
              !controller.tabOverview.isPresented,
              !controller.tabOverview.isTransitionRunning else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        let width = controller.contentView.bounds.width
        guard width > 1 else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        searchPanMode = .blocked
        resetHorizontalTransition()
        horizontalDirection = 1
        
        let targetContent = createContentPreview(for: tab)
        targetContent.frame = controller.contentView.frame.offsetBy(dx: width, dy: 0)
        controller.view.insertSubview(targetContent, belowSubview: controller.contentView)
        horizontalTargetContentView = targetContent
        
        if let barHost = addressBar.superview {
            let targetBar = createAddressBarPreview(for: tab)
            let horizontalOffset = addressBar.bounds.width + UX.addressBarPreviewOutsidePadding
            targetBar.frame = addressBar.frame.offsetBy(dx: horizontalOffset, dy: 0)
            barHost.addSubview(targetBar)
            horizontalTargetBarView = targetBar
        }
        
        UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(translationX: -width, y: 0)
            self.controller.contentView.setTransitionTransform(transform)
            self.addressBar.transform = transform
            self.horizontalTargetContentView?.transform = transform
            self.horizontalTargetBarView?.transform = transform
        } completion: { _ in
            self.resetHorizontalTransition()
            completion()
        }
    }

    // MARK: - Previews
    
    private func createAddressBarPreview(for tab: Tab) -> UIView {
        // A lightweight replica avoids reparenting or mutating the live AddressBar during the swipe.
        let container = UIView()
        container.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        container.layer.cornerRadius = UX.addressBarPreviewCornerRadius
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = UX.addressBarPreviewShadowOpacity
        container.layer.shadowRadius = UX.addressBarPreviewShadowRadius
        container.layer.shadowOffset = UX.addressBarPreviewShadowOffset
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
        trailingButton.setImage(UIImage(systemName: tab.state.loadingState.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        trailingButton.isHidden = !tab.state.loadingState.isLoading && tab.url == nil
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UX.addressBarPreviewFontSize, weight: .regular)
        label.textAlignment = .left
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.attributedText = previewText(for: tab)
        
        container.addSubview(leadingButton)
        container.addSubview(label)
        container.addSubview(trailingButton)
        
        NSLayoutConstraint.activate([
            leadingButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UX.addressBarPreviewHorizontalInset),
            leadingButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leadingButton.widthAnchor.constraint(equalToConstant: UX.addressBarPreviewButtonSize),
            leadingButton.heightAnchor.constraint(equalToConstant: UX.addressBarPreviewButtonSize),
            
            trailingButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UX.addressBarPreviewHorizontalInset),
            trailingButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: UX.addressBarPreviewButtonSize),
            trailingButton.heightAnchor.constraint(equalToConstant: UX.addressBarPreviewButtonSize),
            
            label.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: UX.addressBarPreviewButtonSpacing),
            label.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -UX.addressBarPreviewButtonSpacing),
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
        // Thumbnails are sufficient for the transition; Gecko remains attached only to the selected tab.
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

    // MARK: - Interactive Tab Switching
    
    private func updateHorizontalTabInteraction(translationX: CGFloat) {
        let direction = translationX < 0 ? 1 : -1
        
        if horizontalDirection != direction {
            // Crossing the origin invalidates the preview created for the opposite neighbor.
            resetHorizontalTransition()
            horizontalDirection = direction
        }
        
        if horizontalTargetIndex == nil {
            let candidate = controller.tabManager.selectedTabIndex + direction
            if controller.tabManager.activeTabs.indices.contains(candidate) {
                horizontalTargetIndex = candidate
                
                let targetTab = controller.tabManager.activeTabs[candidate]
                
                let targetContent = createContentPreview(for: targetTab)
                targetContent.frame = controller.contentView.frame.offsetBy(dx: CGFloat(direction) * controller.contentView.bounds.width, dy: 0)
                controller.view.insertSubview(targetContent, belowSubview: controller.contentView)
                horizontalTargetContentView = targetContent
                
                if let barHost = addressBar.superview {
                    let targetBar = createAddressBarPreview(for: targetTab)
                    let horizontalOffset = CGFloat(direction) * (addressBar.bounds.width + UX.addressBarPreviewOutsidePadding)
                    targetBar.frame = addressBar.frame.offsetBy(dx: horizontalOffset, dy: 0)
                    barHost.addSubview(targetBar)
                    horizontalTargetBarView = targetBar
                }
            }
        }
        
        if horizontalTargetIndex == nil {
            // No neighboring tab means an edge drag; damp it until new-tab threshold evaluation.
            let damped = translationX * UX.addressBarEdgeSwipeTranslationDamping
            controller.contentView.setTransitionTransform(CGAffineTransform(translationX: damped, y: 0))
            addressBar.transform = CGAffineTransform(translationX: damped, y: 0)
            return
        }
        
        let transform = CGAffineTransform(translationX: translationX, y: 0)
        controller.contentView.setTransitionTransform(transform)
        addressBar.transform = transform
        horizontalTargetContentView?.transform = transform
        horizontalTargetBarView?.transform = transform
    }
    
    private func finishHorizontalTabInteraction(translationX: CGFloat, velocityX: CGFloat) {
        let width = controller.contentView.bounds.width
        let shouldSwitch = horizontalTargetIndex != nil && (abs(translationX) > width * UX.addressBarTabSwitchCompletionDistanceRatio || abs(velocityX) > UX.addressBarTabSwitchVelocityThreshold)
        // A leftward edge swipe from the final phone tab is the only gesture that creates a tab.
        let shouldCreateNewTab = controller.browserLayout.browserChromeMode == .phone
        && horizontalTargetIndex == nil
        && controller.tabManager.selectedTabIndex == controller.tabManager.activeTabs.count - 1
        && horizontalDirection == 1
        && (abs(translationX) > width * UX.addressBarTabSwitchCompletionDistanceRatio || velocityX < -UX.addressBarTabSwitchVelocityThreshold)
        
        if shouldSwitch, let targetIndex = horizontalTargetIndex {
            let finalTranslation = CGFloat(-horizontalDirection) * width
            UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
                let transform = CGAffineTransform(translationX: finalTranslation, y: 0)
                self.controller.contentView.setTransitionTransform(transform)
                self.addressBar.transform = transform
                self.horizontalTargetContentView?.transform = transform
                self.horizontalTargetBarView?.transform = transform
            } completion: { _ in
                self.resetHorizontalTransition()
                self.controller.tabManager.selectTab(at: targetIndex, mode: self.controller.tabManager.selectedTabMode)
            }
        } else if shouldCreateNewTab {
            swipeHaptic.impactOccurred()
            animateAutomaticNewTabTransition {
                let createdIndex = self.controller.tabManager.createTab(selecting: true)
                self.controller.tabBar.setPendingExpansion(at: createdIndex)
            }
        } else {
            UIView.animate(withDuration: UX.addressBarTabSwitchCancellationDuration, delay: 0, options: [.curveEaseOut]) {
                self.controller.contentView.setTransitionTransform(.identity)
                self.addressBar.transform = .identity
                self.horizontalTargetContentView?.transform = .identity
                self.horizontalTargetBarView?.transform = .identity
            } completion: { _ in
                self.resetHorizontalTransition()
            }
        }
    }

    // MARK: - Gesture Actions
    
    @objc private func handleSearchPan(_ recognizer: UIPanGestureRecognizer) {
        if controller.browserLayout.browserChromeMode != .phone {
            resetHorizontalTransition()
            searchPanMode = .blocked
            return
        }
        
        if controller.searchOverlayCoordinator.isFocused && recognizer.state == .began {
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
                // Wait for deliberate motion before locking the recognizer to horizontal or blocked.
                if abs(translation.x) < UX.addressBarPanDirectionDetectionThreshold,
                   abs(translation.y) < UX.addressBarPanDirectionDetectionThreshold {
                    return
                }
                
                if abs(translation.x) > abs(translation.y) {
                    let newMode: SearchPanMode = (!controller.tabOverview.isPresented && !controller.searchOverlayCoordinator.isFocused) ? .horizontalTabs : .blocked
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
              controller.browserLayout.browserChromeMode == .phone,
              !controller.searchOverlayCoordinator.isFocused,
              !controller.tabOverview.isPresented,
              !controller.tabOverview.isTransitionRunning else {
            return
        }
        
        controller.setTabOverviewVisible(true, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddressBarGestures: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIButton)
    }
}
