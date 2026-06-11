//
//  OverlayCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import UIKit

final class OverlayCoordinator {
    enum Page: Hashable {
        case homepage
        case search
    }

    enum Host {
        case embedded
        case detached
    }

    private struct Entry {
        let page: Page
        let host: Host
        let controller: UIViewController
        let prepare: () -> Void
    }

    private unowned let controller: BrowserViewController
    private var activeEntry: Entry?
    private var previousEntry: Entry?

    init(controller: BrowserViewController) {
        self.controller = controller
    }

    func isPresented(_ page: Page) -> Bool {
        activeEntry?.page == page
    }

    func host(for page: Page) -> Host? {
        guard activeEntry?.page == page else {
            return nil
        }

        return activeEntry?.host
    }

    func present(
        _ viewController: UIViewController,
        for page: Page,
        on host: Host,
        animated: Bool,
        prepare: @escaping () -> Void = {}
    ) {
        let entry = Entry(page: page, host: host, controller: viewController, prepare: prepare)
        if activeEntry?.page == page {
            activate(entry, replacing: activeEntry, animated: animated)
            return
        }

        previousEntry = activeEntry
        activate(entry, replacing: activeEntry, animated: animated)
    }

    func dismiss(
        _ page: Page,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let activeEntry, activeEntry.page == page else {
            completion?()
            return
        }

        let nextEntry = previousEntry
        self.activeEntry = nextEntry
        previousEntry = nil

        guard let nextEntry else {
            hide(activeEntry.host, animated: animated, completion: completion)
            return
        }

        activate(nextEntry, replacing: activeEntry, animated: animated) {
            self.removeController(for: page, from: activeEntry.host)
            completion?()
        }
    }

    private func activate(
        _ entry: Entry,
        replacing currentEntry: Entry?,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        let showEntry = {
            entry.prepare()
            self.setController(entry.controller, for: entry.page, on: entry.host)
            self.show(entry.page, on: entry.host, animated: animated, completion: completion)
            self.activeEntry = entry
        }

        guard let currentEntry, currentEntry.host != entry.host else {
            showEntry()
            return
        }

        hide(currentEntry.host, animated: false, completion: showEntry)
    }

    private func hide(_ host: Host, animated: Bool, completion: (() -> Void)?) {
        switch host {
        case .embedded:
            controller.browserUI.contentView.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        case .detached:
            controller.browserUI.browserChrome.setOverlayPresentation(.hidden, animated: animated, completion: completion)
        }
    }

    private func setController(_ viewController: UIViewController, for page: Page, on host: Host) {
        switch host {
        case .embedded:
            controller.browserUI.contentView.setOverlayController(
                viewController,
                for: embeddedPage(for: page),
                in: controller
            )
        case .detached:
            controller.browserUI.browserChrome.setOverlayController(
                viewController,
                for: detachedPage(for: page),
                in: controller
            )
        }
    }

    private func removeController(for page: Page, from host: Host) {
        switch host {
        case .embedded:
            controller.browserUI.contentView.removeOverlayController(for: embeddedPage(for: page))
        case .detached:
            controller.browserUI.browserChrome.removeOverlayController(for: detachedPage(for: page))
        }
    }

    private func show(
        _ page: Page,
        on host: Host,
        animated: Bool,
        completion: (() -> Void)?
    ) {
        switch host {
        case .embedded:
            controller.browserUI.contentView.setOverlayPresentation(
                .visible(embeddedPage(for: page)),
                animated: animated,
                completion: completion
            )
        case .detached:
            controller.browserUI.browserChrome.setOverlayPresentation(
                .visible(detachedPage(for: page)),
                animated: animated,
                completion: completion
            )
        }
    }

    private func embeddedPage(for page: Page) -> OverlayContentView.Page {
        switch page {
        case .homepage: return .homepage
        case .search: return .search
        }
    }

    private func detachedPage(for page: Page) -> ChromeOverlayContentView.Page {
        switch page {
        case .homepage: return .homepage
        case .search: return .search
        }
    }
}
