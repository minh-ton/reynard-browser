//
//  ContextMenuCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

final class ContextMenuCoordinator: NSObject {
    // MARK: - State

    private weak var browserViewController: BrowserViewController?
    private var pendingContext: ContextMenuContext?
    private var interaction: UIContextMenuInteraction?
    private var linkPreview: LinkPreviewViewController?
    private var isCommitting = false
    private var isPresenting = false

    // MARK: - Lifecycle

    init(browserViewController: BrowserViewController) {
        self.browserViewController = browserViewController
        super.init()
    }

    // MARK: - Configuration

    func configure() {
        guard interaction == nil,
              let browserViewController else {
            return
        }

        let interaction = UIContextMenuInteraction(delegate: self)
        browserViewController.contentView.addWebViewInteraction(interaction)
        self.interaction = interaction
    }

    // MARK: - Presentation

    func present(at point: CGPoint, target: ContextMenuContext.Target) {
        guard let interaction else {
            return
        }

        let context = ContextMenuContext(target: target, point: point)
        closePreview()
        pendingContext = context
        isCommitting = false
        isPresenting = true

        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            isPresenting = false
            pendingContext = nil
            return
        }

        let presentHaptic = UIImpactFeedbackGenerator(style: .rigid)
        presentHaptic.impactOccurred()
        _ = interaction.perform(selector, with: NSValue(cgPoint: context.point))
    }

    // MARK: - Link Actions

    private func openLinkPreviewInNewTab() {
        guard let browserViewController,
              let preview = linkPreview,
              let session = preview.releaseSession() else {
            return
        }

        isCommitting = true
        let selectedIndex = browserViewController.tabManager.selectedTabIndex
        let activeTabs = browserViewController.tabManager.selectedTabMode == .private
            ? browserViewController.tabManager.privateTabs
            : browserViewController.tabManager.regularTabs
        let insertionIndex = selectedIndex >= 0 ? selectedIndex + 1 : activeTabs.count
        browserViewController.tabManager.addTab(
            using: session,
            url: preview.pageURL,
            title: preview.pageTitle,
            selecting: true,
            at: insertionIndex,
            isPrivate: browserViewController.tabManager.selectedTab?.isPrivate ?? false
        )
        linkPreview = nil
    }

    private func openLinkPreviewInNewPrivateTab() {
        guard let browserViewController,
              let preview = linkPreview else {
            return
        }

        let previewURL = preview.pageURL
        isCommitting = true
        closePreview()

        let insertionIndex = browserViewController.tabManager.selectedTabMode == .private
            ? browserViewController.tabManager.selectedTabIndex + 1
            : browserViewController.tabManager.privateTabs.count
        let tabIndex = browserViewController.createTab(selecting: true, at: insertionIndex, isPrivate: true)
        guard browserViewController.tabManager.privateTabs.indices.contains(tabIndex) else {
            return
        }

        browserViewController.tabManager.browse(to: previewURL, in: browserViewController.tabManager.privateTabs[tabIndex])
        browserViewController.refreshAddressBar()
    }

    // MARK: - Preview

    private func makeTargetedPreview() -> UITargetedPreview? {
        guard let browserViewController else {
            return nil
        }

        let sourcePoint = pendingContext?.point ?? CGPoint(
            x: browserViewController.contentView.bounds.midX,
            y: browserViewController.contentView.bounds.midY
        )
        let target = UIPreviewTarget(container: browserViewController.contentView, center: sourcePoint)
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        return UITargetedPreview(view: view, parameters: parameters, target: target)
    }

    // MARK: - Cleanup

    private func closePreview() {
        linkPreview?.closeSession()
        linkPreview = nil
    }

    private func restoreSelectedTabInteraction() {
        DispatchQueue.main.async { [weak self] in
            guard let browserViewController = self?.browserViewController,
                  let session = browserViewController.tabManager.selectedTab?.session else {
                return
            }

            browserViewController.contentView.restoreInteraction(for: session)
        }
    }

    private func endPresentation() {
        if !isCommitting {
            closePreview()
            restoreSelectedTabInteraction()
        } else {
            isCommitting = false
        }
        pendingContext = nil
    }
}

extension ContextMenuCoordinator: UIContextMenuInteractionDelegate {
    // MARK: - UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard interaction === self.interaction,
              isPresenting,
              let context = pendingContext,
              let browserViewController else {
            return nil
        }
        isPresenting = false

        if let imageConfiguration = ImagePreviewMenu.configuration(
            for: context,
            presentingController: browserViewController,
            sourceView: browserViewController.contentView
        ) {
            return imageConfiguration
        }

        return LinkPreviewMenu.configuration(
            for: context,
            isPrivate: browserViewController.tabManager.selectedTab?.isPrivate ?? false,
            onPreviewCreated: { [weak self] preview in
                self?.linkPreview = preview
            },
            openInNewTab: { [weak self] in
                self?.openLinkPreviewInNewTab()
            },
            openInNewPrivateTab: { [weak self] in
                self?.openLinkPreviewInNewPrivateTab()
            },
            shareLink: { [weak browserViewController] url in
                browserViewController?.presentShareSheet(url: url.absoluteString)
            }
        )
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        animator.preferredCommitStyle = .pop
        guard interaction === self.interaction,
              let browserViewController,
              let preview = animator.previewViewController as? LinkPreviewViewController,
              let session = preview.releaseSession() else {
            return
        }

        isCommitting = true
        browserViewController.tabManager.replaceSession(with: session, url: preview.pageURL, title: preview.pageTitle)
        linkPreview = nil

        animator.addCompletion { [weak self] in
            self?.isCommitting = false
            self?.pendingContext = nil
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard interaction === self.interaction else {
            return nil
        }

        return makeTargetedPreview()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard interaction === self.interaction else {
            return nil
        }

        return makeTargetedPreview()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        guard interaction === self.interaction else {
            return
        }

        guard let animator else {
            endPresentation()
            return
        }

        animator.addCompletion { [weak self] in
            self?.endPresentation()
        }
    }
}
