//
//  ContextMenuTabActions.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView

enum TabOpenDisposition {
    case currentTab
    case newTab
    case newPrivateTab
}

struct ContextMenuTabActions {
    private let tabManager: TabManager
    
    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }
    
    func openPreviewSession(
        _ session: GeckoSession,
        url: String,
        title: String?,
        disposition: TabOpenDisposition
    ) {
        switch disposition {
        case .currentTab:
            tabManager.replaceSelectedSession(with: session, url: url, title: title)
            
        case .newTab:
            tabManager.addTransferredSession(
                session,
                url: url,
                title: title,
                selecting: true,
                at: tabManager.index(for: .afterSelected, mode: tabManager.selectedTabMode),
                isPrivate: tabManager.selectedTabMode == .private
            )
            
        case .newPrivateTab:
            tabManager.addTransferredSession(
                session,
                url: url,
                title: title,
                selecting: true,
                at: tabManager.index(for: tabManager.selectedTabMode == .private ? .afterSelected : .end, mode: .private),
                isPrivate: true
            )
        }
    }
    
    func openURL(_ url: String, disposition: TabOpenDisposition) {
        switch disposition {
        case .currentTab:
            tabManager.browse(to: url)
            
        case .newTab:
            openURL(url, inNewTabFor: tabManager.selectedTabMode, target: .afterSelected)
            
        case .newPrivateTab:
            openURL(url, inNewTabFor: .private, target: tabManager.selectedTabMode == .private ? .afterSelected : .end)
        }
    }
    
    private func openURL(_ url: String, inNewTabFor mode: TabMode, target: TabInsertionTarget) {
        let tabIndex = tabManager.createTab(selecting: true, target: target, mode: mode)
        guard let tab = tabManager.activeTabs[safe: tabIndex] else {
            return
        }
        tabManager.browse(to: url, in: tab)
    }
}
