//
//  AddressBarGestures.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol AddressBarGestureDelegate: AnyObject {
    var transitionContainerView: UIView { get }
    var transitionContentView: ContentView { get }
    var chromeMode: BrowserChromeMode { get }
    var isSearchFocused: Bool { get }
    var isTabOverviewPresented: Bool { get }
    var isTabOverviewTransitionRunning: Bool { get }
    var selectedTabIndex: Int { get }
    var selectedTabMode: TabMode { get }
    var activeTabs: [Tab] { get }
    
    func selectTabFromGesture(at index: Int, mode: TabMode)
    func createTabForSwipe() -> Int
    func setPendingTabExpansion(at index: Int?)
    func presentTabOverviewFromGesture(animated: Bool)
}

final class AddressBarGestures: NSObject {
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
    private weak var delegate: AddressBarGestureDelegate?
    private var searchPanMode: SearchPanMode = .blocked
    
    private var horizontalDirection = 0
    private var horizontalTargetIndex: Int?
    private var horizontalTargetContentView: UIView?
    private var horizontalTargetBarView: UIView?
    
    init(addressBar: AddressBar, delegate: AddressBarGestureDelegate) {
        self.addressBar = addressBar
        self.delegate = delegate
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
        
        phonePan.require(toFail: phoneSwipeUp)
        
        addressBar.addGestureRecognizer(phoneSwipeUp)
        addressBar.addGestureRecognizer(phonePan)
    }
    
    // MARK: - Transition Lifecycle
    
    func resetHorizontalTransition() {
        delegate?.transitionContentView.setTransitionTransform(.identity)
        addressBar.transform = .identity
        
        horizontalTargetContentView?.removeFromSuperview()
        horizontalTargetBarView?.removeFromSuperview()
        
        horizontalTargetContentView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
    }
    
    func animateAutomaticNewTabTransition(completion: @escaping () -> Void) {
        guard let delegate,
              delegate.chromeMode == .phone,
              !delegate.isTabOverviewPresented,
              !delegate.isTabOverviewTransitionRunning else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        guard width > 1 else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        searchPanMode = .blocked
        resetHorizontalTransition()
        
        UIView.animate(withDuration: UX.addressBarAutomaticNewTabTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(
                translationX: -width * UX.addressBarAutomaticNewTabTranslationRatio,
                y: 0
            )
            delegate.transitionContentView.setTransitionTransform(transform)
            self.addressBar.transform = transform
        } completion: { _ in
            self.resetHorizontalTransition()
            completion()
        }
    }
    
    func animateAutomaticNewTabTransition(to tab: Tab, completion: @escaping () -> Void) {
        guard let delegate,
              delegate.chromeMode == .phone,
              !delegate.isTabOverviewPresented,
              !delegate.isTabOverviewTransitionRunning else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        guard width > 1 else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        
        searchPanMode = .blocked
        resetHorizontalTransition()
        horizontalDirection = 1
        
        let targetContent = createContentPreview(for: tab)
        targetContent.frame = delegate.transitionContentView.frame.offsetBy(dx: width, dy: 0)
        delegate.transitionContainerView.insertSubview(targetContent, belowSubview: delegate.transitionContentView)
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
            delegate.transitionContentView.setTransitionTransform(transform)
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
        leadingButton.setImage(UIImage(named: tab.url != nil ? "reynard.list.bullet.below.rectangle" : "reynard.magnifyingglass"), for: .normal)
        
        let trailingButton = AddressBarButton(type: .system)
        trailingButton.translatesAutoresizingMaskIntoConstraints = false
        trailingButton.tintColor = .label
        trailingButton.isUserInteractionEnabled = false
        trailingButton.setImage(UIImage(named: tab.state.loadingState.isLoading ? "reynard.xmark" : "reynard.arrow.clockwise"), for: .normal)
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
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let direction = translationX < 0 ? 1 : -1
        
        if horizontalDirection != direction {
            resetHorizontalTransition()
            horizontalDirection = direction
        }
        
        if horizontalTargetIndex == nil {
            let candidate = delegate.selectedTabIndex + direction
            if delegate.activeTabs.indices.contains(candidate) {
                horizontalTargetIndex = candidate
                
                let targetTab = delegate.activeTabs[candidate]
                
                let targetContent = createContentPreview(for: targetTab)
                targetContent.frame = delegate.transitionContentView.frame.offsetBy(dx: CGFloat(direction) * delegate.transitionContentView.bounds.width, dy: 0)
                delegate.transitionContainerView.insertSubview(targetContent, belowSubview: delegate.transitionContentView)
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
            let damped = translationX * UX.addressBarEdgeSwipeTranslationDamping
            delegate.transitionContentView.setTransitionTransform(CGAffineTransform(translationX: damped, y: 0))
            addressBar.transform = CGAffineTransform(translationX: damped, y: 0)
            return
        }
        
        let transform = CGAffineTransform(translationX: translationX, y: 0)
        delegate.transitionContentView.setTransitionTransform(transform)
        addressBar.transform = transform
        horizontalTargetContentView?.transform = transform
        horizontalTargetBarView?.transform = transform
    }
    
    private func finishHorizontalTabInteraction(translationX: CGFloat, velocityX: CGFloat) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let shouldSwitch = horizontalTargetIndex != nil && (abs(translationX) > width * UX.addressBarTabSwitchCompletionDistanceRatio || abs(velocityX) > UX.addressBarTabSwitchVelocityThreshold)
        let shouldCreateNewTab = delegate.chromeMode == .phone
        && horizontalTargetIndex == nil
        && delegate.selectedTabIndex == delegate.activeTabs.count - 1
        && horizontalDirection == 1
        && (abs(translationX) > width * UX.addressBarTabSwitchCompletionDistanceRatio || velocityX < -UX.addressBarTabSwitchVelocityThreshold)
        
        if shouldSwitch, let targetIndex = horizontalTargetIndex {
            let finalTranslation = CGFloat(-horizontalDirection) * width
            UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
                let transform = CGAffineTransform(translationX: finalTranslation, y: 0)
                delegate.transitionContentView.setTransitionTransform(transform)
                self.addressBar.transform = transform
                self.horizontalTargetContentView?.transform = transform
                self.horizontalTargetBarView?.transform = transform
            } completion: { _ in
                self.resetHorizontalTransition()
                delegate.selectTabFromGesture(at: targetIndex, mode: delegate.selectedTabMode)
            }
        } else if shouldCreateNewTab {
            Haptics.rigid()
            animateAutomaticNewTabTransition {
                let createdIndex = delegate.createTabForSwipe()
                delegate.setPendingTabExpansion(at: createdIndex)
            }
        } else {
            UIView.animate(withDuration: UX.addressBarTabSwitchCancellationDuration, delay: 0, options: [.curveEaseOut]) {
                delegate.transitionContentView.setTransitionTransform(.identity)
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
        guard let delegate else {
            resetHorizontalTransition()
            searchPanMode = .blocked
            return
        }
        
        if delegate.chromeMode != .phone {
            resetHorizontalTransition()
            searchPanMode = .blocked
            return
        }
        
        if delegate.isSearchFocused && recognizer.state == .began {
            return
        }
        
        let translation = recognizer.translation(in: delegate.transitionContainerView)
        let velocity = recognizer.velocity(in: delegate.transitionContainerView)
        
        switch recognizer.state {
        case .began:
            searchPanMode = .undecided
            resetHorizontalTransition()
            Haptics.prepareRigid()
            
        case .changed:
            if searchPanMode == .undecided {
                if abs(translation.x) < UX.addressBarPanDirectionDetectionThreshold,
                   abs(translation.y) < UX.addressBarPanDirectionDetectionThreshold {
                    return
                }
                
                if abs(translation.x) > abs(translation.y) {
                    let newMode: SearchPanMode = (!delegate.isTabOverviewPresented && !delegate.isSearchFocused) ? .horizontalTabs : .blocked
                    searchPanMode = newMode
                    if newMode == .horizontalTabs {
                        Haptics.rigid()
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
              let delegate,
              delegate.chromeMode == .phone,
              !delegate.isSearchFocused,
              !delegate.isTabOverviewPresented,
              !delegate.isTabOverviewTransitionRunning else {
            return
        }
        
        delegate.presentTabOverviewFromGesture(animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddressBarGestures: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is UIButton)
    }
}
