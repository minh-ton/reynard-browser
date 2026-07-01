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
    func addressBarGestureWillBegin()
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
    private var horizontalSourceBarView: UIView?
    private var horizontalTargetBarView: UIView?
    private var horizontalFinishingViews: [UIView] = []
    private var transitionCompletion: (() -> Void)?
    
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
        
        let gestureHost = delegate?.transitionContainerView ?? addressBar
        gestureHost.addGestureRecognizer(phoneSwipeUp)
        gestureHost.addGestureRecognizer(phonePan)
    }
    
    // MARK: - Transition Lifecycle
    
    func resetHorizontalTransition() {
        delegate?.transitionContentView.setTransitionTransform(.identity)
        delegate?.transitionContentView.setTransitionHidden(false)
        addressBar.isHidden = false
        addressBar.transform = .identity
        
        horizontalTargetContentView?.removeFromSuperview()
        horizontalSourceBarView?.removeFromSuperview()
        horizontalTargetBarView?.removeFromSuperview()
        
        horizontalTargetContentView = nil
        horizontalSourceBarView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
    }
    
    func performAfterTransition(_ completion: @escaping () -> Void) -> Bool {
        guard !horizontalFinishingViews.isEmpty else {
            return false
        }
        
        transitionCompletion = completion
        return true
    }
    
    private func clearHorizontalFinishingViews() {
        horizontalFinishingViews.forEach {
            $0.layer.removeAllAnimations()
            $0.removeFromSuperview()
        }
        horizontalFinishingViews.removeAll()
        transitionCompletion = nil
    }
    
    private func runTransitionCompletion() {
        let completion = transitionCompletion
        transitionCompletion = nil
        completion?()
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
        prepareHorizontalTarget(for: tab, direction: 1, pageWidth: width, delegate: delegate)
        
        UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(translationX: -width, y: 0)
            delegate.transitionContentView.setTransitionTransform(transform)
            self.applySourceAddressBarTransform(transform)
            self.horizontalTargetContentView?.transform = transform
            self.horizontalTargetBarView?.transform = transform
        } completion: { _ in
            completion()
            self.resetHorizontalTransition()
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
        
        if let barHost = addressBar.superview {
            ensureHorizontalSourceBar(in: barHost)
        }
        
        if horizontalTargetIndex == nil {
            let candidate = delegate.selectedTabIndex + direction
            if delegate.activeTabs.indices.contains(candidate) {
                horizontalTargetIndex = candidate
                
                let targetTab = delegate.activeTabs[candidate]
                let pageWidth = delegate.transitionContentView.bounds.width
                
                prepareHorizontalTarget(for: targetTab, direction: direction, pageWidth: pageWidth, delegate: delegate)
            }
        }
        
        if horizontalTargetIndex == nil {
            let damped = translationX * UX.addressBarEdgeSwipeTranslationDamping
            delegate.transitionContentView.setTransitionTransform(CGAffineTransform(translationX: damped, y: 0))
            applySourceAddressBarTransform(CGAffineTransform(translationX: damped, y: 0))
            return
        }
        
        let transform = CGAffineTransform(translationX: translationX, y: 0)
        delegate.transitionContentView.setTransitionTransform(transform)
        applySourceAddressBarTransform(transform)
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
            finishHorizontalTabSwitch(to: targetIndex, mode: delegate.selectedTabMode, translationX: translationX)
        } else if shouldCreateNewTab {
            Haptics.rigid()
            finishHorizontalNewTabSwipe(translationX: translationX)
        } else {
            UIView.animate(withDuration: UX.addressBarTabSwitchCancellationDuration, delay: 0, options: [.curveEaseOut]) {
                delegate.transitionContentView.setTransitionTransform(.identity)
                self.applySourceAddressBarTransform(.identity)
                self.horizontalTargetContentView?.transform = .identity
                self.horizontalTargetBarView?.transform = .identity
            } completion: { _ in
                self.resetHorizontalTransition()
            }
        }
    }
    
    private func finishHorizontalTabSwitch(to targetIndex: Int, mode: TabMode, translationX: CGFloat) {
        guard let delegate,
              let outgoingContent = delegate.transitionContentView.snapshotView(afterScreenUpdates: false) else {
            resetHorizontalTransition()
            delegate?.selectTabFromGesture(at: targetIndex, mode: mode)
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let direction = horizontalDirection
        let contentContainer = delegate.transitionContainerView
        let targetContent = horizontalTargetContentView
        let targetBar = horizontalTargetBarView
        let sourceBar = horizontalSourceBarView
        let outgoingBar = sourceBar ?? addressBar.snapshotView(afterScreenUpdates: false)
        let barHost = addressBar.superview
        let clipView = transitionClipView(for: delegate.transitionContentView, in: contentContainer)
        let finalTranslation = CGFloat(-direction) * width
        let outgoingFinalFrame = clipView.bounds.offsetBy(dx: finalTranslation, dy: 0)
        let remainingTranslation = finalTranslation - translationX
        
        outgoingContent.frame = clipView.convert(
            presentationFrame(of: delegate.transitionContentView, in: contentContainer),
            from: contentContainer
        )
        outgoingContent.isUserInteractionEnabled = false
        clipView.addSubview(outgoingContent)

        if let targetContent {
            let targetContentFrame = clipView.convert(
                presentationFrame(of: targetContent, in: contentContainer),
                from: contentContainer
            )
            targetContent.transform = .identity
            targetContent.frame = targetContentFrame
            targetContent.isUserInteractionEnabled = false
            clipView.addSubview(targetContent)
        }

        contentContainer.addSubview(clipView)
        horizontalFinishingViews.append(clipView)
        
        if let outgoingBar, let barHost {
            let outgoingBarFrame = sourceBar.map { presentationFrame(of: $0, in: barHost) } ?? presentationFrame(of: addressBar, in: barHost)
            outgoingBar.transform = .identity
            outgoingBar.frame = outgoingBarFrame
            outgoingBar.isUserInteractionEnabled = false
            barHost.addSubview(outgoingBar)
            barHost.bringSubviewToFront(outgoingBar)
            horizontalFinishingViews.append(outgoingBar)
        }
        
        if let targetBar, let barHost {
            let targetBarFrame = presentationFrame(of: targetBar, in: barHost)
            targetBar.transform = .identity
            targetBar.frame = targetBarFrame
            targetBar.isUserInteractionEnabled = false
            barHost.addSubview(targetBar)
            barHost.bringSubviewToFront(targetBar)
            horizontalFinishingViews.append(targetBar)
        }

        horizontalTargetContentView = nil
        horizontalSourceBarView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
        delegate.transitionContentView.setTransitionTransform(.identity)
        addressBar.transform = .identity
        delegate.transitionContentView.setTransitionHidden(true)
        addressBar.isHidden = true
        delegate.selectTabFromGesture(at: targetIndex, mode: mode)
        barHost?.layoutIfNeeded()
        let targetBarFinalFrame = barHost.map { restingFrame(of: addressBar, in: $0) }
        
        UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            outgoingContent.frame = outgoingFinalFrame
            targetContent?.frame = clipView.bounds
            outgoingBar?.transform = CGAffineTransform(translationX: remainingTranslation, y: 0)
            if let targetBarFinalFrame {
                targetBar?.frame = targetBarFinalFrame
            }
        } completion: { _ in
            clipView.removeFromSuperview()
            outgoingBar?.removeFromSuperview()
            targetBar?.removeFromSuperview()
            self.horizontalFinishingViews.removeAll { view in
                view === clipView || view === outgoingBar || view === targetBar
            }
            delegate.transitionContentView.setTransitionHidden(false)
            self.addressBar.isHidden = false
            self.runTransitionCompletion()
        }
    }
    
    private func finishHorizontalNewTabSwipe(translationX: CGFloat) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let currentTranslation = translationX * UX.addressBarEdgeSwipeTranslationDamping
        let mode = delegate.selectedTabMode
        let createdIndex = delegate.createTabForSwipe()
        delegate.setPendingTabExpansion(at: createdIndex)
        guard delegate.activeTabs.indices.contains(createdIndex) else {
            resetHorizontalTransition()
            return
        }

        horizontalTargetIndex = createdIndex
        horizontalDirection = 1

        let targetTab = delegate.activeTabs[createdIndex]
        prepareHorizontalTarget(for: targetTab, direction: 1, pageWidth: width, delegate: delegate)

        finishHorizontalTabSwitch(to: createdIndex, mode: mode, translationX: currentTranslation)
    }

    private func prepareHorizontalTarget(for tab: Tab, direction: Int, pageWidth: CGFloat, delegate: AddressBarGestureDelegate) {
        let targetContent = createContentPreview(for: tab)
        targetContent.frame = delegate.transitionContentView.frame.offsetBy(dx: CGFloat(direction) * pageWidth, dy: 0)
        delegate.transitionContainerView.insertSubview(targetContent, belowSubview: delegate.transitionContentView)
        horizontalTargetContentView = targetContent

        if let barHost = addressBar.superview {
            ensureHorizontalSourceBar(in: barHost)
            let targetBar = createAddressBarPreview(for: tab)
            targetBar.frame = restingFrame(of: addressBar, in: barHost).offsetBy(dx: CGFloat(direction) * pageWidth, dy: 0)
            barHost.addSubview(targetBar)
            horizontalTargetBarView = targetBar
        }
    }

    private func ensureHorizontalSourceBar(in barHost: UIView) {
        guard horizontalSourceBarView == nil else {
            return
        }
        
        guard let sourceBar = addressBar.snapshotView(afterScreenUpdates: false) else {
            return
        }
        
        sourceBar.frame = restingFrame(of: addressBar, in: barHost)
        sourceBar.isUserInteractionEnabled = false
        barHost.addSubview(sourceBar)
        barHost.bringSubviewToFront(sourceBar)
        horizontalSourceBarView = sourceBar
        addressBar.isHidden = true
    }

    private func applySourceAddressBarTransform(_ transform: CGAffineTransform) {
        if let horizontalSourceBarView {
            horizontalSourceBarView.transform = transform
        } else {
            addressBar.transform = transform
        }
    }

    private func transitionClipView(for view: UIView, in targetView: UIView) -> UIView {
        let clipView = UIView(frame: restingFrame(of: view, in: targetView))
        clipView.backgroundColor = .clear
        clipView.clipsToBounds = true
        clipView.isUserInteractionEnabled = false
        return clipView
    }
    
    private func presentationFrame(of view: UIView, in targetView: UIView) -> CGRect {
        if let presentationFrame = view.layer.presentation()?.frame,
           let superview = view.superview {
            return superview.convert(presentationFrame, to: targetView)
        }
        
        return view.convert(view.bounds, to: targetView)
    }
    
    private func restingFrame(of view: UIView, in targetView: UIView) -> CGRect {
        guard let superview = view.superview else {
            return view.convert(view.bounds, to: targetView)
        }
        
        let frame = CGRect(
            x: view.center.x - (view.bounds.width / 2),
            y: view.center.y - (view.bounds.height / 2),
            width: view.bounds.width,
            height: view.bounds.height
        )
        return superview.convert(frame, to: targetView)
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
            clearHorizontalFinishingViews()
            resetHorizontalTransition()
            delegate.addressBarGestureWillBegin()
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
        
        delegate.addressBarGestureWillBegin()
        delegate.presentTabOverviewFromGesture(animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddressBarGestures: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !(touch.view is UIButton) else {
            return false
        }
        
        guard gestureRecognizer.view !== addressBar,
              let delegate else {
            return true
        }
        
        let gestureFrame = restingFrame(of: addressBar, in: delegate.transitionContainerView)
            .insetBy(dx: 0, dy: -UX.addressBarPreviewOutsidePadding)
        return gestureFrame.contains(touch.location(in: delegate.transitionContainerView))
    }
}
