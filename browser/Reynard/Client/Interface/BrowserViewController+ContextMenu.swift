//
//  BrowserViewController+ContextMenu.swift
//  Reynard
//
//  Created by Minh Ton on 16/5/26.
//

import GeckoView
import ObjectiveC
import UIKit

final class ContextMenuContext {
    enum Target {
        case link(URL)
        case image(URL)
    }
    
    let target: Target
    let point: CGPoint
    
    init(target: Target, point: CGPoint) {
        self.target = target
        self.point = point
    }
}

private enum ContextMenuAssociatedKeys {
    static var pendingContextMenuContext = 0
    static var contextMenuInteraction = 0
    static var contextMenuViewController = 0
    static var isCommittingContextMenu = 0
    static var isPresentingContextMenu = 0
    static var haptic = 0
}

extension BrowserViewController: UIContextMenuInteractionDelegate {
    var pendingContextMenuContext: ContextMenuContext? {
        get {
            objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.pendingContextMenuContext) as? ContextMenuContext
        }
        set {
            objc_setAssociatedObject(self, &ContextMenuAssociatedKeys.pendingContextMenuContext, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var contextMenuInteraction: UIContextMenuInteraction? {
        get {
            objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.contextMenuInteraction) as? UIContextMenuInteraction
        }
        set {
            objc_setAssociatedObject(self, &ContextMenuAssociatedKeys.contextMenuInteraction, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var contextMenuViewController: LinkPreviewViewController? {
        get {
            objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.contextMenuViewController) as? LinkPreviewViewController
        }
        set {
            objc_setAssociatedObject(self, &ContextMenuAssociatedKeys.contextMenuViewController, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var isCommittingContextMenu: Bool {
        get {
            (objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.isCommittingContextMenu) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &ContextMenuAssociatedKeys.isCommittingContextMenu,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    private var isPresentingContextMenu: Bool {
        get {
            (objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.isPresentingContextMenu) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &ContextMenuAssociatedKeys.isPresentingContextMenu,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    private var presentHaptic: UIImpactFeedbackGenerator {
        if let existing = objc_getAssociatedObject(self, &ContextMenuAssociatedKeys.haptic) as? UIImpactFeedbackGenerator {
            return existing
        }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        objc_setAssociatedObject(self, &ContextMenuAssociatedKeys.haptic, generator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return generator
    }
    
    func configureContextMenu() {
        guard contextMenuInteraction == nil else {
            return
        }
        
        let interaction = UIContextMenuInteraction(delegate: self)
        browserUI.contentView.addWebViewInteraction(interaction)
        contextMenuInteraction = interaction
    }
    
    func presentContextMenu(at point: CGPoint, target: ContextMenuContext.Target) {
        let context = ContextMenuContext(target: target, point: point)
        presentContextMenu(context)
    }
    
    private func presentContextMenu(_ context: ContextMenuContext) {
        guard let interaction = contextMenuInteraction else {
            return
        }
        
        presentHaptic.prepare()
        closeContextMenu()
        pendingContextMenuContext = context
        isCommittingContextMenu = false
        isPresentingContextMenu = true
        
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            isPresentingContextMenu = false
            pendingContextMenuContext = nil
            return
        }
        
        presentHaptic.impactOccurred()
        _ = interaction.perform(selector, with: NSValue(cgPoint: context.point))
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard interaction === contextMenuInteraction,
              isPresentingContextMenu,
              let context = pendingContextMenuContext else {
            return nil
        }
        isPresentingContextMenu = false
        
        if let imageConfiguration = ImagePreviewMenu.configuration(
            for: context,
            presentingController: self,
            sourceView: browserUI.contentView
        ) {
            return imageConfiguration
        }
        
        return LinkPreviewMenu.configuration(
            for: context,
            isPrivate: tabManager.selectedTab?.isPrivate ?? false,
            onPreviewCreated: { [weak self] preview in
                self?.contextMenuViewController = preview
            },
            openInNewTab: { [weak self] in
                self?.openPreviewInNewTab()
            },
            openInNewPrivateTab: { [weak self] in
                self?.openPreviewInNewPrivateTab()
            },
            shareLink: { [weak self] url in
                self?.presentShareSheet(url: url.absoluteString)
            }
        )
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        animator.preferredCommitStyle = .pop
        guard interaction === contextMenuInteraction else {
            return
        }
        
        guard let preview = animator.previewViewController as? LinkPreviewViewController,
              let session = preview.releaseSessionForCommit() else {
            return
        }
        
        isCommittingContextMenu = true
        tabManager.replaceSession(with: session, url: preview.pageURL, title: preview.pageTitle)
        contextMenuViewController = nil
        
        animator.addCompletion { [weak self] in
            guard let self else {
                return
            }
            self.isCommittingContextMenu = false
            self.pendingContextMenuContext = nil
        }
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard interaction === contextMenuInteraction else {
            return nil
        }
        
        return makeTargetedPreview()
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard interaction === contextMenuInteraction else {
            return nil
        }
        
        return makeTargetedPreview()
    }
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        guard interaction === contextMenuInteraction else {
            return
        }
        
        guard let animator else {
            if !isCommittingContextMenu {
                closeContextMenu()
                restoreBrowserTabInteraction()
            } else {
                isCommittingContextMenu = false
            }
            pendingContextMenuContext = nil
            return
        }
        
        animator.addCompletion { [weak self] in
            guard let self else {
                return
            }
            if !self.isCommittingContextMenu {
                self.closeContextMenu()
                self.restoreBrowserTabInteraction()
            } else {
                self.isCommittingContextMenu = false
            }
            self.pendingContextMenuContext = nil
        }
    }
    
    private func openPreviewInNewTab() {
        guard let preview = contextMenuViewController,
              let session = preview.releaseSessionForCommit() else {
            return
        }
        
        isCommittingContextMenu = true
        let selectedIndex = tabManager.selectedTabIndex
        let activeTabs = tabManager.selectedTabMode == .private ? tabManager.privateTabs : tabManager.regularTabs
        let insertionIndex = selectedIndex >= 0 ? selectedIndex + 1 : activeTabs.count
        tabManager.addTab(
            using: session,
            url: preview.pageURL,
            title: preview.pageTitle,
            selecting: true,
            at: insertionIndex,
            isPrivate: tabManager.selectedTab?.isPrivate ?? false
        )
        contextMenuViewController = nil
    }
    
    private func openPreviewInNewPrivateTab() {
        guard let preview = contextMenuViewController else {
            return
        }
        
        let previewURL = preview.pageURL
        isCommittingContextMenu = true
        closeContextMenu()
        
        let insertionIndex = tabManager.selectedTabMode == .private ? tabManager.selectedTabIndex + 1 : tabManager.privateTabs.count
        let tabIndex = createTab(selecting: true, at: insertionIndex, isPrivate: true)
        guard tabManager.privateTabs.indices.contains(tabIndex) else {
            return
        }
        
        tabManager.browse(to: previewURL, in: tabManager.privateTabs[tabIndex])
        refreshAddressBar()
    }
    
    private func makeTargetedPreview() -> UITargetedPreview {
        let sourcePoint = pendingContextMenuContext?.point ?? CGPoint(
            x: browserUI.contentView.bounds.midX,
            y: browserUI.contentView.bounds.midY
        )
        let target = UIPreviewTarget(container: browserUI.contentView, center: sourcePoint)
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        return UITargetedPreview(view: view, parameters: parameters, target: target)
    }
    
    private func closeContextMenu() {
        contextMenuViewController?.closeSessionIfNeeded()
        contextMenuViewController = nil
    }
    
    private func restoreBrowserTabInteraction() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let session = self.tabManager.selectedTab?.session else {
                return
            }
            
            self.browserUI.contentView.restoreInteraction(for: session)
        }
    }
}
