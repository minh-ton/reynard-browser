//
//  AddressBarGestures.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol AddressBarGestureDelegate: TabListSource {
    var transitionContainerView: UIView { get }
    var transitionContentView: ContentView { get }
    var chromeMode: BrowserChromeMode { get }
    var isSearchFocused: Bool { get }
    var isTabOverviewPresented: Bool { get }
    var isTabOverviewTransitionRunning: Bool { get }
    
    func selectTabFromGesture(at index: Int, mode: TabMode)
    func pageBackgroundColor(for tab: Tab) -> UIColor
    func createTabForSwipe() -> Tab
    func setPendingTabExpansion(to tab: Tab?)
    func presentTabOverviewFromGesture(animated: Bool)
    func addressBarTransitionWillBegin(prepareForGesture: Bool)
    func addressBarTransitionDidEnd()
    func storedContentPreview(from tab: Tab) -> UIImage?
}

final class AddressBarGestures: NSObject {
    private enum UX {
        static let addressBarAutomaticNewTabTransitionDuration: TimeInterval = 0.2
        static let addressBarTabSwitchTransitionDuration: TimeInterval = 0.24
        static let addressBarTabSwitchCancellationDuration: TimeInterval = 0.22
        static let addressBarAutomaticNewTabTranslationRatio: CGFloat = 0.34
        static let addressBarPreviewOutsidePadding: CGFloat = 24
        static let addressBarPreviewCornerRadius: CGFloat = 22
        static let addressBarPreviewBorderWidth: CGFloat = 0.5
        static let addressBarPreviewShadowOpacity: Float = 0.18
        static let addressBarPreviewShadowRadius: CGFloat = 14
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
    private var horizontalSourceContentView: UIView?
    private var horizontalTargetContentView: UIView?
    private var horizontalSourceBarView: UIView?
    private var horizontalTargetBarView: UIView?
    private var horizontalFinishingViews: [UIView] = []
    private var transitionCompletion: (() -> Void)?
    private var horizontalTransitionGeneration = 0
    
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
    
    func resetHorizontalTransition(preservingLock: Bool = false) {
        horizontalTransitionGeneration += 1
        delegate?.transitionContentView.setTransitionTransform(.identity)
        delegate?.transitionContentView.setTransitionHidden(false)
        addressBar.isHidden = false
        addressBar.transform = .identity
        
        horizontalSourceContentView?.removeFromSuperview()
        horizontalTargetContentView?.removeFromSuperview()
        horizontalSourceBarView?.removeFromSuperview()
        horizontalTargetBarView?.removeFromSuperview()
        
        horizontalSourceContentView = nil
        horizontalTargetContentView = nil
        horizontalSourceBarView = nil
        horizontalTargetBarView = nil
        horizontalTargetIndex = nil
        horizontalDirection = 0
        if !preservingLock {
            delegate?.addressBarTransitionDidEnd()
        }
    }
    
    func performAfterTransition(_ completion: @escaping () -> Void) -> Bool {
        guard !horizontalFinishingViews.isEmpty else {
            return false
        }
        
        transitionCompletion = completion
        return true
    }
    
    private func clearHorizontalFinishingViews() {
        horizontalTransitionGeneration += 1
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
        delegate.addressBarTransitionWillBegin(prepareForGesture: false)
        
        let transitionGeneration = horizontalTransitionGeneration
        UIView.animate(withDuration: UX.addressBarAutomaticNewTabTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let transform = CGAffineTransform(
                translationX: -width * UX.addressBarAutomaticNewTabTranslationRatio,
                y: 0
            )
            delegate.transitionContentView.setTransitionTransform(transform)
            self.addressBar.transform = transform
        } completion: { _ in
            guard transitionGeneration == self.horizontalTransitionGeneration else {
                return
            }
            self.resetHorizontalTransition()
            completion()
        }
    }
    
    private func setupSourceContentPreview(delegate: AddressBarGestureDelegate) {
        guard horizontalSourceContentView == nil,
              delegate.transitionContentView.transform.isIdentity,
              let sourceTab = delegate.activeTabs[safe: delegate.selectedTabIndex],
              let previewImage = delegate.storedContentPreview(from: sourceTab),
              let captureGeometry = delegate.transitionContentView.thumbnailCaptureGeometry else {
            return
        }
        
        let sourcePreview = createContentPreview(image: previewImage, captureGeometry: captureGeometry)
        sourcePreview.frame = delegate.transitionContentView.frame
        sourcePreview.isUserInteractionEnabled = false
        delegate.transitionContainerView.insertSubview(sourcePreview, aboveSubview: delegate.transitionContentView)
        horizontalSourceContentView = sourcePreview
        delegate.transitionContentView.setTransitionTransform(.identity)
        delegate.transitionContentView.setTransitionHidden(true)
    }
    
    private func applySourceContentTransform(_ transform: CGAffineTransform, delegate: AddressBarGestureDelegate) {
        if let horizontalSourceContentView {
            horizontalSourceContentView.transform = transform
        } else {
            delegate.transitionContentView.setTransitionTransform(transform)
        }
    }
    
    func animateAutomaticTabTransition(to tab: Tab, returning: Bool = false, completion: @escaping () -> Void) {
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
        delegate.addressBarTransitionWillBegin(prepareForGesture: false)
        let direction = returning ? -1 : 1
        horizontalDirection = direction
        prepareHorizontalTarget(for: tab, direction: direction, pageWidth: width, delegate: delegate)
        
        let transitionGeneration = horizontalTransitionGeneration
        UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            let contentTransform = CGAffineTransform(translationX: -CGFloat(direction) * width, y: 0)
            let barTransform = CGAffineTransform(translationX: -CGFloat(direction) * self.horizontalBarTravelWidth(), y: 0)
            self.applySourceContentTransform(contentTransform, delegate: delegate)
            self.applySourceAddressBarTransform(barTransform)
            self.horizontalTargetContentView?.transform = contentTransform
            self.horizontalTargetBarView?.transform = barTransform
        } completion: { _ in
            guard transitionGeneration == self.horizontalTransitionGeneration else {
                return
            }
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
        container.layer.borderWidth = UX.addressBarPreviewBorderWidth
        container.layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor
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
    
    private func createContentPreview(
        image: UIImage?,
        captureGeometry: ContentView.ThumbnailCaptureGeometry
    ) -> UIView {
        let preview = UIView()
        
        if let image {
            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(
                x: -captureGeometry.visibleRect.minX,
                y: -captureGeometry.visibleRect.minY,
                width: captureGeometry.size.width,
                height: captureGeometry.size.height
            )
            imageView.contentMode = .scaleToFill
            preview.addSubview(imageView)
        }
        
        return preview
    }
    
    private func createBackgroundPreview(color: UIColor) -> UIView {
        let preview = UIView()
        preview.backgroundColor = color
        preview.isUserInteractionEnabled = false
        return preview
    }
    
    private func expandedPreviewFrame(
        _ previewFrame: CGRect,
        captureGeometry: ContentView.ThumbnailCaptureGeometry
    ) -> CGRect {
        return CGRect(
            x: previewFrame.minX - captureGeometry.visibleRect.minX,
            y: previewFrame.minY - captureGeometry.visibleRect.minY,
            width: captureGeometry.size.width,
            height: captureGeometry.size.height
        )
    }
    
    // MARK: - Interactive Tab Switching
    
    private func updateHorizontalTabInteraction(translationX: CGFloat) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let direction = translationX < 0 ? 1 : -1
        
        if horizontalDirection != direction {
            resetHorizontalTransition(preservingLock: true)
            horizontalDirection = direction
        }
        
        setupSourceContentPreview(delegate: delegate)
        
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
            let contentTranslation = clampedHorizontalTranslation(
                translationX * UX.addressBarEdgeSwipeTranslationDamping,
                travelWidth: delegate.transitionContentView.bounds.width,
                direction: direction
            )
            let barTranslation = clampedHorizontalTranslation(
                translationX * UX.addressBarEdgeSwipeTranslationDamping,
                travelWidth: horizontalBarTravelWidth(),
                direction: direction
            )
            let contentTransform = CGAffineTransform(translationX: contentTranslation, y: 0)
            applySourceContentTransform(contentTransform, delegate: delegate)
            applySourceAddressBarTransform(CGAffineTransform(translationX: barTranslation, y: 0))
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let contentTranslation = clampedHorizontalTranslation(
            translationX,
            travelWidth: width,
            direction: direction
        )
        let contentTransform = CGAffineTransform(translationX: contentTranslation, y: 0)
        applySourceContentTransform(contentTransform, delegate: delegate)
        horizontalTargetContentView?.transform = contentTransform
        
        let barTranslation = clampedHorizontalTranslation(
            translationX,
            travelWidth: horizontalBarTravelWidth(),
            direction: direction
        )
        let barTransform = CGAffineTransform(translationX: barTranslation, y: 0)
        applySourceAddressBarTransform(barTransform)
        horizontalTargetBarView?.transform = barTransform
    }
    
    private func finishHorizontalTabInteraction(translationX: CGFloat, velocityX: CGFloat) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let passedDistanceThreshold = abs(translationX) > width * UX.addressBarTabSwitchCompletionDistanceRatio
        let shouldSwitch = horizontalTargetIndex != nil && (passedDistanceThreshold || abs(velocityX) > UX.addressBarTabSwitchVelocityThreshold)
        let shouldCreateNewTab = delegate.chromeMode == .phone
        && horizontalTargetIndex == nil
        && delegate.selectedTabIndex == delegate.activeTabs.count - 1
        && delegate.activeTabs[safe: delegate.selectedTabIndex]?.url != nil
        && horizontalDirection == 1
        && (passedDistanceThreshold || velocityX < -UX.addressBarTabSwitchVelocityThreshold)
        
        if shouldSwitch, let targetIndex = horizontalTargetIndex {
            finishHorizontalTabSwitch(to: targetIndex, mode: delegate.selectedTabMode)
        } else if shouldCreateNewTab {
            Haptics.rigid()
            finishHorizontalNewTabSwipe(translationX: translationX)
        } else {
            let transitionGeneration = horizontalTransitionGeneration
            UIView.animate(withDuration: UX.addressBarTabSwitchCancellationDuration, delay: 0, options: [.curveEaseOut]) {
                self.applySourceContentTransform(.identity, delegate: delegate)
                self.applySourceAddressBarTransform(.identity)
                self.horizontalTargetContentView?.transform = .identity
                self.horizontalTargetBarView?.transform = .identity
            } completion: { _ in
                guard transitionGeneration == self.horizontalTransitionGeneration else {
                    return
                }
                self.resetHorizontalTransition()
            }
        }
    }
    
    private func finishHorizontalTabSwitch(to targetIndex: Int, mode: TabMode) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let sourcePreview = horizontalSourceContentView
        let storedContentPreview: UIView?
        if sourcePreview == nil,
           let sourceTab = delegate.activeTabs[safe: delegate.selectedTabIndex],
           let previewImage = delegate.storedContentPreview(from: sourceTab),
           let captureGeometry = delegate.transitionContentView.thumbnailCaptureGeometry {
            storedContentPreview = createContentPreview(
                image: previewImage,
                captureGeometry: captureGeometry
            )
        } else {
            storedContentPreview = nil
        }
        guard let outgoingPreview = sourcePreview
                ?? storedContentPreview
                ?? delegate.transitionContentView.snapshotView(afterScreenUpdates: false) else {
            resetHorizontalTransition()
            delegate.selectTabFromGesture(at: targetIndex, mode: mode)
            return
        }
        
        let contentWidth = delegate.transitionContentView.bounds.width
        let swipeDirection = horizontalDirection == 0
        ? (targetIndex >= delegate.selectedTabIndex ? 1 : -1)
        : horizontalDirection
        let transitionContainer = delegate.transitionContainerView
        let sourcePreviewView = sourcePreview ?? delegate.transitionContentView
        let targetPreview = horizontalTargetContentView
        let targetBar = horizontalTargetBarView
        let sourceBar = horizontalSourceBarView
        let outgoingBar = sourceBar ?? addressBar.snapshotView(afterScreenUpdates: false)
        let barHost = addressBar.superview
        let transitionClip = transitionClipView(for: delegate.transitionContentView, in: transitionContainer)
        let outgoingTranslation = CGFloat(-swipeDirection) * contentWidth
        let outgoingPreviewFinalFrame = transitionClip.bounds.offsetBy(dx: outgoingTranslation, dy: 0)
        let targetPreviewFinalFrame = transitionClip.bounds
        let captureGeometry = delegate.transitionContentView.thumbnailCaptureGeometry
        let sourceBackgroundColor = delegate.activeTabs[safe: delegate.selectedTabIndex]
            .map { delegate.pageBackgroundColor(for: $0) }
        ?? .systemBackground
        let targetBackgroundColor = delegate.activeTabs[safe: targetIndex]
            .map { delegate.pageBackgroundColor(for: $0) }
        ?? .systemBackground
        var outgoingBackground: UIView?
        var targetBackground: UIView?
        var outgoingBarFinalFrame: CGRect?
        
        transitionContainer.insertSubview(transitionClip, aboveSubview: delegate.transitionContentView)
        horizontalFinishingViews.append(transitionClip)
        
        let outgoingPreviewFrame = transitionClip.convert(
            presentationFrame(of: sourcePreviewView, in: transitionContainer),
            from: transitionContainer
        )
        outgoingPreview.transform = .identity
        outgoingPreview.frame = outgoingPreviewFrame
        outgoingPreview.isUserInteractionEnabled = false
        
        if let targetPreview {
            let targetPreviewFrame = transitionClip.convert(
                presentationFrame(of: targetPreview, in: transitionContainer),
                from: transitionContainer
            )
            targetPreview.transform = .identity
            targetPreview.frame = targetPreviewFrame
            targetPreview.isUserInteractionEnabled = false
        }
        if let captureGeometry {
            outgoingBackground = createBackgroundPreview(color: sourceBackgroundColor)
            outgoingBackground?.frame = expandedPreviewFrame(
                outgoingPreview.frame,
                captureGeometry: captureGeometry
            )
            targetBackground = createBackgroundPreview(color: targetBackgroundColor)
            targetBackground?.frame = expandedPreviewFrame(
                targetPreview?.frame ?? targetPreviewFinalFrame,
                captureGeometry: captureGeometry
            )
        }
        if let outgoingBackground {
            transitionClip.addSubview(outgoingBackground)
            horizontalFinishingViews.append(outgoingBackground)
        }
        if let targetBackground {
            transitionClip.addSubview(targetBackground)
            horizontalFinishingViews.append(targetBackground)
        }
        transitionClip.addSubview(outgoingPreview)
        if let targetPreview {
            transitionClip.addSubview(targetPreview)
        }
        
        if let outgoingBar, let barHost {
            let outgoingBarFrame = presentationPositionFrame(of: sourceBar ?? addressBar, in: barHost)
            let outgoingBarRestingFrame = restingFrame(of: sourceBar ?? addressBar, in: barHost)
            let finalBarTranslation = CGFloat(-swipeDirection) * horizontalBarTravelWidth(in: barHost)
            outgoingBar.transform = .identity
            outgoingBar.frame = outgoingBarFrame
            outgoingBar.isUserInteractionEnabled = false
            outgoingBarFinalFrame = outgoingBarRestingFrame.offsetBy(dx: finalBarTranslation, dy: 0)
            barHost.addSubview(outgoingBar)
            barHost.bringSubviewToFront(outgoingBar)
            horizontalFinishingViews.append(outgoingBar)
        }
        
        if let targetBar, let barHost {
            let targetBarFrame = presentationPositionFrame(of: targetBar, in: barHost)
            targetBar.transform = .identity
            targetBar.frame = targetBarFrame
            targetBar.isUserInteractionEnabled = false
            barHost.addSubview(targetBar)
            barHost.bringSubviewToFront(targetBar)
            horizontalFinishingViews.append(targetBar)
        }
        
        horizontalTargetContentView = nil
        horizontalSourceContentView = nil
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
        
        let transitionGeneration = horizontalTransitionGeneration
        UIView.animate(withDuration: UX.addressBarTabSwitchTransitionDuration, delay: 0, options: [.curveEaseOut]) {
            outgoingPreview.frame = outgoingPreviewFinalFrame
            targetPreview?.frame = targetPreviewFinalFrame
            if let captureGeometry {
                outgoingBackground?.frame = self.expandedPreviewFrame(
                    outgoingPreviewFinalFrame,
                    captureGeometry: captureGeometry
                )
                targetBackground?.frame = self.expandedPreviewFrame(
                    targetPreviewFinalFrame,
                    captureGeometry: captureGeometry
                )
            }
            if let outgoingBarFinalFrame {
                outgoingBar?.frame = outgoingBarFinalFrame
            }
            if let targetBarFinalFrame {
                targetBar?.frame = targetBarFinalFrame
            }
        } completion: { _ in
            transitionClip.removeFromSuperview()
            outgoingBar?.removeFromSuperview()
            targetBar?.removeFromSuperview()
            self.horizontalFinishingViews.removeAll { view in
                view === transitionClip
                || view === outgoingBackground
                || view === targetBackground
                || view === outgoingBar
                || view === targetBar
            }
            guard transitionGeneration == self.horizontalTransitionGeneration else {
                return
            }
            delegate.transitionContentView.setTransitionHidden(false)
            self.addressBar.isHidden = false
            self.delegate?.addressBarTransitionDidEnd()
            self.runTransitionCompletion()
        }
    }
    
    private func finishHorizontalNewTabSwipe(translationX: CGFloat) {
        guard let delegate else {
            resetHorizontalTransition()
            return
        }
        
        let width = delegate.transitionContentView.bounds.width
        let barPresentationTranslation: CGFloat
        if let barHost = addressBar.superview {
            let barPresentationFrame = presentationPositionFrame(of: addressBar, in: barHost)
            let barRestingFrame = restingFrame(of: addressBar, in: barHost)
            barPresentationTranslation = clampedHorizontalTranslation(
                barPresentationFrame.midX - barRestingFrame.midX,
                travelWidth: horizontalBarTravelWidth(in: barHost, fallbackWidth: width),
                direction: 1
            )
        } else {
            barPresentationTranslation = clampedHorizontalTranslation(
                translationX * UX.addressBarEdgeSwipeTranslationDamping,
                travelWidth: width,
                direction: 1
            )
        }
        let mode = delegate.selectedTabMode
        let createdTab = delegate.createTabForSwipe()
        delegate.setPendingTabExpansion(to: createdTab)
        guard let createdIndex = delegate.activeTabs.firstIndex(where: { $0 === createdTab }) else {
            resetHorizontalTransition()
            return
        }
        
        horizontalTargetIndex = createdIndex
        horizontalDirection = 1
        
        prepareHorizontalTarget(for: createdTab, direction: 1, pageWidth: width, delegate: delegate)
        applySourceAddressBarTransform(CGAffineTransform(translationX: barPresentationTranslation, y: 0))
        
        finishHorizontalTabSwitch(to: createdIndex, mode: mode)
    }
    
    private func prepareHorizontalTarget(for tab: Tab, direction: Int, pageWidth: CGFloat, delegate: AddressBarGestureDelegate) {
        guard let captureGeometry = delegate.transitionContentView.thumbnailCaptureGeometry else {
            return
        }
        
        let targetPreview = createContentPreview(
            image: tab.thumbnail,
            captureGeometry: captureGeometry
        )
        targetPreview.frame = delegate.transitionContentView.frame.offsetBy(dx: CGFloat(direction) * pageWidth, dy: 0)
        delegate.transitionContainerView.insertSubview(targetPreview, belowSubview: delegate.transitionContentView)
        horizontalTargetContentView = targetPreview
        
        guard let barHost = addressBar.superview else {
            return
        }
        
        let barFrame = restingFrame(of: addressBar, in: barHost)
        
        if horizontalSourceBarView == nil,
           let sourceTab = delegate.activeTabs[safe: delegate.selectedTabIndex] {
            let sourceBar = createAddressBarPreview(for: sourceTab)
            sourceBar.frame = barFrame
            sourceBar.layoutIfNeeded()
            sourceBar.isUserInteractionEnabled = false
            barHost.addSubview(sourceBar)
            barHost.bringSubviewToFront(sourceBar)
            horizontalSourceBarView = sourceBar
            addressBar.isHidden = true
        }
        
        let targetBar = createAddressBarPreview(for: tab)
        targetBar.frame = barFrame.offsetBy(
            dx: CGFloat(direction) * horizontalBarTravelWidth(in: barHost, fallbackWidth: pageWidth),
            dy: 0
        )
        targetBar.layoutIfNeeded()
        barHost.addSubview(targetBar)
        horizontalTargetBarView = targetBar
    }
    
    private func applySourceAddressBarTransform(_ transform: CGAffineTransform) {
        if let horizontalSourceBarView {
            horizontalSourceBarView.transform = transform
        } else {
            addressBar.transform = transform
        }
    }
    
    private func horizontalBarTravelWidth() -> CGFloat {
        guard let barHost = addressBar.superview else {
            return addressBar.bounds.width
        }
        
        return horizontalBarTravelWidth(in: barHost)
    }
    
    private func horizontalBarTravelWidth(in barHost: UIView, fallbackWidth: CGFloat? = nil) -> CGFloat {
        if barHost.bounds.width > 1 {
            return barHost.bounds.width
        }
        
        if let fallbackWidth, fallbackWidth > 1 {
            return fallbackWidth
        }
        
        return max(addressBar.bounds.width, 1)
    }
    
    private func clampedHorizontalTranslation(_ translationX: CGFloat, travelWidth: CGFloat, direction: Int) -> CGFloat {
        guard travelWidth > 1 else {
            return translationX
        }
        
        switch direction {
        case let direction where direction > 0:
            return min(0, max(-travelWidth, translationX))
        case let direction where direction < 0:
            return max(0, min(travelWidth, translationX))
        default:
            return max(-travelWidth, min(travelWidth, translationX))
        }
    }
    
    private func transitionClipView(for view: UIView, in targetView: UIView) -> UIView {
        let clipView = UIView(frame: restingFrame(of: view, in: targetView))
        clipView.backgroundColor = .clear
        clipView.clipsToBounds = false
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
    
    private func presentationPositionFrame(of view: UIView, in targetView: UIView) -> CGRect {
        var frame = restingFrame(of: view, in: targetView)
        let presentationFrame = presentationFrame(of: view, in: targetView)
        frame.origin.x = presentationFrame.midX - (frame.width / 2)
        frame.origin.y = presentationFrame.midY - (frame.height / 2)
        return frame
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
            delegate.addressBarTransitionWillBegin(prepareForGesture: true)
            Haptics.prepareRigid()
            
        case .changed:
            if searchPanMode == .undecided {
                if abs(translation.x) < UX.addressBarPanDirectionDetectionThreshold,
                   abs(translation.y) < UX.addressBarPanDirectionDetectionThreshold {
                    return
                }
                
                if abs(translation.x) > abs(translation.y) {
                    let newMode: SearchPanMode = (
                        !delegate.isTabOverviewPresented &&
                        !delegate.isSearchFocused &&
                        Prefs.AppearanceSettings.swipeAddressBarSidewaysEnabled
                    ) ? .horizontalTabs : .blocked
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
              !delegate.isTabOverviewTransitionRunning,
              Prefs.AppearanceSettings.swipeAddressBarUpEnabled else {
            return
        }
        
        delegate.addressBarTransitionWillBegin(prepareForGesture: false)
        delegate.presentTabOverviewFromGesture(animated: true)
        delegate.addressBarTransitionDidEnd()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddressBarGestures: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !(touch.view is UIButton) else {
            return false
        }
        
        var view: UIView? = addressBar
        while let currentView = view {
            guard !currentView.isHidden, currentView.alpha > 0.01 else {
                return false
            }
            view = currentView.superview
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
